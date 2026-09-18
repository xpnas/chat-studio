import '../../l10n.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../../data/compression_settings.dart';

/// Wait for the exit animation before callers dispose their form controllers.
Future<T?> showSettingsSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) async {
  final navigator = Navigator.of(context);
  final route = ModalBottomSheetRoute<T>(
    builder: builder,
    capturedThemes: InheritedTheme.capture(
      from: context,
      to: navigator.context,
    ),
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
  );
  final result = await navigator.push(route);
  await route.completed;
  return result;
}

class SettingsSheet extends StatelessWidget {
  const SettingsSheet({
    super.key,
    required this.title,
    required this.content,
    this.actions = const [],
  });
  final Widget title, content;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .78,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: DefaultTextStyle.merge(
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
                child: title,
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: content,
              ),
            ),
            if (actions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                child: OverflowBar(
                  alignment: MainAxisAlignment.end,
                  spacing: 8,
                  overflowSpacing: 4,
                  children: actions,
                ),
              )
            else
              const SizedBox(height: 16),
          ],
        ),
      ),
    ),
  );
}

String? validateJsonObject(String value) {
  try {
    if (jsonDecode(value) is! Map) return '配置必须是 JSON 对象';
    return null;
  } on FormatException catch (error) {
    return error.message;
  }
}

Future<String?> showSettingsTextEditor({
  required BuildContext context,
  required String title,
  required String label,
  required String initialValue,
  String? Function(String)? validator,
}) => showDialog<String>(
  context: context,
  useSafeArea: false,
  barrierDismissible: false,
  builder: (_) => _SettingsTextEditor(
    title: title,
    label: label,
    initialValue: initialValue,
    validator: validator,
  ),
);

class _SettingsTextEditor extends StatefulWidget {
  const _SettingsTextEditor({
    required this.title,
    required this.label,
    required this.initialValue,
    this.validator,
  });
  final String title, label, initialValue;
  final String? Function(String)? validator;
  @override
  State<_SettingsTextEditor> createState() => _SettingsTextEditorState();
}

class _SettingsTextEditorState extends State<_SettingsTextEditor> {
  late final input = TextEditingController(text: widget.initialValue);
  String? error;
  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  void save() {
    final problem = widget.validator?.call(input.text);
    if (problem != null) {
      setState(() => error = problem);
      return;
    }
    Navigator.pop(context, input.text);
  }

  @override
  Widget build(BuildContext context) => Dialog.fullscreen(
    child: Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        leading: IconButton(
          tooltip: context.tr("取消编辑"),
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [TextButton(onPressed: save, child: Text(context.tr("保存")))],
      ),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(15, 8, 15, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.label, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 12),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              Expanded(
                child: TextField(
                  key: const Key('settings-text-input'),
                  controller: input,
                  expands: true,
                  minLines: null,
                  maxLines: null,
                  textAlignVertical: TextAlignVertical.top,
                  keyboardType: TextInputType.multiline,
                  autocorrect: false,
                  enableSuggestions: false,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 14,
                    height: 1.5,
                  ),
                  decoration: InputDecoration(hintText: context.tr("输入配置内容")),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class CompressionSettingsSheet extends StatefulWidget {
  const CompressionSettingsSheet({super.key, required this.settings});
  final CompressionSettings settings;
  @override
  State<CompressionSettingsSheet> createState() =>
      _CompressionSettingsSheetState();
}

class _CompressionSettingsSheetState extends State<CompressionSettingsSheet> {
  late bool enabled = widget.settings.enabled;
  late final threshold = TextEditingController(text: widget.settings.percent);
  String? error;
  @override
  void dispose() {
    threshold.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SettingsSheet(
    title: Text(context.tr("上下文自动压缩")),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          context.tr(
            "作用于当前 Profile 下 Hermes / Ekko 对话发送给模型的历史上下文：达到阈值后生成摘要并保留部分原始消息，不删除聊天记录。\nCodex、Claude 等外部 CLI 的原生压缩不由此开关控制。\n这里显示配置策略，不是当前会话的压缩进度或成功状态；已有摘要、手动 /compact 与运行时强制压缩是另外的机制。",
          ),
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(context.tr("启用自动压缩")),
          value: enabled,
          onChanged: (value) => setState(() => enabled = value),
        ),
        TextField(
          key: const Key('compression-threshold'),
          controller: threshold,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: context.tr("触发阈值（上下文窗口占比）"),
            suffixText: '%',
            helperText: context.tr("5%–95%，服务端默认 50%；不是 Token 数量"),
            errorText: error,
          ),
        ),
        const SizedBox(height: 12),
        Text(context.tr("保存到当前 Profile，后续上下文组装读取新策略；不会立即压缩当前会话。")),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.tr("取消")),
      ),
      FilledButton(
        onPressed: () {
          final value = double.tryParse(threshold.text.trim());
          if (value == null || !value.isFinite || value < 5 || value > 95) {
            setState(() => error = context.tr("请输入 5–95 之间的百分比"));
            return;
          }
          Navigator.pop(context, <String, dynamic>{
            'enabled': enabled,
            'threshold': value / 100,
          });
        },
        child: Text(context.tr("保存")),
      ),
    ],
  );
}
