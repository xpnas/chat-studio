import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../data/mobile_media.dart';
import '../../data/models.dart';
import '../../state/app_controller.dart';
import 'reading_handle.dart';
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
  final _attachments = <LocalAttachment>[];
  final _focus = FocusNode();
  String _phase = '';
  String? _inlineError;
  double _uploadProgress = 0;
  double _level = 0;
  int _lastAudibleSecond = 0;
  StreamSubscription<double>? _levels;
  int _retryRevision = 0;
  final _remoteAttachments = <MessageAttachment>[];
  int _operation = 0, _seconds = 0;
  late int _revision;
  Timer? _timer;
  Completer<void>? _cancel;
  bool _sending = false;
  AppController get c => widget.controller;
  bool get _busy => _phase.isNotEmpty;
  @override
  void initState() {
    super.initState();
    _focus.addListener(_focusChanged);
    _retryRevision = c.retryRevision;
    _revision = c.chatRevision;
    c.addListener(_contextChanged);
    WidgetsBinding.instance.addObserver(this);
  }

  void _focusChanged() {
    if (mounted) setState(() {});
  }

  void _contextChanged() {
    if (_retryRevision != c.retryRevision) {
      _retryRevision = c.retryRevision;
      if (_busy ||
          widget.input.text.isNotEmpty ||
          _attachments.isNotEmpty ||
          _remoteAttachments.isNotEmpty) {
        setState(() => _inlineError = '请先完成当前操作或清空现有草稿，再恢复失败消息');
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
    if (_revision == c.chatRevision) return;
    _revision = c.chatRevision;
    if (!_sending) {
      _attachments.clear();
      _remoteAttachments.clear();
      _inlineError = null;
      _abort();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Permission prompts/pickers can be inactive; cancel active recording on background.
    if (state == AppLifecycleState.paused &&
        (_phase == '录音中' || _phase == '准备录音')) {
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
    final voice = ['录音中', '识别中', '准备录音', '取消中'].contains(_phase);
    if (mounted) setState(() => _phase = voice ? '取消中' : '');
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

  Future<void> _pick() async {
    final operation = ++_operation;
    setState(() => _phase = '选择附件');
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
              const ListTile(
                title: Text('添加附件'),
                subtitle: Text('最多 5 个；单个 20 MB，总计 40 MB。发送时上传。'),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('图片'),
                onTap: () => Navigator.pop(context, true),
              ),
              ListTile(
                leading: const Icon(Icons.attach_file_rounded),
                title: const Text('文件'),
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
        throw StateError('最多 5 个非空附件，单个不超过 20 MB，总计不超过 40 MB');
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
    setState(() => _phase = '准备录音');
    try {
      await c.refreshCapabilities();
      if (!_valid(operation)) return;
      if (c.sttProvider == null) throw StateError(c.voiceHint);
      await _media.startRecording();
      if (!_valid(operation)) return;
      setState(() {
        _phase = '录音中';
        _seconds = 0;
        _level = 0;
        _lastAudibleSecond = 0;
        _inlineError = null;
      });
      if (_media is AudioLevelSource) {
        _levels = (_media as AudioLevelSource).audioLevels.listen(
          (level) {
            if (!_valid(operation) || _phase != '录音中') return;
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
    if (_phase != '录音中') return;
    final operation = _operation, client = c.api, provider = c.sttProvider;
    _timer?.cancel();
    _cancel = Completer<void>();
    _levels?.cancel();
    _levels = null;
    setState(() => _phase = '识别中');
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
      if (value.length > 64000) throw StateError('识别后文字超出输入上限，请缩短草稿');
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
    if (_busy || !c.canSend) return;
    final operation = ++_operation, client = c.api;
    final input = widget.input.text;
    _inlineError = null;
    _uploadProgress = 0;
    if (input.length > 64000) {
      _error('消息不能超过 64000 字符');
      return;
    }
    _cancel = Completer<void>();
    setState(() => _phase = '上传中');
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
      _sending = true;
      final sent = c.send(
        input,
        attachments: _remoteAttachments.map((f) => f.toBlock()).toList(),
      );
      _sending = false;
      if (sent) {
        widget.input.clear();
        _attachments.clear();
        _remoteAttachments.clear();
        HapticFeedback.lightImpact();
      } else {
        _error('当前无法发送，草稿已保留。请恢复连接后重试。');
      }
    } catch (e) {
      if (_valid(operation)) _error(e);
    } finally {
      _sending = false;
      if (_valid(operation)) setState(() => _phase = '');
    }
  }

  @override
  Widget build(BuildContext context) {
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
            tooltip: '停止生成',
            onPressed: c.connected ? c.stop : null,
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
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: DecoratedBox(
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
                          '$_inlineError · 草稿已保留',
                          style: TextStyle(fontSize: 12, color: colors.error),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: '关闭输入提示',
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
                                                const Padding(
                                                  padding: EdgeInsets.all(24),
                                                  child: Text('此图片格式暂不支持预览'),
                                                ),
                                          ),
                                        ),
                                      ),
                                      TextButton(
                                        onPressed: () => Navigator.pop(context),
                                        child: const Text('关闭预览'),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            : null,
                        onDeleted: _busy
                            ? null
                            : () =>
                                  setState(() => _attachments.removeAt(index)),
                        deleteButtonTooltipMessage: '移除 ${file.name}',
                      );
                    },
                  ),
                ),
              if (_phase == '录音中' && _media is AudioLevelSource)
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
                        const Text(
                          '暂未检测到声音，请靠近麦克风或检查权限',
                          style: TextStyle(fontSize: 11),
                        ),
                    ],
                  ),
                ),
              if (_phase == '上传中' && _attachments.isNotEmpty)
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
                            ? '上传数据已发送 · 等待服务器保存'
                            : '上传 ${(100 * _uploadProgress).floor()}%',
                        style: const TextStyle(fontSize: 11),
                      ),
                    ],
                  ),
                ),
              if (_busy)
                Row(
                  children: [
                    if (_phase != '录音中' && _phase != '选择附件')
                      const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 1.5),
                      ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _phase == '录音中'
                            ? '录音 $_seconds / 60 秒 · 完成后可编辑'
                            : _phase,
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                    if (_phase == '录音中')
                      TextButton(
                        onPressed: _finishVoice,
                        child: const Text('完成'),
                      ),
                    IconButton(
                      tooltip: '取消当前操作',
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
                  decoration: const InputDecoration(
                    hintText: '发消息给 Ekko',
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
                children: [
                  IconButton(
                    key: const Key('attachment-button'),
                    tooltip: '添加文件或图片',
                    onPressed: !_busy && c.canSend ? _pick : null,
                    icon: const Icon(Icons.add_rounded),
                  ),
                  const Spacer(),
                  IconButton(
                    key: const Key('voice-button'),
                    tooltip: c.sttProvider == null ? '配置语音输入' : '语音输入',
                    onPressed: !_busy && c.canSend ? _voice : null,
                    icon: Icon(
                      Icons.mic_none_rounded,
                      color: c.sttProvider == null
                          ? colors.onSurfaceVariant
                          : colors.primary,
                    ),
                  ),
                  ValueListenableBuilder(
                    valueListenable: widget.input,
                    builder: (context, value, _) => IconButton.filled(
                      key: Key(c.working ? 'stop-button' : 'send-button'),
                      tooltip: c.working ? '停止生成' : '发送消息',
                      onPressed: c.working
                          ? (c.connected ? c.stop : null)
                          : (!_busy &&
                                    c.canSend &&
                                    (value.text.trim().isNotEmpty ||
                                        _attachments.isNotEmpty ||
                                        _remoteAttachments.isNotEmpty)
                                ? _send
                                : null),
                      icon: Icon(
                        c.working
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
    );
  }
}
