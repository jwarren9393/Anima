import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/ui_style_settings.dart';
import 'anima_theme.dart';

/// Soft backdrop behind the whole app — style depends on [AnimaUiTheme].
class ParchmentBackdrop extends StatelessWidget {
  const ParchmentBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ui = AnimaUiTheme.of(context);
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = ui.backdropBackground ??
        (isDark ? AnimaTheme.night : AnimaTheme.parchmentDeep);

    final List<Color> gradientColors;
    switch (ui.backgroundStyle) {
      case BackgroundStyle.solid:
        gradientColors = [base, base];
      case BackgroundStyle.softGradient:
        gradientColors = isDark
            ? [
                Color.lerp(base, Colors.black, 0.15)!,
                base,
                Color.lerp(base, scheme.primary, 0.12)!,
              ]
            : [
                Color.lerp(base, Colors.white, 0.2)!,
                base,
                Color.lerp(base, scheme.primary, 0.1)!,
              ];
      case BackgroundStyle.parchment:
        gradientColors = isDark
            ? [
                const Color(0xFF1A1712),
                base,
                const Color(0xFF12100E),
              ]
            : [
                const Color(0xFFF0E4CC),
                base,
                const Color(0xFFCFBB94),
              ];
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: gradientColors,
            ),
          ),
        ),
        if (ui.showTexture)
          CustomPaint(
            painter: _ParchmentTexturePainter(
              dark: isDark,
              intensity: ui.textureIntensity,
              showVignette: ui.showVignette,
            ),
            child: const SizedBox.expand(),
          )
        else if (ui.showVignette)
          CustomPaint(
            painter: _ParchmentTexturePainter(
              dark: isDark,
              intensity: 0,
              showVignette: true,
            ),
            child: const SizedBox.expand(),
          ),
        child,
      ],
    );
  }
}

class _ParchmentTexturePainter extends CustomPainter {
  _ParchmentTexturePainter({
    required this.dark,
    required this.intensity,
    required this.showVignette,
  });

  final bool dark;
  final double intensity;
  final bool showVignette;

  @override
  void paint(Canvas canvas, Size size) {
    if (intensity > 0.01) {
      final fiber = Paint()
        ..strokeWidth = 1
        ..style = PaintingStyle.stroke;
      final rng = math.Random(42);
      final count = (28 + intensity * 30).round();
      final alpha = (dark ? 0.05 : 0.06) * intensity;
      for (var i = 0; i < count; i++) {
        final y = rng.nextDouble() * size.height;
        final x0 = rng.nextDouble() * size.width * 0.15;
        final x1 = size.width * (0.55 + rng.nextDouble() * 0.45);
        fiber.color =
            (dark ? const Color(0xFFD4C4A0) : const Color(0xFF5A4A32))
                .withValues(alpha: alpha);
        canvas.drawLine(
          Offset(x0, y),
          Offset(x1, y + (rng.nextDouble() - 0.5) * 6),
          fiber,
        );
      }
    }

    if (showVignette) {
      final vignette = Paint()
        ..shader = RadialGradient(
          center: Alignment.center,
          radius: 1.05,
          colors: [
            Colors.transparent,
            (dark ? Colors.black : const Color(0xFF3A2E1C))
                .withValues(alpha: dark ? 0.35 : 0.12),
          ],
          stops: const [0.55, 1.0],
        ).createShader(Offset.zero & size);
      canvas.drawRect(Offset.zero & size, vignette);
    }
  }

  @override
  bool shouldRepaint(covariant _ParchmentTexturePainter oldDelegate) {
    return oldDelegate.dark != dark ||
        oldDelegate.intensity != intensity ||
        oldDelegate.showVignette != showVignette;
  }
}
