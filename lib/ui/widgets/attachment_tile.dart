import 'dart:async';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../data/models.dart';
import '../../data/studio_api.dart';
import '../../state/app_controller.dart';

class AttachmentTile extends StatefulWidget {
  const AttachmentTile({
    super.key,
    required this.file,
    required this.controller,
  });
  final MessageAttachment file;
  final AppController controller;
  @override
  State<AttachmentTile> createState() => _AttachmentTileState();
}

class _AttachmentTileState extends State<AttachmentTile> {
  Future<Uint8List>? _preview;
  final _cancel = Completer<void>();
  StudioApi? _api;
  String? _profile;
  @override
  void initState() {
    super.initState();
    _api = widget.controller.api;
    _profile = widget.controller.profile;
    if (widget.file.isImage) _load();
  }

  void _load() {
    _preview = _api?.attachmentBytes(
      widget.file,
      thumbnail: true,
      cancel: _cancel.future,
    );
    // A cached/fast retry may fail before the next frame attaches FutureBuilder.
    // Mark it handled immediately; FutureBuilder still receives the error state.
    _preview?.ignore();
  }

  @override
  void dispose() {
    _cancel.complete();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    if (_api != widget.controller.api ||
        _profile != widget.controller.profile) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => showDialog<void>(
          context: context,
          builder: (_) => AttachmentViewer(
            file: widget.file,
            controller: widget.controller,
          ),
        ),
        child: Container(
          width: 250,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: colors.surfaceContainer.withValues(alpha: .65),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.file.isImage)
                FutureBuilder<Uint8List>(
                  future: _preview,
                  builder: (context, snapshot) => SizedBox(
                    height: 120,
                    width: double.infinity,
                    child: snapshot.hasData
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.memory(
                              snapshot.data!,
                              cacheWidth: 480,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) =>
                                  const Center(child: Text('图片格式无法预览，点击查看详情')),
                            ),
                          )
                        : snapshot.hasError
                        ? Center(
                            child: TextButton(
                              onPressed: () => setState(_load),
                              child: Text(
                                '${snapshot.error}\n点击重试',
                                textAlign: TextAlign.center,
                              ),
                            ),
                          )
                        : const Center(
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                              ),
                            ),
                          ),
                  ),
                ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(
                    widget.file.isImage
                        ? Icons.image_outlined
                        : Icons.insert_drive_file_outlined,
                    size: 18,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      widget.file.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
              Text(
                '${widget.file.name.split('.').last.toUpperCase()} · ${widget.file.sizeLabel}',
                style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AttachmentViewer extends StatefulWidget {
  const AttachmentViewer({
    super.key,
    required this.file,
    required this.controller,
  });
  final MessageAttachment file;
  final AppController controller;
  @override
  State<AttachmentViewer> createState() => _AttachmentViewerState();
}

class _AttachmentViewerState extends State<AttachmentViewer> {
  late final StudioApi? _api = widget.controller.api;
  late final String _profile = widget.controller.profile;
  final _cancel = Completer<void>();
  Uint8List? _bytes;
  String? _error;
  bool _loading = false, _saving = false, _leaving = false;
  bool get _valid =>
      mounted &&
      _api == widget.controller.api &&
      _profile == widget.controller.profile;
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    if (widget.file.isImage) _load();
  }

  void _changed() {
    if (!_valid && mounted && !_leaving) {
      _leaving = true;
      if (!_cancel.isCompleted) _cancel.complete();
      setState(() => _bytes = null);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
    }
  }

  Future<void> _load() async {
    if (_loading || !_valid) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _api!.attachmentBytes(
        widget.file,
        cancel: _cancel.future,
      );
      if (_valid) setState(() => _bytes = data);
    } catch (e) {
      if (_valid) setState(() => _error = '$e');
    } finally {
      if (_valid) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_saving || !_valid) return;
    setState(() => _saving = true);
    try {
      if (_bytes == null) await _load();
      if (!_valid || _bytes == null) return;
      final name = widget.file.name.replaceAll(RegExp(r'[/\\\x00-\x1f]'), '_');
      final result = await FilePicker.saveFile(
        fileName: name,
        bytes: _bytes!,
        mimeType: widget.file.mimeType,
      );
      if (mounted && _valid && result != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('附件已保存至你选择的位置')));
      }
    } catch (e) {
      if (_valid) setState(() => _error = '保存失败，请重试');
    } finally {
      if (_valid) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    if (!_cancel.isCompleted) _cancel.complete();
    _bytes = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.file.name, maxLines: 2, overflow: TextOverflow.ellipsis),
    content: SizedBox(
      width: 600,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(20),
              child: CircularProgressIndicator(),
            ),
          if (_bytes != null && widget.file.isImage)
            Flexible(
              child: InteractiveViewer(
                child: Image.memory(
                  _bytes!,
                  cacheWidth: 1800,
                  errorBuilder: (_, _, _) => const Text('此格式暂不支持预览，可保存原文件'),
                ),
              ),
            ),
          if (!widget.file.isImage)
            Text(
              '${widget.file.mimeType}\n${_bytes == null ? widget.file.sizeLabel : '${_bytes!.length} 字节'}\n文件不会自动执行，可保存后使用系统应用查看。',
            ),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('关闭'),
      ),
      if (_error != null)
        TextButton(
          onPressed: _loading ? null : _load,
          child: const Text('重试读取'),
        ),
      FilledButton(
        onPressed: _loading || _saving ? null : _save,
        child: Text(_saving ? '保存中' : '保存附件'),
      ),
    ],
  );
}
