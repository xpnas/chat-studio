import '../../l10n.dart';
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
                useSafeArea: !widget.file.isImage,
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
                              errorBuilder: (_, _, _) => Center(
                                child: Text(context.tr("图片格式无法预览，点击查看详情")),
                              ),
                            ),
                          )
                        : snapshot.hasError
                        ? Center(
                            child: TextButton(
                              onPressed: () => setState(_load),
                              child: Text(
                                context.l10n.format("{0}\n点击重试", {
                                  '0': snapshot.error,
                                }),
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
                    tooltip: context.tr("下载文件"),
                    onPressed: () => showDialog<void>(
                      context: context,
                      useSafeArea: !widget.file.isImage,
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
        directory = await root.createTemp('chatstudio-download-');
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
        ).showSnackBar(SnackBar(content: Text(context.tr("附件已保存至你选择的位置"))));
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

  Widget _imagePreview(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    // The image canvas is edge-to-edge; only the floating controls observe
    // system insets. Do not change global SystemChrome state for a dialog.
    return Dialog.fullscreen(
      backgroundColor: colors.surface,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: GestureDetector(
              key: const Key('dismiss-image-preview'),
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.pop(context),
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
                          errorBuilder: (_, _, _) => Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(context.tr("此格式暂不支持预览，可保存原文件")),
                          ),
                        ),
                ),
              ),
            ),
          ),
          if (_loading)
            const IgnorePointer(
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          if (_error != null)
            IgnorePointer(
              child: SafeArea(
                minimum: const EdgeInsets.fromLTRB(24, 24, 24, 100),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: colors.errorContainer,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      _error!,
                      style: TextStyle(color: colors.onErrorContainer),
                    ),
                  ),
                ),
              ),
            ),
          Positioned.fill(
            child: SafeArea(
              minimum: const EdgeInsets.all(16),
              child: Align(
                alignment: Alignment.bottomRight,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(32),
                    boxShadow: [
                      BoxShadow(
                        color: colors.shadow.withValues(alpha: .12),
                        blurRadius: 20,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Material(
                    key: const Key('image-preview-actions'),
                    color: colors.surfaceContainerHigh.withValues(alpha: .96),
                    shape: StadiumBorder(
                      side: BorderSide(
                        color: colors.outlineVariant.withValues(alpha: .5),
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_error != null && _bytes == null)
                            IconButton(
                              tooltip: context.tr("重试读取图片"),
                              onPressed: _loading ? null : _load,
                              style: _previewButtonStyle(colors),
                              icon: const Icon(Icons.refresh_rounded, size: 28),
                            ),
                          IconButton(
                            key: const Key('image-preview-download'),
                            tooltip: _saving
                                ? (_exporting
                                      ? context.tr("请选择保存位置")
                                      : context.tr("取消下载"))
                                : context.tr("下载图片"),
                            style: _previewButtonStyle(colors),
                            onPressed: _loading || _exporting
                                ? null
                                : _saving
                                ? () {
                                    if (_downloadCancel?.isCompleted == false) {
                                      _downloadCancel!.complete();
                                    }
                                  }
                                : _save,
                            icon: _saving
                                ? SizedBox.square(
                                    dimension: 28,
                                    child: Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        CircularProgressIndicator(
                                          strokeWidth: 2,
                                          value: _total != null && _total! > 0
                                              ? (_received / _total!).clamp(
                                                  0,
                                                  1,
                                                )
                                              : null,
                                        ),
                                        if (!_exporting)
                                          const Icon(
                                            Icons.stop_rounded,
                                            size: 14,
                                          ),
                                      ],
                                    ),
                                  )
                                : const _PreviewGlyph(download: true),
                          ),
                          Container(
                            width: 1,
                            height: 20,
                            color: colors.outlineVariant.withValues(alpha: .6),
                          ),
                          IconButton(
                            key: const Key('image-preview-close'),
                            tooltip: context.tr("关闭预览"),
                            style: _previewButtonStyle(colors),
                            onPressed: () => Navigator.pop(context),
                            icon: const _PreviewGlyph(download: false),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  ButtonStyle _previewButtonStyle(ColorScheme colors) => IconButton.styleFrom(
    foregroundColor: colors.primary,
    minimumSize: const Size.square(52),
    fixedSize: const Size.square(52),
    padding: const EdgeInsets.all(12),
    shape: const CircleBorder(),
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
                        ? context.tr("请选择保存位置")
                        : context.l10n.format("已下载 {0} MB{1}", {
                            '0': (_received / 1024 / 1024).toStringAsFixed(1),
                            '1': _total == null
                                ? ''
                                : ' / ${(_total! / 1024 / 1024).toStringAsFixed(1)} MB',
                          }),
                  ),
                  if (!_exporting)
                    TextButton(
                      onPressed: () {
                        if (_downloadCancel?.isCompleted == false) {
                          _downloadCancel!.complete();
                        }
                      },
                      child: Text(context.tr("取消下载")),
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
                            Text(context.tr("此格式暂不支持预览，可保存原文件")),
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
                    context.l10n.format("{0}\n{1}\n文件不会自动执行，可保存后使用系统应用查看。", {
                      '0': widget.file.mimeType,
                      '1': _bytes == null
                          ? widget.file.sizeLabel
                          : context.l10n.format("{0} 字节", {
                              '0': _bytes!.length,
                            }),
                    }),
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
              child: Text(context.tr("关闭")),
            ),
            if (_error != null)
              TextButton(
                onPressed: _loading ? null : _load,
                child: Text(context.tr("重试读取")),
              ),
            FilledButton(
              onPressed: _loading || _saving ? null : _save,
              child: Text(
                _saving ? context.tr("下载保存中") : context.tr("下载 / 保存附件"),
              ),
            ),
          ],
        );
}

// Matching rounded 28px line icons, independent of platform glyph variants.
class _PreviewGlyph extends StatelessWidget {
  const _PreviewGlyph({required this.download});
  final bool download;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: const Size.square(28),
    painter: _PreviewGlyphPainter(
      download: download,
      color:
          IconTheme.of(context).color ?? Theme.of(context).colorScheme.primary,
    ),
  );
}

class _PreviewGlyphPainter extends CustomPainter {
  const _PreviewGlyphPainter({required this.download, required this.color});
  final bool download;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 28, size.height / 28);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path();
    if (download) {
      path
        ..moveTo(14, 4)
        ..lineTo(14, 17)
        ..moveTo(9, 12)
        ..lineTo(14, 17)
        ..lineTo(19, 12)
        ..moveTo(5, 18)
        ..lineTo(5, 21)
        ..quadraticBezierTo(5, 24, 8, 24)
        ..lineTo(20, 24)
        ..quadraticBezierTo(23, 24, 23, 21)
        ..lineTo(23, 18);
    } else {
      path
        ..moveTo(7, 7)
        ..lineTo(21, 21)
        ..moveTo(21, 7)
        ..lineTo(7, 21);
    }
    canvas.drawPath(path, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PreviewGlyphPainter oldDelegate) =>
      download != oldDelegate.download || color != oldDelegate.color;
}
