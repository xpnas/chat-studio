import '../l10n.dart';
import 'package:flutter/material.dart';

const chatstudioGreen = Color(0xFF285B4B);
ThemeData chatstudioTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: chatstudioGreen,
    brightness: brightness,
    surface: dark ? const Color(0xFF141B18) : const Color(0xFFFAFAF6),
  );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme);
  final textTheme = base.textTheme.copyWith(
    titleLarge: base.textTheme.titleLarge?.copyWith(
      fontSize: 18,
      fontWeight: FontWeight.w600,
      letterSpacing: -.1,
    ),
    titleMedium: base.textTheme.titleMedium?.copyWith(
      fontSize: 15,
      fontWeight: FontWeight.w600,
    ),
    bodyLarge: base.textTheme.bodyLarge?.copyWith(fontSize: 15, height: 1.45),
    bodyMedium: base.textTheme.bodyMedium?.copyWith(fontSize: 13, height: 1.4),
    bodySmall: base.textTheme.bodySmall?.copyWith(fontSize: 12, height: 1.35),
    labelLarge: base.textTheme.labelLarge?.copyWith(fontSize: 13),
  );
  return base.copyWith(
    textTheme: textTheme,
    scaffoldBackgroundColor: scheme.surface,
    cardTheme: CardThemeData(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    dialogTheme: DialogThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
    ),
    listTileTheme: ListTileThemeData(
      minVerticalPadding: 7,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      titleTextStyle: textTheme.bodyLarge?.copyWith(
        fontWeight: FontWeight.w500,
      ),
      subtitleTextStyle: textTheme.bodySmall,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      centerTitle: true,
      elevation: 0,
      titleTextStyle: base.textTheme.titleLarge!.copyWith(
        color: scheme.onSurface,
        fontSize: 17,
        fontWeight: FontWeight.w600,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? const Color(0xFF202A25) : Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant.withValues(alpha: .6),
      thickness: .7,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
  );
}

class ChatStudioMark extends StatelessWidget {
  const ChatStudioMark({super.key, this.size = 56, this.label = 'Chat Studio'});
  final String label;
  final double size;
  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    image: true,
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF159C90), Color(0xFF125D70)],
        ),
        borderRadius: BorderRadius.circular(size * .28),
      ),
      child: CustomPaint(painter: _MarkPainter(const Color(0xFFF5FFF9))),
    ),
  );
}

class _MarkPainter extends CustomPainter {
  _MarkPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width, size.height);
    canvas.translate(.5, .5);
    final path = Path()
      ..moveTo(0, -.19)
      ..lineTo(0, -.31)
      ..cubicTo(0, -.40, .14, -.41, .20, -.31)
      ..lineTo(.30, -.14)
      ..cubicTo(.35, -.05, .29, .025, .21, .025)
      ..lineTo(.125, .025);
    for (var i = 0; i < 6; i++) {
      canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0xFF127C78)
          ..strokeWidth = .075
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..style = PaintingStyle.stroke,
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..strokeWidth = .038
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..style = PaintingStyle.stroke,
      );
      canvas.rotate(3.141592653589793 / 3);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _MarkPainter oldDelegate) =>
      color != oldDelegate.color;
}

class ErrorNotice extends StatelessWidget {
  const ErrorNotice({
    super.key,
    required this.message,
    required this.onDismiss,
  });
  final String message;
  final VoidCallback onDismiss;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 6, 16, 6),
        padding: const EdgeInsets.only(left: 14, top: 6, bottom: 6),
        decoration: BoxDecoration(
          color: colors.errorContainer,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(
              Icons.info_outline_rounded,
              color: colors.onErrorContainer,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: colors.onErrorContainer, fontSize: 13),
              ),
            ),
            IconButton(
              tooltip: context.tr("关闭提示"),
              onPressed: onDismiss,
              icon: const Icon(Icons.close_rounded, size: 18),
            ),
          ],
        ),
      ),
    );
  }
}
