import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../data/mobile_media.dart';
import '../../state/app_controller.dart';

/// Native pickers/recorder; no upload until Send (or Finish for speech).
class ChatComposer extends StatefulWidget {
  const ChatComposer({
    super.key,
    required this.controller,
    required this.input,
    this.media,
  });
  final AppController controller;
  final TextEditingController input;
  final MediaAccess? media;
  @override
  State<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends State<ChatComposer>
    with WidgetsBindingObserver {
  late final MediaAccess _media = widget.media ?? NativeMediaAccess();
  final _attachments = <LocalAttachment>[];
  String _phase = '';
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
    _revision = c.chatRevision;
    c.addListener(_contextChanged);
    WidgetsBinding.instance.addObserver(this);
  }

  void _contextChanged() {
    if (_revision == c.chatRevision) return;
    _revision = c.chatRevision;
    if (!_sending) {
      _attachments.clear();
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
    if (mounted) c.reportError(error);
  }

  @override
  void dispose() {
    c.removeListener(_contextChanged);
    WidgetsBinding.instance.removeObserver(this);
    _operation++;
    _timer?.cancel();
    if (_cancel?.isCompleted == false) _cancel!.complete();
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
      if (combined.length > LocalAttachment.maxCount ||
          combined.any(
            (f) => f.size <= 0 || f.size > LocalAttachment.maxBytes,
          ) ||
          combined.fold<int>(0, (n, f) => n + f.size) >
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
      });
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
    if (_phase != '录音中' && _phase != '选择附件') return;
    final operation = _operation, client = c.api, provider = c.sttProvider;
    _timer?.cancel();
    _cancel = Completer<void>();
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
            );
      if (!_valid(operation)) return;
      _sending = true;
      final sent = c.send(input, attachments: blocks);
      _sending = false;
      if (sent) {
        widget.input.clear();
        _attachments.clear();
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
                                        _attachments.isNotEmpty)
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
