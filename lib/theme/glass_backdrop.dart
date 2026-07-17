import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import 'anima_theme.dart';

/// Vibrant dark glass backdrop — black depth with living gold light.
class GlassBackdrop extends StatelessWidget {
  const GlassBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF050508),
                Color(0xFF0A0A12),
                Color(0xFF08060A),
                Color(0xFF030306),
              ],
              stops: [0.0, 0.35, 0.7, 1.0],
            ),
          ),
        ),
        const CustomPaint(painter: _GoldGlowPainter(), child: SizedBox.expand()),
        const CustomPaint(painter: _GlassSheenPainter(), child: SizedBox.expand()),
        child,
      ],
    );
  }
}

class _GoldGlowPainter extends CustomPainter {
  const _GoldGlowPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final soft = Paint()
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 80)
      ..color = AnimaTheme.gold.withValues(alpha: 0.16);
    final hotter = Paint()
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 50)
      ..color = AnimaTheme.goldDeep.withValues(alpha: 0.22);
    final cool = Paint()
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 90)
      ..color = const Color(0xFF3A2A80).withValues(alpha: 0.12);

    canvas.drawCircle(
      Offset(size.width * 0.15, size.height * 0.08),
      size.shortestSide * 0.45,
      soft,
    );
    canvas.drawCircle(
      Offset(size.width * 0.92, size.height * 0.22),
      size.shortestSide * 0.38,
      hotter,
    );
    canvas.drawCircle(
      Offset(size.width * 0.75, size.height * 0.85),
      size.shortestSide * 0.5,
      cool,
    );
    canvas.drawCircle(
      Offset(size.width * 0.05, size.height * 0.65),
      size.shortestSide * 0.28,
      hotter..color = AnimaTheme.gold.withValues(alpha: 0.1),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _GlassSheenPainter extends CustomPainter {
  const _GlassSheenPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = AnimaTheme.gold.withValues(alpha: 0.04);

    const step = 56.0;
    for (var x = -size.height; x < size.width + size.height; x += step) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x + size.height * 0.35, size.height),
        line,
      );
    }

    final vignette = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.transparent,
          AnimaTheme.obsidianDeep.withValues(alpha: 0.55),
        ],
        stops: const [0.45, 1.0],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, vignette);

    // Soft top highlight like glass edge light.
    final sheen = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.center,
        colors: [
          Colors.white.withValues(alpha: 0.05),
          Colors.transparent,
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height * 0.35));
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height * 0.35),
      sheen,
    );

    // Tiny sparkles for a living feel.
    final sparkle = Paint()..color = AnimaTheme.goldSoft.withValues(alpha: 0.35);
    final rng = math.Random(17);
    for (var i = 0; i < 28; i++) {
      final dx = rng.nextDouble() * size.width;
      final dy = rng.nextDouble() * size.height;
      final r = 0.6 + rng.nextDouble() * 1.4;
      canvas.drawCircle(Offset(dx, dy), r, sparkle);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Frosted glass panel helper for cards / sheets that want extra blur.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.borderRadius = 16,
    this.padding,
  });

  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(borderRadius);
    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            color: AnimaTheme.glassHigh.withValues(alpha: 0.45),
            border: Border.all(
              color: AnimaTheme.gold.withValues(alpha: 0.22),
            ),
            boxShadow: [
              BoxShadow(
                color: AnimaTheme.gold.withValues(alpha: 0.08),
                blurRadius: 24,
                spreadRadius: -4,
              ),
            ],
          ),
          child: padding == null
              ? child
              : Padding(padding: padding!, child: child),
        ),
      ),
    );
  }
}
