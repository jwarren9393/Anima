import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/ui_style_settings.dart';

/// Builds Anima [ThemeData] from [UiStyleSettings] (presets + overrides).
class AnimaTheme {
  /// When true, skip Google Fonts (tests / offline) and use the platform typeface.
  static bool useSystemFonts = false;

  static const pine = Color(0xFF3D5C4A);
  static const brass = Color(0xFFA67C3D);
  static const ink = Color(0xFF2C241B);
  static const parchment = Color(0xFFE8D9BC);
  static const parchmentDeep = Color(0xFFD9C7A3);
  static const night = Color(0xFF161410);
  static const nightSurface = Color(0xFF241F1A);

  static ThemeData light([UiStyleSettings style = const UiStyleSettings()]) {
    return _build(style, dark: false);
  }

  static ThemeData dark([UiStyleSettings style = const UiStyleSettings()]) {
    return _build(style, dark: true);
  }

  static ThemeData _build(UiStyleSettings style, {required bool dark}) {
    final scheme = _schemeFor(style, dark: dark);
    final radius = BorderRadius.circular(style.cornerRadius);
    final textTheme = _textTheme(style, scheme);
    final displayTitle = _titleStyle(style, scheme);

    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      brightness: scheme.brightness,
      scaffoldBackgroundColor: Colors.transparent,
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      visualDensity: switch (style.density) {
        UiDensity.comfortable => VisualDensity.standard,
        UiDensity.cozy => VisualDensity.comfortable,
        UiDensity.compact => VisualDensity.compact,
      },
      extensions: [AnimaUiTheme.fromSettings(style)],
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: dark
            ? scheme.surfaceContainer
            : (style.surfaceColor ?? scheme.surface),
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        titleTextStyle: displayTitle.copyWith(fontSize: 22 * style.fontScale),
        iconTheme: IconThemeData(color: scheme.primary),
        actionsIconTheme: IconThemeData(color: scheme.primary),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.7),
        thickness: 1,
        space: 1,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: scheme.primary,
        textColor: scheme.onSurface,
        dense: style.density == UiDensity.compact,
        visualDensity: switch (style.density) {
          UiDensity.comfortable => VisualDensity.standard,
          UiDensity.cozy => VisualDensity.comfortable,
          UiDensity.compact => VisualDensity.compact,
        },
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark
            ? scheme.surfaceContainerHighest.withValues(alpha: 0.55)
            : scheme.surfaceContainerLowest.withValues(alpha: 0.85),
        border: OutlineInputBorder(borderRadius: radius),
        enabledBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: radius),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: radius),
          side: BorderSide(color: scheme.outline),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: scheme.primary),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        extendedTextStyle: displayTitle.copyWith(
          color: scheme.onPrimary,
          fontSize: 14 * style.fontScale,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(style.cornerRadius + 2),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.secondaryContainer.withValues(alpha: 0.55),
        selectedColor: scheme.primaryContainer,
        labelStyle: textTheme.labelLarge,
        side: BorderSide(color: scheme.outlineVariant),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(style.cornerRadius - 2),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: dark ? scheme.surfaceContainer : scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.75)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: dark ? scheme.surfaceContainer : scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(style.cornerRadius + 4),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: dark ? scheme.surfaceContainer : scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(style.cornerRadius + 6),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: dark ? scheme.inverseSurface : scheme.onSurface,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: dark ? scheme.onInverseSurface : scheme.surface,
        ),
        shape: RoundedRectangleBorder(borderRadius: radius),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: scheme.primary),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return scheme.primary;
          return scheme.outline;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return scheme.primaryContainer;
          }
          return scheme.surfaceContainerHighest;
        }),
      ),
      pageTransitionsTheme: PageTransitionsTheme(
        builders: {
          for (final platform in TargetPlatform.values)
            platform: style.reduceMotion
                ? const _InstantPageTransitionsBuilder()
                : const ZoomPageTransitionsBuilder(),
        },
      ),
    );
  }

  static ColorScheme _schemeFor(UiStyleSettings style, {required bool dark}) {
    final base = _presetScheme(style.preset, dark: dark);
    var scheme = base;

    if (style.primaryColor != null) {
      final p = style.primaryColor!;
      scheme = scheme.copyWith(
        primary: p,
        primaryContainer: Color.lerp(p, scheme.surface, dark ? 0.55 : 0.72)!,
        onPrimary: _onColor(p),
        onPrimaryContainer: dark ? scheme.onPrimaryContainer : _onColor(
          Color.lerp(p, scheme.surface, 0.72)!,
        ),
        inversePrimary: Color.lerp(p, Colors.white, 0.35),
      );
    }
    if (style.accentColor != null) {
      final a = style.accentColor!;
      scheme = scheme.copyWith(
        secondary: a,
        secondaryContainer: Color.lerp(a, scheme.surface, dark ? 0.5 : 0.7)!,
        onSecondary: _onColor(a),
      );
    }
    if (style.backgroundColor != null || style.surfaceColor != null) {
      final surface = style.surfaceColor ?? style.backgroundColor ?? scheme.surface;
      final bg = style.backgroundColor ?? surface;
      scheme = scheme.copyWith(
        surface: surface,
        surfaceContainerLowest: Color.lerp(bg, Colors.white, dark ? 0.02 : 0.08),
        surfaceContainerLow: Color.lerp(bg, surface, 0.35),
        surfaceContainer: Color.lerp(bg, surface, 0.55),
        surfaceContainerHigh: Color.lerp(surface, scheme.onSurface, dark ? 0.08 : 0.06),
        surfaceContainerHighest:
            Color.lerp(surface, scheme.onSurface, dark ? 0.14 : 0.1),
      );
    }
    if (style.inkColor != null) {
      final ink = style.inkColor!;
      scheme = scheme.copyWith(
        onSurface: ink,
        onSurfaceVariant: Color.lerp(ink, scheme.surface, 0.35),
      );
    }
    return scheme;
  }

  static Color _onColor(Color c) {
    return ThemeData.estimateBrightnessForColor(c) == Brightness.dark
        ? Colors.white
        : const Color(0xFF1A1510);
  }

  static ColorScheme _presetScheme(VisualPreset preset, {required bool dark}) {
    switch (preset) {
      case VisualPreset.parchment:
        return dark ? _parchmentDark : _parchmentLight;
      case VisualPreset.teal:
        return ColorScheme.fromSeed(
          seedColor: const Color(0xFF2F6F6A),
          brightness: dark ? Brightness.dark : Brightness.light,
        );
      case VisualPreset.midnight:
        return dark ? _midnightDark : _midnightLight;
      case VisualPreset.ember:
        return dark ? _emberDark : _emberLight;
      case VisualPreset.mist:
        return ColorScheme.fromSeed(
          seedColor: const Color(0xFF5B6E7A),
          brightness: dark ? Brightness.dark : Brightness.light,
        );
    }
  }

  static const _parchmentLight = ColorScheme(
    brightness: Brightness.light,
    primary: pine,
    onPrimary: Color(0xFFF5EFE0),
    primaryContainer: Color(0xFFC5D4C8),
    onPrimaryContainer: Color(0xFF1A2E24),
    secondary: brass,
    onSecondary: Color(0xFFFFF8EB),
    secondaryContainer: Color(0xFFE8D4B0),
    onSecondaryContainer: Color(0xFF3A2A12),
    tertiary: Color(0xFF6B4F3A),
    onTertiary: Color(0xFFFFF4E8),
    tertiaryContainer: Color(0xFFE2CDB8),
    onTertiaryContainer: Color(0xFF2E1F14),
    error: Color(0xFF8B3A2F),
    onError: Color(0xFFFFF5F0),
    errorContainer: Color(0xFFF0D0C8),
    onErrorContainer: Color(0xFF3D1610),
    surface: parchment,
    onSurface: ink,
    surfaceContainerHighest: Color(0xFFD4C4A4),
    surfaceContainerHigh: Color(0xFFDDCFB2),
    surfaceContainer: Color(0xFFE3D5B8),
    surfaceContainerLow: Color(0xFFEDE1C8),
    surfaceContainerLowest: Color(0xFFF4EBDA),
    onSurfaceVariant: Color(0xFF5A4E3E),
    outline: Color(0xFF8A7A62),
    outlineVariant: Color(0xFFC4B498),
    shadow: Color(0xFF1A1510),
    scrim: Color(0xFF1A1510),
    inverseSurface: Color(0xFF2C241B),
    onInverseSurface: parchment,
    inversePrimary: Color(0xFFA8C4B2),
  );

  static const _parchmentDark = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFFA8C4B2),
    onPrimary: Color(0xFF1A2E24),
    primaryContainer: Color(0xFF3D5C4A),
    onPrimaryContainer: Color(0xFFE4F0E8),
    secondary: Color(0xFFD4B078),
    onSecondary: Color(0xFF2A1E0C),
    secondaryContainer: Color(0xFF5C4524),
    onSecondaryContainer: Color(0xFFF5E6C8),
    tertiary: Color(0xFFC9A990),
    onTertiary: Color(0xFF2E1F14),
    tertiaryContainer: Color(0xFF4A382C),
    onTertiaryContainer: Color(0xFFF0E0D0),
    error: Color(0xFFE8A090),
    onError: Color(0xFF3D1610),
    errorContainer: Color(0xFF5C2A22),
    onErrorContainer: Color(0xFFF8D8D0),
    surface: night,
    onSurface: Color(0xFFEDE3D0),
    surfaceContainerHighest: Color(0xFF3A342C),
    surfaceContainerHigh: Color(0xFF302B24),
    surfaceContainer: nightSurface,
    surfaceContainerLow: Color(0xFF1C1814),
    surfaceContainerLowest: Color(0xFF100E0C),
    onSurfaceVariant: Color(0xFFC4B8A4),
    outline: Color(0xFF8A7E6C),
    outlineVariant: Color(0xFF4A4338),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    inverseSurface: parchment,
    onInverseSurface: ink,
    inversePrimary: pine,
  );

  static const _midnightLight = ColorScheme(
    brightness: Brightness.light,
    primary: Color(0xFF3D4F6B),
    onPrimary: Color(0xFFF2F5FA),
    primaryContainer: Color(0xFFD5DDEA),
    onPrimaryContainer: Color(0xFF1A2436),
    secondary: Color(0xFF6B5B7A),
    onSecondary: Color(0xFFF8F4FA),
    secondaryContainer: Color(0xFFE6DCEC),
    onSecondaryContainer: Color(0xFF2A2034),
    tertiary: Color(0xFF4A6670),
    onTertiary: Color(0xFFF0F6F8),
    tertiaryContainer: Color(0xFFD5E4E8),
    onTertiaryContainer: Color(0xFF1A2A30),
    error: Color(0xFF8B3A2F),
    onError: Color(0xFFFFF5F0),
    errorContainer: Color(0xFFF0D0C8),
    onErrorContainer: Color(0xFF3D1610),
    surface: Color(0xFFE8ECF2),
    onSurface: Color(0xFF1A1F2A),
    surfaceContainerHighest: Color(0xFFC8D0DC),
    surfaceContainerHigh: Color(0xFFD4DBE6),
    surfaceContainer: Color(0xFFDCE2EC),
    surfaceContainerLow: Color(0xFFE4E9F0),
    surfaceContainerLowest: Color(0xFFF4F6FA),
    onSurfaceVariant: Color(0xFF4A5568),
    outline: Color(0xFF6B7688),
    outlineVariant: Color(0xFFB0B8C8),
    shadow: Color(0xFF101418),
    scrim: Color(0xFF101418),
    inverseSurface: Color(0xFF1A1F2A),
    onInverseSurface: Color(0xFFE8ECF2),
    inversePrimary: Color(0xFFA8B8D4),
  );

  static final _midnightDark = ColorScheme.fromSeed(
    seedColor: const Color(0xFF8FA3C4),
    brightness: Brightness.dark,
  );

  static const _emberLight = ColorScheme(
    brightness: Brightness.light,
    primary: Color(0xFF8B4518),
    onPrimary: Color(0xFFFFF5E8),
    primaryContainer: Color(0xFFE8C9A8),
    onPrimaryContainer: Color(0xFF3A1E08),
    secondary: Color(0xFFB33B2A),
    onSecondary: Color(0xFFFFF0EC),
    secondaryContainer: Color(0xFFF0C8BE),
    onSecondaryContainer: Color(0xFF3A120C),
    tertiary: Color(0xFF6B4E2E),
    onTertiary: Color(0xFFFFF4E4),
    tertiaryContainer: Color(0xFFE2D0B0),
    onTertiaryContainer: Color(0xFF2A1C0C),
    error: Color(0xFF8B3A2F),
    onError: Color(0xFFFFF5F0),
    errorContainer: Color(0xFFF0D0C8),
    onErrorContainer: Color(0xFF3D1610),
    surface: Color(0xFFF2E4D0),
    onSurface: Color(0xFF2A1C12),
    surfaceContainerHighest: Color(0xFFD8C4A8),
    surfaceContainerHigh: Color(0xFFE0CDB4),
    surfaceContainer: Color(0xFFE8D6BE),
    surfaceContainerLow: Color(0xFFEEE0CC),
    surfaceContainerLowest: Color(0xFFF8F0E4),
    onSurfaceVariant: Color(0xFF5A4636),
    outline: Color(0xFF8A7260),
    outlineVariant: Color(0xFFC4B098),
    shadow: Color(0xFF1A1008),
    scrim: Color(0xFF1A1008),
    inverseSurface: Color(0xFF2A1C12),
    onInverseSurface: Color(0xFFF2E4D0),
    inversePrimary: Color(0xFFD4A070),
  );

  static final _emberDark = ColorScheme.fromSeed(
    seedColor: const Color(0xFFD4783A),
    brightness: Brightness.dark,
  );

  static TextStyle _safeGoogle(
    TextStyle Function() build, {
    TextStyle? fallback,
  }) {
    try {
      return build();
    } catch (_) {
      return fallback ?? const TextStyle();
    }
  }

  static TextTheme _safeGoogleTheme(TextTheme Function() build) {
    try {
      return build();
    } catch (_) {
      return ThemeData(brightness: Brightness.light).textTheme;
    }
  }

  static TextStyle _titleStyle(UiStyleSettings style, ColorScheme scheme) {
    if (useSystemFonts) {
      return TextStyle(
        color: scheme.onSurface,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.4,
        fontSize: 22 * style.fontScale,
      );
    }
    final base = switch (style.fontPairing) {
      FontPairing.fantasy => _safeGoogle(
          () => GoogleFonts.cinzel(
            fontWeight: FontWeight.w600,
            letterSpacing: 0.6,
          ),
        ),
      FontPairing.classicSerif => _safeGoogle(
          () => GoogleFonts.libreBaskerville(fontWeight: FontWeight.w700),
        ),
      FontPairing.cleanSans => _safeGoogle(
          () => GoogleFonts.outfit(
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
      FontPairing.softRounded => _safeGoogle(
          () => GoogleFonts.nunito(fontWeight: FontWeight.w700),
        ),
    };
    return base.copyWith(color: scheme.onSurface);
  }

  static TextTheme _textTheme(UiStyleSettings style, ColorScheme scheme) {
    final scale = style.fontScale;
    if (useSystemFonts) {
      return ThemeData(brightness: scheme.brightness).textTheme.apply(
            bodyColor: scheme.onSurface,
            displayColor: scheme.onSurface,
            fontSizeFactor: scale,
          );
    }
    final TextTheme raw = switch (style.fontPairing) {
      FontPairing.fantasy => _safeGoogleTheme(
          () => GoogleFonts.literataTextTheme().copyWith(
                titleLarge: GoogleFonts.cinzel(
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                ),
                titleMedium: GoogleFonts.cinzel(
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
                titleSmall: GoogleFonts.cinzel(fontWeight: FontWeight.w600),
                headlineSmall: GoogleFonts.cinzel(fontWeight: FontWeight.w600),
              ),
        ),
      FontPairing.classicSerif =>
        _safeGoogleTheme(GoogleFonts.libreBaskervilleTextTheme),
      FontPairing.cleanSans => _safeGoogleTheme(
          () => GoogleFonts.sourceSans3TextTheme().copyWith(
                titleLarge: GoogleFonts.outfit(fontWeight: FontWeight.w600),
                titleMedium: GoogleFonts.outfit(fontWeight: FontWeight.w600),
              ),
        ),
      FontPairing.softRounded => _safeGoogleTheme(GoogleFonts.nunitoTextTheme),
    };

    return raw.apply(
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
      fontSizeFactor: scale,
    );
  }
}

class _InstantPageTransitionsBuilder extends PageTransitionsBuilder {
  const _InstantPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return child;
  }
}
