import '../../l10n.dart';
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../data/mobile_media.dart';
import '../../data/models.dart';
import '../../state/app_controller.dart';
import '../../state/conversation_state.dart';
import 'reading_handle.dart';
import 'model_sheet.dart';
import 'slash_command_picker.dart';
import 'package:flutter/foundation.dart';

typedef ComposerLayoutBuilder =
    Widget Function(Widget editor, Widget? readingHandle, Widget? stopButton);

/// Native pickers/recorder; no upload until Send (or Finish for speech).
class ChatComposer extends StatefulWidget {
  const ChatComposer({
    super.key,
    required this.controller,
    required this.input,
    this.media,
    this.collapsed = false,
    this.onExpand,
    this.readingProgress = const AlwaysStoppedAnimation<double>(0),
    this.layoutBuilder,
  });
  final AppController controller;
  final TextEditingController input;
  final MediaAccess? media;
  final bool collapsed;
  final VoidCallback? onExpand;
  final ValueListenable<double> readingProgress;
  final ComposerLayoutBuilder? layoutBuilder;
  @override
  State<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends State<ChatComposer>
    with WidgetsBindingObserver {
  late final MediaAccess _media = widget.media ?? NativeMediaAccess();
  late ConversationDraft _draft;
  List<LocalAttachment> get _attachments => _draft.files;
  final _focus = FocusNode();
  String _phase = '';
  String? _inlineError;
  double _uploadProgress = 0;
  double _level = 0;
  int _lastAudibleSecond = 0;
  StreamSubscription<double>? _levels;
  int _retryRevision = 0;
  List<MessageAttachment> get _remoteAttachments => _draft.uploaded;
  int _operation = 0, _seconds = 0;
  Timer? _timer;
  Completer<void>? _cancel;
  AppController get c => widget.controller;
  bool get _busy => _phase.isNotEmpty;
  @override
  void initState() {
    super.initState();
    _focus.addListener(_focusChanged);
    _retryRevision = c.retryRevision;
    _draft = c.draft;
    if (_draft.text.isNotEmpty) {
      widget.input.text = _draft.text;
    } else {
      _draft.text = widget.input.text;
    }
    widget.input.addListener(_saveDraft);
    c.addListener(_contextChanged);
    WidgetsBinding.instance.addObserver(this);
  }

  void _focusChanged() {
    if (mounted) setState(() {});
  }

  void _saveDraft() => _draft.text = widget.input.text;

  void _contextChanged() {
    if (!identical(_draft, c.draft)) {
      _abort();
      _focus.unfocus();
      _draft = c.draft;
      _retryRevision = c.retryRevision;
      _inlineError = null;
      widget.input.value = TextEditingValue(
        text: _draft.text,
        selection: TextSelection.collapsed(offset: _draft.text.length),
      );
      if (mounted) setState(() {});
      return;
    }
    if (_retryRevision != c.retryRevision) {
      _retryRevision = c.retryRevision;
      if (_busy ||
          widget.input.text.isNotEmpty ||
          _attachments.isNotEmpty ||
          _remoteAttachments.isNotEmpty) {
        setState(() => _inlineError = context.tr("请先完成当前操作或清空现有草稿，再恢复失败消息"));
        return;
      }
      widget.input.text = c.retryInput ?? '';
      widget.input.selection = TextSelection.collapsed(
        offset: widget.input.text.length,
      );
      _remoteAttachments
        ..clear()
        ..addAll(MessageAttachment.parse(c.retryAttachments));
      setState(() => _inlineError = null);
      widget.onExpand?.call();
      _focus.requestFocus();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Permission prompts/pickers can be inactive; cancel active recording on background.
    if (state == AppLifecycleState.paused &&
        (_phase == context.tr("录音中") || _phase == context.tr("准备录音"))) {
      _abort();
    }
  }

  void _abort() {
    final operation = ++_operation;
    _timer?.cancel();
    _levels?.cancel();
    _levels = null;
    if (_cancel?.isCompleted == false) _cancel!.complete();
    _cancel = null;
    final voice = [
      context.tr("录音中"),
      context.tr("识别中"),
      context.tr("准备录音"),
      context.tr("取消中"),
    ].contains(_phase);
    if (mounted) setState(() => _phase = voice ? context.tr("取消中") : '');
    if (voice) {
      unawaited(
        _media.cancelRecording().catchError((Object _) {}).whenComplete(() {
          if (_valid(operation)) setState(() => _phase = '');
        }),
      );
    }
  }

  bool _valid(int operation) => mounted && operation == _operation;
  void _error(Object error) {
    if (mounted) {
      setState(() => _inlineError = '$error');
    }
  }

  @override
  void dispose() {
    c.removeListener(_contextChanged);
    widget.input.removeListener(_saveDraft);
    _focus.removeListener(_focusChanged);
    _focus.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _operation++;
    _timer?.cancel();
    if (_cancel?.isCompleted == false) _cancel!.complete();
    _levels?.cancel();
    unawaited(_media.dispose().catchError((Object _) {}));
    super.dispose();
  }

  Future<void> _models() async {
    final draft = c.draft;
    final selected = await showModalBottomSheet<ModelChoice>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) =>
          ModelSheet(models: c.models, selected: c.selectedModel),
    );
    if (mounted && identical(draft, c.draft) && selected != null) {
      await c.chooseModel(selected);
    }
  }

  Future<void> _reasoning() async {
    final draft = c.draft;
    final chosen = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (context) => SizedBox(
        height: MediaQuery.sizeOf(context).height * .7,
        child: Column(
          children: [
            Text(
              context.tr("思考深度"),
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Text(
                context.tr("实际效果取决于服务端引擎与模型支持；更深的思考可能更慢。"),
                style: TextStyle(fontSize: 12),
              ),
            ),
            Expanded(
              child: ListView(
                children: [
                  for (final entry in reasoningEffortLabels.entries)
                    ListTile(
                      key: ValueKey('reasoning:${entry.key}'),
                      selected: c.reasoningEffort == entry.key,
                      title: Text(context.tr(entry.value)),
                      subtitle: entry.key.isEmpty
                          ? Text(context.tr("使用服务端 / 模型默认值"))
                          : null,
                      trailing: c.reasoningEffort == entry.key
                          ? const Icon(Icons.check_rounded)
                          : null,
                      onTap: () => Navigator.pop(context, entry.key),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (chosen != null && identical(draft, c.draft)) {
      await c.chooseReasoningEffort(chosen);
    }
  }

  Future<void> _pick() async {
    final operation = ++_operation;
    final attachmentLimitError = context.tr(
      "最多 5 个非空附件，单个不超过 20 MB，总计不超过 40 MB",
    );
    setState(() => _phase = context.tr("选择附件"));
    try {
      final images = await showModalBottomSheet<bool>(
        context: context,
        showDragHandle: true,
        useSafeArea: true,
        builder: (context) => Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(context.tr("添加附件")),
                subtitle: Text(context.tr("最多 5 个；单个 20 MB，总计 40 MB。发送时上传。")),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: Text(context.tr("图片")),
                onTap: () => Navigator.pop(context, true),
              ),
              ListTile(
                leading: const Icon(Icons.attach_file_rounded),
                title: Text(context.tr("文件")),
                onTap: () => Navigator.pop(context, false),
              ),
            ],
          ),
        ),
      );
      if (images == null || !_valid(operation)) return;
      final selected = await _media.pick(images: images);
      if (!_valid(operation)) return;
      final combined = [..._attachments, ...selected];
      if (combined.length + _remoteAttachments.length >
              LocalAttachment.maxCount ||
          combined.any(
            (f) => f.size <= 0 || f.size > LocalAttachment.maxBytes,
          ) ||
          combined.fold<int>(0, (n, f) => n + f.size) +
                  _remoteAttachments.fold<int>(0, (n, f) => n + f.size) >
              LocalAttachment.maxTotalBytes) {
        throw StateError(attachmentLimitError);
      }
      setState(() => _attachments.addAll(selected));
    } catch (e) {
      if (_valid(operation)) _error(e);
    } finally {
      if (_valid(operation)) setState(() => _phase = '');
    }
  }

  Future<void> _voice() async {
    final operation = ++_operation;
    final recordingLabel = context.tr("录音中");
    setState(() => _phase = context.tr("准备录音"));
    try {
      await c.refreshCapabilities(includeAgents: false);
      if (!_valid(operation)) return;
      if (c.sttProvider == null) throw StateError(c.voiceHint);
      await _media.startRecording();
      if (!_valid(operation)) return;
      setState(() {
        _phase = context.tr("录音中");
        _seconds = 0;
        _level = 0;
        _lastAudibleSecond = 0;
        _inlineError = null;
      });
      if (_media is AudioLevelSource) {
        _levels = (_media as AudioLevelSource).audioLevels.listen(
          (level) {
            if (!_valid(operation) || _phase != recordingLabel) return;
            setState(() {
              _level = level;
              if (level > .2) _lastAudibleSecond = _seconds;
            });
          },
          onError: (Object _) {
            /* Recording remains usable without a meter. */
          },
        );
      }
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!_valid(operation)) return;
        setState(() => _seconds++);
        if (_seconds >= 60) unawaited(_finishVoice());
      });
    } catch (e) {
      if (_valid(operation)) {
        await _media.cancelRecording().catchError((Object _) {});
        if (_valid(operation)) {
          setState(() => _phase = '');
          _error(e);
        }
      }
    }
  }

  Future<void> _finishVoice() async {
    if (_phase != context.tr("录音中")) return;
    final operation = _operation, client = c.api, provider = c.sttProvider;
    _timer?.cancel();
    _cancel = Completer<void>();
    _levels?.cancel();
    _levels = null;
    final transcriptionLengthError = context.tr("识别后文字超出输入上限，请缩短草稿");
    setState(() => _phase = context.tr("识别中"));
    try {
      final path = await _media.stopRecording();
      if (!_valid(operation) ||
          path == null ||
          client == null ||
          provider == null) {
        return;
      }
      final result = await client.transcribe(
        path,
        provider,
        cancel: _cancel?.future,
      );
      if (!_valid(operation)) return;
      final previous = widget.input.text;
      final value = previous.isEmpty ? result : '$previous\n$result';
      if (value.length > 64000) {
        throw StateError(transcriptionLengthError);
      }
      widget.input.value = TextEditingValue(
        text: value,
        selection: TextSelection.collapsed(offset: value.length),
      );
    } catch (e) {
      if (_valid(operation)) _error(e);
    } finally {
      // A canceled old operation must not delete a newer recording.
      if (_valid(operation)) {
        await _media.cancelRecording().catchError((Object _) {});
        if (_valid(operation)) setState(() => _phase = '');
      }
    }
  }

  Future<void> _send() async {
    if (_busy || !c.canSubmit(widget.input.text)) return;
    if (c.working &&
        c.isBridgeCommand(widget.input.text) &&
        (_attachments.isNotEmpty || _remoteAttachments.isNotEmpty)) {
      _error(context.tr("运行中发送命令不能携带附件，请先移除附件"));
      return;
    }
    final operation = ++_operation, client = c.api;
    final input = widget.input.text;
    _inlineError = null;
    _uploadProgress = 0;
    if (input.length > 64000) {
      _error(context.tr("消息不能超过 64000 字符"));
      return;
    }
    _cancel = Completer<void>();
    final sendUnavailableError = context.tr("当前无法发送，草稿已保留。请恢复连接后重试。");
    setState(() => _phase = context.tr("上传中"));
    try {
      final blocks = _attachments.isEmpty
          ? <Map<String, dynamic>>[]
          : await client!.uploadAttachments(
              List.of(_attachments),
              cancel: _cancel!.future,
              onProgress: (value) {
                if (_valid(operation)) setState(() => _uploadProgress = value);
              },
            );
      if (!_valid(operation)) return;
      _remoteAttachments.addAll(MessageAttachment.parse(blocks));
      _attachments.clear();
      final sent = c.send(
        input,
        attachments: _remoteAttachments.map((f) => f.toBlock()).toList(),
      );
      if (sent) {
        widget.input.clear();
        _attachments.clear();
        _remoteAttachments.clear();
        HapticFeedback.lightImpact();
      } else {
        _error(sendUnavailableError);
      }
    } catch (e) {
      if (_valid(operation)) _error(e);
    } finally {
      if (_valid(operation)) setState(() => _phase = '');
    }
  }

  @override
  Widget build(BuildContext context) {
    final owner = c.sessionId;
    final folded =
        widget.collapsed &&
        !_busy &&
        !_focus.hasFocus &&
        _attachments.isEmpty &&
        _remoteAttachments.isEmpty &&
        c.timeline.interaction == null;
    final editor = AnimatedSize(
      duration: MediaQuery.of(context).disableAnimations
          ? Duration.zero
          : const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      alignment: Alignment.bottomCenter,
      // Keep the editor subtree mounted, but consume zero height when folded.
      child: Visibility(
        visible: !folded,
        maintainState: true,
        child: _expanded(context),
      ),
    );
    final handle = folded
        ? ValueListenableBuilder(
            key: const Key('collapsed-composer'),
            valueListenable: widget.input,
            builder: (context, value, _) => ReadingHandle(
              progress: widget.readingProgress,
              onExpand: widget.onExpand,
              hasDraft: value.text.isNotEmpty,
            ),
          )
        : null;
    final stop = folded && c.working
        ? IconButton.filledTonal(
            key: const Key('collapsed-stop-button'),
            tooltip: context.tr("停止生成"),
            onPressed: c.connected && c.current?.canContinue != false
                ? () => c.stop(expectedSession: owner)
                : null,
            icon: const Icon(Icons.stop_rounded, size: 21),
          )
        : null;
    if (widget.layoutBuilder != null) {
      return widget.layoutBuilder!(editor, handle, stop);
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        editor,
        if (handle != null)
          Row(
            children: [
              Expanded(child: Center(child: handle)),
              ?stop,
            ],
          ),
      ],
    );
  }

  Widget _expanded(BuildContext context) {
    final owner = c.sessionId;
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: SlashCommandPicker(
        controller: c,
        input: widget.input,
        focus: _focus,
        enabled: !_busy,
        child: DecoratedBox(
          key: const Key('composer-surface'),
          decoration: BoxDecoration(
            color: colors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: colors.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_inlineError != null)
                  Row(
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text(
                            context.l10n.format("{0} · 草稿已保留", {
                              '0': _inlineError,
                            }),
                            style: TextStyle(fontSize: 12, color: colors.error),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: context.tr("关闭输入提示"),
                        onPressed: () => setState(() => _inlineError = null),
                        icon: const Icon(Icons.close, size: 16),
                      ),
                    ],
                  ),
                if (_remoteAttachments.isNotEmpty)
                  Wrap(
                    children: [
                      for (final file in _remoteAttachments)
                        InputChip(
                          label: Text(file.name),
                          onDeleted: _busy
                              ? null
                              : () => setState(
                                  () => _remoteAttachments.remove(file),
                                ),
                        ),
                    ],
                  ),
                if (_attachments.isNotEmpty)
                  SizedBox(
                    height: 70,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _attachments.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 6),
                      itemBuilder: (context, index) {
                        final file = _attachments[index];
                        return InputChip(
                          avatar: file.isImage
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: Image.file(
                                    File(file.path),
                                    width: 32,
                                    height: 32,
                                    cacheWidth: 128,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) =>
                                        const Icon(Icons.image_outlined),
                                  ),
                                )
                              : const Icon(
                                  Icons.insert_drive_file_outlined,
                                  size: 20,
                                ),
                          label: SizedBox(
                            width: 112,
                            child: Text(
                              file.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          onPressed: file.isImage
                              ? () => showDialog<void>(
                                  context: context,
                                  builder: (context) => Dialog(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Flexible(
                                          child: InteractiveViewer(
                                            child: Image.file(
                                              File(file.path),
                                              cacheWidth: 1600,
                                              errorBuilder: (_, _, _) =>
                                                  Padding(
                                                    padding: EdgeInsets.all(24),
                                                    child: Text(
                                                      context.tr("此图片格式暂不支持预览"),
                                                    ),
                                                  ),
                                            ),
                                          ),
                                        ),
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(context),
                                          child: Text(context.tr("关闭预览")),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                              : null,
                          onDeleted: _busy
                              ? null
                              : () => setState(
                                  () => _attachments.removeAt(index),
                                ),
                          deleteButtonTooltipMessage: context.l10n.format(
                            "移除 {0}",
                            {'0': file.name},
                          ),
                        );
                      },
                    ),
                  ),
                if (_phase == context.tr("录音中") && _media is AudioLevelSource)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Column(
                      children: [
                        LinearProgressIndicator(
                          key: const Key('voice-level'),
                          value: _level,
                          minHeight: 3,
                          borderRadius: BorderRadius.circular(3),
                        ),
                        if (_seconds - _lastAudibleSecond >= 5)
                          Text(
                            context.tr("暂未检测到声音，请靠近麦克风或检查权限"),
                            style: TextStyle(fontSize: 11),
                          ),
                      ],
                    ),
                  ),
                if (_phase == context.tr("上传中") && _attachments.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Column(
                      children: [
                        LinearProgressIndicator(
                          key: const Key('upload-progress'),
                          value: _uploadProgress,
                          minHeight: 2,
                        ),
                        Text(
                          _uploadProgress >= 1
                              ? context.tr("上传数据已发送 · 等待服务器保存")
                              : context.l10n.format("上传 {0}%", {
                                  '0': (100 * _uploadProgress).floor(),
                                }),
                          style: const TextStyle(fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                if (_busy)
                  Row(
                    children: [
                      if (_phase != context.tr("录音中") &&
                          _phase != context.tr("选择附件"))
                        const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 1.5),
                        ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _phase == context.tr("录音中")
                              ? context.l10n.format("录音 {0} / 60 秒 · 完成后可编辑", {
                                  '0': _seconds,
                                })
                              : _phase,
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                      if (_phase == context.tr("录音中"))
                        TextButton(
                          onPressed: _finishVoice,
                          child: Text(context.tr("完成")),
                        ),
                      IconButton(
                        tooltip: context.tr("取消当前操作"),
                        onPressed: _abort,
                        icon: const Icon(Icons.close_rounded, size: 18),
                      ),
                    ],
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: TextField(
                    key: const Key('message-input'),
                    focusNode: _focus,
                    controller: widget.input,
                    readOnly: _busy,
                    minLines: 1,
                    maxLines: 5,
                    maxLength: 64000,
                    textCapitalization: TextCapitalization.sentences,
                    keyboardType: TextInputType.multiline,
                    decoration: InputDecoration(
                      hintText: context.tr("发消息，输入 / 使用命令"),
                      counterText: '',
                      filled: false,
                      contentPadding: EdgeInsets.symmetric(vertical: 8),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                    ),
                    style: const TextStyle(fontSize: 16, height: 1.4),
                    onTapOutside: (_) =>
                        FocusManager.instance.primaryFocus?.unfocus(),
                  ),
                ),
                Row(
                  key: const Key('composer-toolbar'),
                  children: [
                    SizedBox(
                      width: 44,
                      child: IconButton(
                        key: const Key('attachment-button'),
                        tooltip: context.tr("添加文件或图片"),
                        onPressed: !_busy && (c.canSend || c.canQueue)
                            ? _pick
                            : null,
                        icon: const Icon(Icons.add_rounded, size: 22),
                      ),
                    ),
                    Expanded(
                      child: Tooltip(
                        message: context.l10n.format("选择模型 · {0}", {
                          '0': c.selectedModel?.label ?? context.tr("服务端默认模型"),
                        }),
                        child: TextButton(
                          key: const Key('model-button'),
                          onPressed: !_busy && c.canConfigure ? _models : null,
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            minimumSize: const Size(0, 44),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  c.selectedModel?.label ?? context.tr("默认模型"),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                              const Icon(Icons.expand_more_rounded, size: 16),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Tooltip(
                      message: context.l10n.format("思考深度 · {0}", {
                        '0': context.tr(
                          reasoningEffortLabels[c.reasoningEffort] ?? "默认",
                        ),
                      }),
                      child: SizedBox(
                        width: 64,
                        child: TextButton(
                          key: const Key('reasoning-button'),
                          onPressed: !_busy && c.canConfigure
                              ? _reasoning
                              : null,
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            minimumSize: const Size(0, 44),
                          ),
                          child: Text(
                            context.l10n.format("思考 · {0}", {
                              '0': context.tr(
                                reasoningEffortLabels[c.reasoningEffort] ??
                                    "默认",
                              ),
                            }),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 44,
                      child: IconButton(
                        key: const Key('voice-button'),
                        tooltip: c.sttProvider == null
                            ? context.tr("配置语音输入")
                            : context.tr("语音输入"),
                        onPressed: !_busy && (c.canSend || c.canQueue)
                            ? _voice
                            : null,
                        icon: Icon(
                          Icons.mic_none_rounded,
                          size: 22,
                          color: c.sttProvider == null
                              ? colors.onSurfaceVariant
                              : colors.primary,
                        ),
                      ),
                    ),
                    ValueListenableBuilder(
                      valueListenable: widget.input,
                      builder: (context, value, _) =>
                          c.working && value.text.trim().isNotEmpty
                          ? SizedBox(
                              width: 40,
                              child: IconButton(
                                tooltip: context.tr("停止生成"),
                                onPressed: c.connected
                                    ? () => c.stop(expectedSession: owner)
                                    : null,
                                icon: const Icon(Icons.stop_rounded),
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                    ValueListenableBuilder(
                      valueListenable: widget.input,
                      builder: (context, value, _) => IconButton.filled(
                        key: Key(
                          c.working &&
                                  widget.input.text.trim().isEmpty &&
                                  _attachments.isEmpty &&
                                  _remoteAttachments.isEmpty
                              ? 'stop-button'
                              : 'send-button',
                        ),
                        tooltip:
                            c.working &&
                                value.text.trim().isEmpty &&
                                _attachments.isEmpty &&
                                _remoteAttachments.isEmpty
                            ? context.tr("停止生成")
                            : c.working && !c.isBridgeCommand(value.text)
                            ? context.tr("加入队列")
                            : context.tr("发送消息"),
                        onPressed:
                            c.working &&
                                value.text.trim().isEmpty &&
                                _attachments.isEmpty &&
                                _remoteAttachments.isEmpty
                            ? (c.connected && c.current?.canContinue != false
                                  ? () => c.stop(expectedSession: owner)
                                  : null)
                            : (!_busy &&
                                      c.canSubmit(value.text) &&
                                      (value.text.trim().isNotEmpty ||
                                          _attachments.isNotEmpty ||
                                          _remoteAttachments.isNotEmpty)
                                  ? _send
                                  : null),
                        icon: Icon(
                          c.working &&
                                  value.text.trim().isEmpty &&
                                  _attachments.isEmpty &&
                                  _remoteAttachments.isEmpty
                              ? Icons.stop_rounded
                              : Icons.arrow_upward_rounded,
                          size: 23,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
