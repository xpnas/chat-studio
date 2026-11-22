import 'package:flutter/material.dart';
import '../l10n.dart';
import '../data/models.dart';
import '../data/person_api.dart';
import '../data/person_models.dart';
import '../data/studio_api.dart';
import '../state/app_controller.dart';
import 'widgets/person_model_picker.dart';

class PersonCreateScreen extends StatefulWidget {
  const PersonCreateScreen({
    super.key,
    required this.app,
    required this.api,
    required this.account,
    required this.valid,
  });
  final AppController app;
  final StudioApi api;
  final Object account;
  final bool Function() valid;
  @override
  State<PersonCreateScreen> createState() => _PersonCreateScreenState();
}

class _PersonCreateScreenState extends State<PersonCreateScreen> {
  final name = TextEditingController(), workspace = TextEditingController();
  PersonDefaults? defaults;
  PersonModelChoice? model;
  bool loading = true, saving = false, uncertain = false;
  String? error;
  @override
  void initState() {
    super.initState();
    widget.app.addListener(scopeChanged);
    load();
  }

  void scopeChanged() {
    if (!widget.valid()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final route = ModalRoute.of(context);
        if (route != null) Navigator.of(context).removeRoute(route);
      });
    }
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final next = await widget.api.personDefaults();
      if (mounted && widget.valid()) {
        setState(() {
          defaults = next;
          model ??= next.model;
        });
      }
    } catch (_) {
      if (mounted && widget.valid()) setState(() => error = 'BOT 默认配置加载失败，请重试');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> pickModel() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final next = await showPersonModelPicker(
      context,
      api: widget.api,
      scopeChanges: widget.app,
      valid: widget.valid,
      selected: model,
    );
    if (mounted && widget.valid() && next != null) setState(() => model = next);
  }

  Future<void> create() async {
    if (saving ||
        uncertain ||
        loading ||
        defaults == null ||
        name.text.trim().isEmpty ||
        name.text.trim().length > 100 ||
        model == null ||
        !widget.valid()) {
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final bot = await widget.api.createPersonConversation(
        widget.account,
        title: name.text,
        revision: defaults!.revision,
        model: model,
        workspace: workspace.text,
      );
      if (mounted && widget.valid()) Navigator.pop(context, bot);
    } catch (e) {
      if (!mounted || !widget.valid()) return;
      final rejected = e is ApiException && e.status >= 400 && e.status < 500;
      if (rejected) {
        // Preserve the user's input, but refresh the shared-default revision.
        final message = e.toString();
        await load();
        if (mounted) setState(() => error = message);
      } else {
        // Creation has no server idempotency key. An unknown outcome must be
        // checked in the list before the user starts another creation.
        setState(() {
          uncertain = true;
          error = '创建结果待确认，请返回列表刷新后检查';
        });
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  void dispose() {
    widget.app.removeListener(scopeChanged);
    name.dispose();
    workspace.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !saving,
    child: Scaffold(
      appBar: AppBar(title: Text(context.tr('新建 BOT 对话'))),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      if (loading) const LinearProgressIndicator(),
                      TextField(
                        key: const Key('bot-name-input'),
                        controller: name,
                        enabled: !saving && !uncertain,
                        maxLength: 100,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          labelText: context.tr('BOT 名称'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      ListTile(
                        key: const Key('new-bot-model'),
                        contentPadding: EdgeInsets.zero,
                        title: Text(context.tr('使用模型')),
                        subtitle: Text(
                          model == null
                              ? context.tr('选择模型')
                              : '${model!.label} · ${model!.profile}',
                        ),
                        trailing: const Icon(Icons.expand_more_rounded),
                        onTap: !saving && !uncertain && !loading
                            ? pickModel
                            : null,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        key: const Key('bot-workspace-input'),
                        controller: workspace,
                        enabled: !saving && !uncertain,
                        decoration: InputDecoration(
                          labelText: context.tr('工作区（可选）'),
                          helperText: context.tr('留空时自动创建工作区'),
                        ),
                      ),
                      if (error != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Text(
                            context.tr(error!),
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      if (defaults == null && !loading)
                        TextButton(
                          onPressed: load,
                          child: Text(context.tr('重试')),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  child: SizedBox(
                    width: double.infinity,
                    child: uncertain
                        ? FilledButton(
                            onPressed: () => Navigator.pop(context),
                            child: Text(context.tr('返回列表')),
                          )
                        : FilledButton.icon(
                            key: const Key('create-bot-button'),
                            onPressed:
                                !saving &&
                                    !loading &&
                                    defaults != null &&
                                    model != null &&
                                    name.text.trim().isNotEmpty
                                ? create
                                : null,
                            icon: saving
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.add_rounded),
                            label: Text(context.tr(saving ? '正在创建…' : '创建')),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
