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
class ReadingHandle extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ValueListenableBuilder<double>(
      valueListenable: progress,
      builder: (context, raw, _) {
        final value = raw.isFinite ? raw.clamp(0.0, 1.0) : 0.0;
        final label = hasDraft ? '继续编辑草稿' : '展开输入框';
        final description = '已加载历史回看 ${(value * 100).round()}%';
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
                onTap: onExpand,
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
                      child: CustomPaint(
                        key: const Key('reading-progress-lines'),
                        size: const Size(96, 10),
                        painter: ReadingHandlePainter(
                          progress: value,
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
