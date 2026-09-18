import '../../l10n.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Distance from the newest edge within the currently loaded history, not the
/// percentage of all server-side messages (older pages may not be loaded yet).
double historyReadProgress(ScrollMetrics metrics) {
  final extent = metrics.maxScrollExtent - metrics.minScrollExtent;
  if (!extent.isFinite || extent <= 0 || !metrics.pixels.isFinite) return 0;
  return ((metrics.pixels - metrics.minScrollExtent) / extent).clamp(0.0, 1.0);
}

/// A quiet, floating twin-line affordance. Only the glyph is small; its
/// transparent 128 x 48 hit target remains accessible and keyboard-operable.
class ReadingHandle extends StatefulWidget {
  const ReadingHandle({
    super.key,
    required this.progress,
    required this.onExpand,
    this.hasDraft = false,
  });
  final ValueListenable<double> progress;
  final VoidCallback? onExpand;
  final bool hasDraft;
  @override
  State<ReadingHandle> createState() => _ReadingHandleState();
}

class _ReadingHandleState extends State<ReadingHandle> {
  Timer? _idle;
  bool _active = true;
  @override
  void initState() {
    super.initState();
    widget.progress.addListener(_wake);
    _schedule();
  }

  @override
  void didUpdateWidget(covariant ReadingHandle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.progress != widget.progress) {
      oldWidget.progress.removeListener(_wake);
      widget.progress.addListener(_wake);
    }
  }

  void _schedule() {
    _idle?.cancel();
    _idle = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _active = false);
    });
  }

  void _wake() {
    if (!_active && mounted) setState(() => _active = true);
    _schedule();
  }

  @override
  void dispose() {
    widget.progress.removeListener(_wake);
    _idle?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ValueListenableBuilder<double>(
      valueListenable: widget.progress,
      builder: (context, raw, _) {
        final value = raw.isFinite ? raw.clamp(0.0, 1.0) : 0.0;
        final label = widget.hasDraft
            ? context.tr("继续编辑草稿")
            : context.tr("展开输入框");
        final description = context.l10n.format("已加载历史回看 {0}%", {
          '0': (value * 100).round(),
        });
        return Semantics(
          button: true,
          label: label,
          value: description,
          child: Tooltip(
            message: '$label · $description',
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                key: const Key('expand-composer'),
                borderRadius: BorderRadius.circular(24),
                onTap: widget.onExpand,
                child: SizedBox(
                  width: 128,
                  height: 48,
                  child: Center(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        boxShadow: [
                          BoxShadow(
                            color: colors.surface.withValues(alpha: .94),
                            blurRadius: 12,
                            spreadRadius: 7,
                          ),
                        ],
                      ),
                      child: AnimatedOpacity(
                        duration: MediaQuery.of(context).disableAnimations
                            ? Duration.zero
                            : const Duration(milliseconds: 280),
                        opacity: _active ? 1 : .68,
                        child: TweenAnimationBuilder<double>(
                          tween: Tween<double>(begin: value, end: value),
                          duration: MediaQuery.of(context).disableAnimations
                              ? Duration.zero
                              : const Duration(milliseconds: 180),
                          curve: Curves.easeOutCubic,
                          builder: (context, interpolated, _) => CustomPaint(
                            key: const Key('reading-progress-lines'),
                            size: const Size(96, 10),
                            painter: ReadingHandlePainter(
                              progress: interpolated,
                              track: colors.onSurfaceVariant.withValues(
                                alpha: dark ? .4 : .24,
                              ),
                              fill: colors.primary.withValues(
                                alpha: dark ? .9 : .82,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class ReadingHandlePainter extends CustomPainter {
  const ReadingHandlePainter({
    required this.progress,
    required this.track,
    required this.fill,
  });
  final double progress;
  final Color track, fill;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2.5;
    // Equal insets keep rounded ends inside the track's 96px visual bounds.
    const inset = 1.25;
    final width = size.width - inset * 2;
    canvas.drawLine(
      Offset(inset, 2),
      Offset(size.width - inset, 2),
      paint..color = track,
    );
    final filled = width * progress;
    if (filled > 0) {
      final start = (size.width - filled) / 2;
      canvas.drawLine(
        Offset(start, 8),
        Offset(start + filled, 8),
        paint..color = fill,
      );
    }
  }

  @override
  bool shouldRepaint(covariant ReadingHandlePainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.track != track ||
      oldDelegate.fill != fill;
}
