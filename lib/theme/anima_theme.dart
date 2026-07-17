import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/ui_style_settings.dart';

/// Anima’s single look: Obsidian & Gold — dark glassmorphism with gold accents.
class AnimaTheme {
  /// When true, skip Google Fonts (tests / offline) and use the platform typeface.
  static bool useSystemFonts = false;

  static const obsidian = Color(0xFF050508);
  static const obsidianDeep = Color(0xFF020204);
  static const glass = Color(0xFF14141A);
  static const glassHigh = Color(0xFF1E1E28);
  static const gold = Color(0xFFE8C547);
  static const goldDeep = Color(0xFFB8860B);
  static const goldSoft = Color(0xFFF5E6A8);
  static const ink = Color(0xFFF4F0E6);
  static const inkMuted = Color(0xFFB8B0A0);

  static ThemeData dark() {
    const scheme = ColorScheme(
      brightness: Brightness.dark,
      primary: gold,
      onPrimary: Color(0xFF1A1400),
      primaryContainer: Color(0xFF3D3208),
      onPrimaryContainer: goldSoft,
      secondary: goldDeep,
      onSecondary: Color(0xFF1A1400),
      secondaryContainer: Color(0xFF2A2410),
      onSecondaryContainer: goldSoft,
      tertiary: Color(0xFFFFD56A),
      onTertiary: Color(0xFF1A1400),
      tertiaryContainer: Color(0xFF4A3A10),
      onTertiaryContainer: goldSoft,
      error: Color(0xFFFF6B6B),
      onError: Color(0xFF1A0505),
      errorContainer: Color(0xFF5C1515),
      onErrorContainer: Color(0xFFFFDAD6),
      surface: glass,
      onSurface: ink,
      onSurfaceVariant: inkMuted,
      surfaceContainerLowest: obsidianDeep,
      surfaceContainerLow: Color(0xFF0C0C12),
      surfaceContainer: glass,
      surfaceContainerHigh: glassHigh,
      surfaceContainerHighest: Color(0xFF2A2A36),
      outline: Color(0xFF5C5340),
      outlineVariant: Color(0xFF3A3428),
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: goldSoft,
      onInverseSurface: obsidian,
      inversePrimary: goldDeep,
      surfaceTint: gold,
    );

    final radius = BorderRadius.circular(16);
    final textTheme = _textTheme(scheme);
    final titleStyle = _titleStyle(scheme);

    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: Colors.transparent,
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      extensions: const [AnimaUiTheme.standard],
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: glass.withValues(alpha: 0.72),
        foregroundColor: ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: titleStyle.copyWith(fontSize: 22),
        iconTheme: const IconThemeData(color: gold),
        actionsIconTheme: const IconThemeData(color: gold),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.8),
        thickness: 1,
        space: 1,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: gold,
        textColor: ink,
        shape: RoundedRectangleBorder(borderRadius: radius),
      ),
      cardTheme: CardThemeData(
        color: glassHigh.withValues(alpha: 0.55),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: gold.withValues(alpha: 0.18)),
        ),
        margin: const EdgeInsets.symmetric(vertical: 4),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: glassHigh.withValues(alpha: 0.45),
        border: OutlineInputBorder(borderRadius: radius),
        enabledBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: const BorderSide(color: gold, width: 1.6),
        ),
        labelStyle: TextStyle(color: inkMuted),
        hintStyle: TextStyle(color: inkMuted.withValues(alpha: 0.7)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: gold,
          foregroundColor: const Color(0xFF1A1400),
          shape: RoundedRectangleBorder(borderRadius: radius),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: gold,
          shape: RoundedRectangleBorder(borderRadius: radius),
          side: BorderSide(color: gold.withValues(alpha: 0.55)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: gold),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: gold,
        foregroundColor: const Color(0xFF1A1400),
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: glassHigh.withValues(alpha: 0.7),
        selectedColor: goldDeep.withValues(alpha: 0.55),
        labelStyle: textTheme.labelLarge,
        side: BorderSide(color: gold.withValues(alpha: 0.25)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return gold;
          return inkMuted;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return goldDeep.withValues(alpha: 0.55);
          }
          return glassHigh;
        }),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: glassHigh,
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: ink),
        actionTextColor: gold,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: glass,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: gold.withValues(alpha: 0.25)),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: glass,
        modalBackgroundColor: glass,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: glass.withValues(alpha: 0.9),
        indicatorColor: gold.withValues(alpha: 0.22),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: gold);
          }
          return IconThemeData(color: inkMuted);
        }),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: gold),
      iconTheme: const IconThemeData(color: gold),
      popupMenuTheme: PopupMenuThemeData(
        color: glassHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: gold.withValues(alpha: 0.2)),
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: gold,
        thumbColor: gold,
        inactiveTrackColor: scheme.outlineVariant,
        overlayColor: gold.withValues(alpha: 0.16),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const Color(0xFF1A1400);
            }
            return ink;
          }),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return gold;
            return glassHigh.withValues(alpha: 0.5);
          }),
        ),
      ),
    );
  }

  /// Light is unused — Anima is always dark — but kept for ThemeData completeness.
  static ThemeData light() => dark();

  static TextStyle _titleStyle(ColorScheme scheme) {
    if (useSystemFonts) {
      return TextStyle(
        fontWeight: FontWeight.w700,
        color: scheme.onSurface,
        letterSpacing: 0.2,
      );
    }
    return GoogleFonts.outfit(
      fontWeight: FontWeight.w700,
      color: scheme.onSurface,
      letterSpacing: 0.2,
    );
  }

  static TextTheme _textTheme(ColorScheme scheme) {
    final base = useSystemFonts
        ? Typography.material2021(platform: TargetPlatform.android).white
        : GoogleFonts.plusJakartaSansTextTheme(
            Typography.material2021(platform: TargetPlatform.android).white,
          );

    return base
        .apply(
          bodyColor: scheme.onSurface,
          displayColor: scheme.onSurface,
        )
        .copyWith(
          headlineLarge: _titleStyle(scheme).copyWith(fontSize: 32),
          headlineMedium: _titleStyle(scheme).copyWith(fontSize: 26),
          headlineSmall: _titleStyle(scheme).copyWith(fontSize: 22),
          titleLarge: _titleStyle(scheme).copyWith(fontSize: 20),
          titleMedium: base.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: scheme.onSurface,
          ),
          labelLarge: base.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
            color: scheme.primary,
          ),
        );
  }
}
