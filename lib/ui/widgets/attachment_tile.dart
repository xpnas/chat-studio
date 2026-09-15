import 'dart:async';
import 'dart:typed_data';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../../data/file_export.dart';
import 'audio_attachment_control.dart';
import 'package:flutter/material.dart';
import '../../data/models.dart';
import '../../data/studio_api.dart';
import '../../state/app_controller.dart';

class AttachmentTile extends StatefulWidget {
  const AttachmentTile({
    super.key,
    required this.file,
    required this.controller,
    this.saveFile,
  });
  final MessageAttachment file;
  final AppController controller;
  final Future<String?> Function(String name, Uint8List bytes, String mimeType)?
  saveFile;
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
        onTap: widget.file.isAudio
            ? () => widget.controller.playAudioAttachment(widget.file)
            : () => showDialog<void>(
                context: context,
                builder: (_) => AttachmentViewer(
                  file: widget.file,
                  controller: widget.controller,
                  saveFile: widget.saveFile,
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
              if (widget.file.isAudio)
                AudioAttachmentControl(
                  file: widget.file,
                  controller: widget.controller,
                ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(
                    widget.file.isImage
                        ? Icons.image_outlined
                        : widget.file.isAudio
                        ? Icons.audiotrack_rounded
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
                  IconButton(
                    key: ValueKey('download:${widget.file.path}'),
                    tooltip: '下载文件',
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) => AttachmentViewer(
                        file: widget.file,
                        controller: widget.controller,
                        saveFile: widget.saveFile,
                        downloadOnOpen: true,
                      ),
                    ),
                    icon: const Icon(Icons.download_rounded, size: 20),
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
    this.saveFile,
    this.downloadOnOpen = false,
  });
  final MessageAttachment file;
  final bool downloadOnOpen;
  final AppController controller;
  final Future<String?> Function(String name, Uint8List bytes, String mimeType)?
  saveFile;
  @override
  State<AttachmentViewer> createState() => _AttachmentViewerState();
}

class _AttachmentViewerState extends State<AttachmentViewer> {
  late final StudioApi? _api = widget.controller.api;
  late final String _profile = widget.controller.profile;
  final _cancel = Completer<void>();
  Uint8List? _bytes;
  Completer<void>? _downloadCancel;
  int _received = 0;
  int? _total;
  bool _exporting = false;
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
    if (widget.downloadOnOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_valid) _save();
      });
    } else if (widget.file.isImage) {
      _load();
    }
  }

  void _changed() {
    if (!_valid && mounted && !_leaving) {
      _leaving = true;
      if (!_cancel.isCompleted) _cancel.complete();
      if (_downloadCancel?.isCompleted == false) _downloadCancel!.complete();
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
    final cancel = Completer<void>();
    _downloadCancel = cancel;
    setState(() {
      _saving = true;
      _error = null;
      _received = 0;
      _total = null;
    });
    Directory? directory;
    try {
      // The byte-based callback remains only as a small-fixture test seam.
      final name = widget.file.name.replaceAll(RegExp(r'[/\\\x00-\x1f]'), '_');
      String? result;
      if (widget.saveFile != null) {
        final bytes = await _api!.attachmentBytes(
          widget.file,
          cancel: cancel.future,
        );
        if (!_valid || cancel.isCompleted) return;
        result = await widget.saveFile!(name, bytes, widget.file.mimeType);
      } else {
        final root = await getTemporaryDirectory();
        directory = await root.createTemp('ekko-download-');
        final file = await _api!.downloadAttachment(
          widget.file,
          directory,
          cancel: cancel.future,
          onProgress: (received, total) {
            if (_valid) {
              setState(() {
                _received = received;
                _total = total;
              });
            }
          },
        );
        if (!_valid || cancel.isCompleted) return;
        setState(() => _exporting = true);
        result = await FileExport.save(file, name, widget.file.mimeType);
      }
      if (mounted && _valid && result != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('附件已保存至你选择的位置')));
      }
    } catch (e) {
      if (_valid) setState(() => _error = '$e');
    } finally {
      if (directory != null && await directory.exists()) {
        await directory.delete(recursive: true);
      }
      if (_valid) {
        setState(() {
          _saving = false;
          _exporting = false;
        });
      }
      if (identical(_downloadCancel, cancel)) _downloadCancel = null;
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    if (!_cancel.isCompleted) _cancel.complete();
    if (_downloadCancel?.isCompleted == false) _downloadCancel!.complete();
    _bytes = null;
    super.dispose();
  }

  Widget _imagePreview(BuildContext context) => Dialog.fullscreen(
    backgroundColor: Theme.of(context).colorScheme.surface,
    child: SafeArea(
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: GestureDetector(
              key: const Key('dismiss-image-preview'),
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.pop(context),
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: InteractiveViewer(
                  minScale: 1,
                  maxScale: 5,
                  child: Center(
                    child: _bytes == null
                        ? const SizedBox.shrink()
                        : Image.memory(
                            _bytes!,
                            cacheWidth: 2400,
                            fit: BoxFit.contain,
                            errorBuilder: (_, _, _) =>
                                const Text('此格式暂不支持预览，可保存原文件'),
                          ),
                  ),
                ),
              ),
            ),
          ),
          if (_loading)
            const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          if (_error != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ),
          Positioned(
            right: 8,
            bottom: 6,
            child: Material(
              color: Theme.of(
                context,
              ).colorScheme.surface.withValues(alpha: .9),
              borderRadius: BorderRadius.circular(24),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_saving)
                      SizedBox(
                        width: 130,
                        child: LinearProgressIndicator(
                          value: _total != null && _total! > 0
                              ? (_received / _total!).clamp(0, 1)
                              : null,
                        ),
                      ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_error != null)
                          TextButton(
                            onPressed: _loading ? null : _load,
                            child: const Text(
                              '重试',
                              style: TextStyle(fontSize: 11),
                            ),
                          ),
                        TextButton.icon(
                          style: TextButton.styleFrom(
                            foregroundColor: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                          onPressed: _loading || _saving ? null : _save,
                          icon: const Icon(Icons.download_outlined, size: 16),
                          label: Text(
                            _saving ? '保存中' : '保存',
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                        if (_saving && !_exporting)
                          TextButton(
                            onPressed: () {
                              if (_downloadCancel?.isCompleted == false) {
                                _downloadCancel!.complete();
                              }
                            },
                            child: const Text(
                              '取消',
                              style: TextStyle(fontSize: 11),
                            ),
                          ),
                        TextButton.icon(
                          style: TextButton.styleFrom(
                            foregroundColor: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close_rounded, size: 16),
                          label: const Text(
                            '关闭',
                            style: TextStyle(fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => widget.file.isImage
      ? _imagePreview(context)
      : AlertDialog(
          title: Text(
            widget.file.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          content: SizedBox(
            width: 600,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_saving) ...[
                  LinearProgressIndicator(
                    value: _total != null && _total! > 0
                        ? (_received / _total!).clamp(0, 1)
                        : null,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _exporting
                        ? '请选择保存位置'
                        : '已下载 ${(_received / 1024 / 1024).toStringAsFixed(1)} MB${_total == null ? '' : ' / ${(_total! / 1024 / 1024).toStringAsFixed(1)} MB'}',
                  ),
                  if (!_exporting)
                    TextButton(
                      onPressed: () {
                        if (_downloadCancel?.isCompleted == false) {
                          _downloadCancel!.complete();
                        }
                      },
                      child: const Text('取消下载'),
                    ),
                ],
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
                        errorBuilder: (_, _, _) =>
                            const Text('此格式暂不支持预览，可保存原文件'),
                      ),
                    ),
                  ),
                if (widget.file.isAudio)
                  AudioAttachmentControl(
                    file: widget.file,
                    controller: widget.controller,
                  ),
                if (!widget.file.isImage)
                  Text(
                    '${widget.file.mimeType}\n${_bytes == null ? widget.file.sizeLabel : '${_bytes!.length} 字节'}\n文件不会自动执行，可保存后使用系统应用查看。',
                  ),
                if (_error != null)
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
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
              child: Text(_saving ? '下载保存中' : '下载 / 保存附件'),
            ),
          ],
        );
}
