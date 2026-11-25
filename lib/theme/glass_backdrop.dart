import 'dart:ui';

import 'package:flutter/material.dart';

import '../models/theme_palette.dart';
import '../models/ui_style_settings.dart';

/// App-wide backdrop driven by Theme Studio settings.
///
/// Glass presets get a soft accent glow. Solid presets stay clean and opaque.
/// The old sparkle / diagonal grid texture is intentionally gone.
class GlassBackdrop extends StatelessWidget {
  const GlassBackdrop({super.key, required this.child, this.settings});

  final Widget child;
  final UiStyleSettings? settings;

  @override
  Widget build(BuildContext context) {
    final ui = AnimaUiTheme.of(context);
    final style =
        settings ??
        UiStyleSettings(
          visualStyle: ui.visualStyle,
          backgroundMode: ui.backgroundMode,
          palette: ThemePalette(
            background: ui.background,
            backgroundAlt: ui.backgroundAlt,
            surface: Theme.of(context).colorScheme.surface,
            surfaceHigh: Theme.of(context).colorScheme.surfaceContainerHigh,
            accent: Theme.of(context).colorScheme.primary,
            accentDeep: ui.accentDeep,
            header: Theme.of(context).colorScheme.surface,
            text: Theme.of(context).colorScheme.onSurface,
            textMuted: Theme.of(context).colorScheme.onSurfaceVariant,
            userBubble: ui.userBubbleColor,
            aiBubble: ui.aiBubbleColor,
            brightness: Theme.of(context).brightness,
          ),
          glassOpacity: ui.glassOpacity,
          glassBlur: ui.glassBlur,
          cornerRadius: ui.cornerRadius,
        );

    final palette = style.palette;
    final showGlow =
        style.backgroundMode == BackgroundMode.softGlow ||
        (style.isGlass && style.backgroundMode != BackgroundMode.solid);

    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: style.backgroundMode == BackgroundMode.solid
                ? palette.background
                : null,
            gradient: style.backgroundMode == BackgroundMode.solid
                ? null
                : LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      palette.background,
                      palette.backgroundAlt,
                      Color.lerp(palette.background, palette.surface, 0.35)!,
                      palette.background,
                    ],
                    stops: const [0.0, 0.35, 0.7, 1.0],
                  ),
          ),
        ),
        if (showGlow)
          CustomPaint(
            painter: _SoftGlowPainter(
              accent: palette.accent,
              accentDeep: palette.accentDeep,
              depth: palette.background,
            ),
            child: const SizedBox.expand(),
          ),
        if (style.backgroundMode != BackgroundMode.solid)
          CustomPaint(
            painter: _VignettePainter(depth: palette.background),
            child: const SizedBox.expand(),
          ),
        child,
      ],
    );
  }
}

class _SoftGlowPainter extends CustomPainter {
  const _SoftGlowPainter({
    required this.accent,
    required this.accentDeep,
    required this.depth,
  });

  final Color accent;
  final Color accentDeep;
  final Color depth;

  @override
  void paint(Canvas canvas, Size size) {
    final soft = Paint()
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 90)
      ..color = accent.withValues(alpha: 0.14);
    final hotter = Paint()
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 60)
      ..color = accentDeep.withValues(alpha: 0.16);

    canvas.drawCircle(
      Offset(size.width * 0.18, size.height * 0.1),
      size.shortestSide * 0.42,
      soft,
    );
    canvas.drawCircle(
      Offset(size.width * 0.9, size.height * 0.28),
      size.shortestSide * 0.34,
      hotter,
    );
    canvas.drawCircle(
      Offset(size.width * 0.7, size.height * 0.88),
      size.shortestSide * 0.4,
      soft..color = accent.withValues(alpha: 0.08),
    );
  }

  @override
  bool shouldRepaint(covariant _SoftGlowPainter oldDelegate) {
    return oldDelegate.accent != accent ||
        oldDelegate.accentDeep != accentDeep ||
        oldDelegate.depth != depth;
  }
}

class _VignettePainter extends CustomPainter {
  const _VignettePainter({required this.depth});

  final Color depth;

  @override
  void paint(Canvas canvas, Size size) {
    final vignette = Paint()
      ..shader = RadialGradient(
        colors: [Colors.transparent, depth.withValues(alpha: 0.45)],
        stops: const [0.5, 1.0],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, vignette);
  }

  @override
  bool shouldRepaint(covariant _VignettePainter oldDelegate) {
    return oldDelegate.depth != depth;
  }
}

/// Frosted / solid panel helper for cards that want extra emphasis.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.borderRadius,
    this.padding,
  });

  final Widget child;
  final double? borderRadius;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final ui = AnimaUiTheme.of(context);
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(borderRadius ?? ui.cornerRadius);
    final fill = ui.visualStyle == VisualStyle.glass
        ? scheme.surfaceContainerHigh.withValues(alpha: ui.glassOpacity * 0.65)
        : scheme.surfaceContainerHigh;
    final content = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        color: fill,
        border: Border.all(color: scheme.primary.withValues(alpha: 0.22)),
        boxShadow: [
          BoxShadow(
            color: scheme.primary.withValues(alpha: 0.08),
            blurRadius: 24,
            spreadRadius: -4,
          ),
        ],
      ),
      child: padding == null ? child : Padding(padding: padding!, child: child),
    );

    if (ui.visualStyle != VisualStyle.glass || ui.glassBlur <= 0) {
      return ClipRRect(borderRadius: radius, child: content);
    }

    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: ui.glassBlur, sigmaY: ui.glassBlur),
        child: content,
      ),
    );
  }
}
