import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/theme_palette.dart';
import '../models/ui_style_settings.dart';

/// Builds Anima [ThemeData] from Theme Studio settings.
class AnimaTheme {
  /// When true, skip Google Fonts (tests / offline) and use the platform typeface.
  static bool useSystemFonts = false;

  /// Legacy constants kept for branding / fallbacks (launcher docs, tests).
  static const obsidian = Color(0xFF050508);
  static const obsidianDeep = Color(0xFF020204);
  static const glass = Color(0xFF14141A);
  static const glassHigh = Color(0xFF1E1E28);
  static const gold = Color(0xFFE8C547);
  static const goldDeep = Color(0xFFB8860B);
  static const goldSoft = Color(0xFFF5E6A8);
  static const ink = Color(0xFFF4F0E6);
  static const inkMuted = Color(0xFFB8B0A0);

  /// Default Obsidian Gold theme (clean soft-glow, no sparkle texture).
  static ThemeData dark() => fromSettings(UiStyleSettings.defaults());

  static ThemeData light() =>
      fromSettings(UiStyleSettings.fromPreset(ThemePresets.ivoryInk));

  static ThemeData fromSettings(UiStyleSettings settings) {
    final palette = settings.palette;
    final isGlass = settings.isGlass;
    final radius = BorderRadius.circular(settings.cornerRadius);
    final onAccent = _onColor(palette.accent);
    final surfaceAlpha = isGlass
        ? settings.glassOpacity.clamp(0.45, 0.95)
        : 1.0;

    final scheme = ColorScheme(
      brightness: palette.brightness,
      primary: palette.accent,
      onPrimary: onAccent,
      primaryContainer: Color.alphaBlend(
        palette.accent.withValues(alpha: 0.28),
        palette.surfaceHigh,
      ),
      onPrimaryContainer: palette.text,
      secondary: palette.accentDeep,
      onSecondary: _onColor(palette.accentDeep),
      secondaryContainer: Color.alphaBlend(
        palette.accentDeep.withValues(alpha: 0.22),
        palette.surface,
      ),
      onSecondaryContainer: palette.text,
      tertiary: Color.lerp(palette.accent, Colors.white, 0.25)!,
      onTertiary: onAccent,
      tertiaryContainer: Color.alphaBlend(
        palette.accent.withValues(alpha: 0.18),
        palette.surfaceHigh,
      ),
      onTertiaryContainer: palette.text,
      error: const Color(0xFFFF6B6B),
      onError: const Color(0xFF1A0505),
      errorContainer: const Color(0xFF5C1515),
      onErrorContainer: const Color(0xFFFFDAD6),
      surface: palette.surface,
      onSurface: palette.text,
      onSurfaceVariant: palette.textMuted,
      surfaceContainerLowest: palette.background,
      surfaceContainerLow: Color.lerp(
        palette.background,
        palette.surface,
        0.4,
      )!,
      surfaceContainer: palette.surface,
      surfaceContainerHigh: palette.surfaceHigh,
      surfaceContainerHighest: Color.lerp(
        palette.surfaceHigh,
        palette.accent,
        0.08,
      )!,
      outline: Color.lerp(palette.textMuted, palette.accent, 0.25)!,
      outlineVariant: Color.lerp(palette.surfaceHigh, palette.textMuted, 0.35)!,
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: palette.text,
      onInverseSurface: palette.background,
      inversePrimary: palette.accentDeep,
      surfaceTint: palette.accent,
    );

    final textTheme = _textTheme(scheme, settings);
    final titleStyle = _titleStyle(scheme, settings.headingFont);
    final ui = AnimaUiTheme.fromSettings(settings);

    final headerColor = isGlass
        ? palette.header.withValues(alpha: surfaceAlpha)
        : palette.header;
    final cardColor = isGlass
        ? palette.surfaceHigh.withValues(
            alpha: (surfaceAlpha * 0.85).clamp(0.4, 1),
          )
        : palette.surfaceHigh;
    final fieldFill = isGlass
        ? palette.surfaceHigh.withValues(alpha: 0.45)
        : palette.surfaceHigh;

    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      brightness: palette.brightness,
      scaffoldBackgroundColor: isGlass
          ? Colors.transparent
          : palette.background,
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      extensions: [ui],
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: headerColor,
        foregroundColor: palette.text,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: titleStyle.copyWith(
          fontSize: 22 * settings.headingScale,
        ),
        iconTheme: IconThemeData(color: palette.accent),
        actionsIconTheme: IconThemeData(color: palette.accent),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.8),
        thickness: 1,
        space: 1,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: palette.accent,
        textColor: palette.text,
        shape: RoundedRectangleBorder(borderRadius: radius),
      ),
      cardTheme: CardThemeData(
        color: cardColor,
        elevation: isGlass ? 0 : 1,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: palette.accent.withValues(alpha: 0.18)),
        ),
        margin: const EdgeInsets.symmetric(vertical: 4),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: fieldFill,
        border: OutlineInputBorder(borderRadius: radius),
        enabledBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: palette.accent, width: 1.6),
        ),
        labelStyle: TextStyle(color: palette.textMuted),
        hintStyle: TextStyle(color: palette.textMuted.withValues(alpha: 0.7)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: palette.accent,
          foregroundColor: onAccent,
          shape: RoundedRectangleBorder(borderRadius: radius),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: palette.accent,
          shape: RoundedRectangleBorder(borderRadius: radius),
          side: BorderSide(color: palette.accent.withValues(alpha: 0.55)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: palette.accent),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: palette.accent,
        foregroundColor: onAccent,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(settings.cornerRadius + 2),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: isGlass
            ? palette.surfaceHigh.withValues(alpha: 0.7)
            : palette.surfaceHigh,
        selectedColor: palette.accentDeep.withValues(alpha: 0.55),
        labelStyle: textTheme.labelLarge,
        side: BorderSide(color: palette.accent.withValues(alpha: 0.25)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(settings.cornerRadius * 0.75),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return palette.accent;
          return palette.textMuted;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return palette.accentDeep.withValues(alpha: 0.55);
          }
          return palette.surfaceHigh;
        }),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: palette.surfaceHigh,
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: palette.text),
        actionTextColor: palette.accent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(settings.cornerRadius * 0.85),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: palette.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(settings.cornerRadius + 4),
          side: BorderSide(color: palette.accent.withValues(alpha: 0.25)),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: palette.surface,
        modalBackgroundColor: palette.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(settings.cornerRadius + 6),
          ),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: isGlass
            ? palette.surface.withValues(alpha: 0.9)
            : palette.surface,
        indicatorColor: palette.accent.withValues(alpha: 0.22),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: palette.accent);
          }
          return IconThemeData(color: palette.textMuted);
        }),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: palette.accent),
      iconTheme: IconThemeData(color: palette.accent),
      popupMenuTheme: PopupMenuThemeData(
        color: palette.surfaceHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(settings.cornerRadius * 0.85),
          side: BorderSide(color: palette.accent.withValues(alpha: 0.2)),
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: palette.accent,
        thumbColor: palette.accent,
        inactiveTrackColor: scheme.outlineVariant,
        overlayColor: palette.accent.withValues(alpha: 0.16),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return onAccent;
            return palette.text;
          }),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return palette.accent;
            return isGlass
                ? palette.surfaceHigh.withValues(alpha: 0.5)
                : palette.surfaceHigh;
          }),
        ),
      ),
    );
  }

  static Color _onColor(Color background) {
    return background.computeLuminance() > 0.55
        ? const Color(0xFF1A1400)
        : const Color(0xFFF4F0E6);
  }

  static TextStyle _titleStyle(ColorScheme scheme, AnimaFontChoice font) {
    if (useSystemFonts || font == AnimaFontChoice.system) {
      return TextStyle(
        fontWeight: FontWeight.w700,
        color: scheme.onSurface,
        letterSpacing: 0.2,
      );
    }
    try {
      switch (font) {
        case AnimaFontChoice.outfit:
          return GoogleFonts.outfit(
            fontWeight: FontWeight.w700,
            color: scheme.onSurface,
            letterSpacing: 0.2,
          );
        case AnimaFontChoice.plusJakartaSans:
          return GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w700,
            color: scheme.onSurface,
            letterSpacing: 0.2,
          );
        case AnimaFontChoice.inter:
          return GoogleFonts.inter(
            fontWeight: FontWeight.w700,
            color: scheme.onSurface,
            letterSpacing: 0.2,
          );
        case AnimaFontChoice.merriweather:
          return GoogleFonts.merriweather(
            fontWeight: FontWeight.w700,
            color: scheme.onSurface,
            letterSpacing: 0.2,
          );
        case AnimaFontChoice.sourceSerif4:
          return GoogleFonts.sourceSerif4(
            fontWeight: FontWeight.w700,
            color: scheme.onSurface,
            letterSpacing: 0.2,
          );
        case AnimaFontChoice.system:
          break;
      }
    } catch (_) {}
    return TextStyle(
      fontWeight: FontWeight.w700,
      color: scheme.onSurface,
      letterSpacing: 0.2,
    );
  }

  static TextTheme _bodyBase(AnimaFontChoice font) {
    final white = Typography.material2021(
      platform: TargetPlatform.android,
    ).white;
    if (useSystemFonts || font == AnimaFontChoice.system) {
      return white;
    }
    try {
      switch (font) {
        case AnimaFontChoice.plusJakartaSans:
          return GoogleFonts.plusJakartaSansTextTheme(white);
        case AnimaFontChoice.inter:
          return GoogleFonts.interTextTheme(white);
        case AnimaFontChoice.merriweather:
          return GoogleFonts.merriweatherTextTheme(white);
        case AnimaFontChoice.sourceSerif4:
          return GoogleFonts.sourceSerif4TextTheme(white);
        case AnimaFontChoice.outfit:
          return GoogleFonts.outfitTextTheme(white);
        case AnimaFontChoice.system:
          break;
      }
    } catch (_) {}
    return white;
  }

  /// Material 2021 text styles may leave [TextStyle.fontSize] null; [TextTheme.apply]
  /// with a non-1.0 [fontSizeFactor] asserts in that case — scale explicitly.
  static TextStyle? _scaledBodyStyle(
    TextStyle? style,
    double fallbackSize,
    double textScale,
    Color color,
  ) {
    if (style == null) return null;
    final size = style.fontSize ?? fallbackSize;
    return style.copyWith(fontSize: size * textScale, color: color);
  }

  static TextTheme _textTheme(ColorScheme scheme, UiStyleSettings settings) {
    final base = _bodyBase(settings.bodyFont);
    final title = _titleStyle(scheme, settings.headingFont);
    final textScale = settings.textScale;
    final headingScale = settings.headingScale;
    final onSurface = scheme.onSurface;

    return base.copyWith(
      displayLarge: _scaledBodyStyle(base.displayLarge, 57, textScale, onSurface),
      displayMedium: _scaledBodyStyle(base.displayMedium, 45, textScale, onSurface),
      displaySmall: _scaledBodyStyle(base.displaySmall, 36, textScale, onSurface),
      headlineLarge: title.copyWith(fontSize: 32 * headingScale),
      headlineMedium: title.copyWith(fontSize: 26 * headingScale),
      headlineSmall: title.copyWith(fontSize: 22 * headingScale),
      titleLarge: title.copyWith(fontSize: 20 * headingScale),
      titleMedium: _scaledBodyStyle(
        base.titleMedium,
        16,
        textScale,
        onSurface,
      )?.copyWith(fontWeight: FontWeight.w600),
      titleSmall: _scaledBodyStyle(base.titleSmall, 14, textScale, onSurface),
      bodyLarge: _scaledBodyStyle(base.bodyLarge, 16, textScale, onSurface),
      bodyMedium: _scaledBodyStyle(base.bodyMedium, 14, textScale, onSurface),
      bodySmall: _scaledBodyStyle(base.bodySmall, 12, textScale, onSurface),
      labelLarge: _scaledBodyStyle(
        base.labelLarge,
        14,
        textScale,
        scheme.primary,
      )?.copyWith(fontWeight: FontWeight.w600),
      labelMedium: _scaledBodyStyle(base.labelMedium, 12, textScale, onSurface),
      labelSmall: _scaledBodyStyle(base.labelSmall, 11, textScale, onSurface),
    );
  }
}
