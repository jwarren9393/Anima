import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Glass blur panels vs solid opaque surfaces.
enum VisualStyle {
  glass,
  solid;

  static VisualStyle fromStorage(String? raw) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case 'solid':
        return VisualStyle.solid;
      default:
        return VisualStyle.glass;
    }
  }

  String get storageValue => name;

  String get label => switch (this) {
    VisualStyle.glass => 'Glass',
    VisualStyle.solid => 'Solid',
  };
}

/// How the app backdrop is painted.
enum BackgroundMode {
  solid,
  gradient,
  softGlow;

  static BackgroundMode fromStorage(String? raw) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case 'solid':
        return BackgroundMode.solid;
      case 'softglow':
      case 'soft_glow':
        return BackgroundMode.softGlow;
      default:
        return BackgroundMode.gradient;
    }
  }

  String get storageValue => switch (this) {
    BackgroundMode.solid => 'solid',
    BackgroundMode.gradient => 'gradient',
    BackgroundMode.softGlow => 'softGlow',
  };

  String get label => switch (this) {
    BackgroundMode.solid => 'Solid',
    BackgroundMode.gradient => 'Gradient',
    BackgroundMode.softGlow => 'Soft glow',
  };
}

/// Curated Google Font / system font choices for Appearance.
enum AnimaFontChoice {
  outfit,
  plusJakartaSans,
  inter,
  merriweather,
  sourceSerif4,
  system;

  static AnimaFontChoice fromStorage(String? raw) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case 'plusjakartasans':
      case 'plus_jakarta_sans':
        return AnimaFontChoice.plusJakartaSans;
      case 'inter':
        return AnimaFontChoice.inter;
      case 'merriweather':
        return AnimaFontChoice.merriweather;
      case 'sourceserif4':
      case 'source_serif_4':
      case 'sourceserif':
        return AnimaFontChoice.sourceSerif4;
      case 'system':
        return AnimaFontChoice.system;
      default:
        return AnimaFontChoice.outfit;
    }
  }

  String get storageValue => switch (this) {
    AnimaFontChoice.outfit => 'outfit',
    AnimaFontChoice.plusJakartaSans => 'plusJakartaSans',
    AnimaFontChoice.inter => 'inter',
    AnimaFontChoice.merriweather => 'merriweather',
    AnimaFontChoice.sourceSerif4 => 'sourceSerif4',
    AnimaFontChoice.system => 'system',
  };

  String get label => switch (this) {
    AnimaFontChoice.outfit => 'Outfit',
    AnimaFontChoice.plusJakartaSans => 'Plus Jakarta Sans',
    AnimaFontChoice.inter => 'Inter',
    AnimaFontChoice.merriweather => 'Merriweather',
    AnimaFontChoice.sourceSerif4 => 'Source Serif',
    AnimaFontChoice.system => 'System',
  };
}

/// Core colors that drive ThemeData + backdrop + chat bubbles.
class ThemePalette {
  const ThemePalette({
    required this.background,
    required this.backgroundAlt,
    required this.surface,
    required this.surfaceHigh,
    required this.accent,
    required this.accentDeep,
    required this.header,
    required this.text,
    required this.textMuted,
    required this.userBubble,
    required this.aiBubble,
    this.brightness = Brightness.dark,
  });

  final Color background;
  final Color backgroundAlt;
  final Color surface;
  final Color surfaceHigh;
  final Color accent;
  final Color accentDeep;
  final Color header;
  final Color text;
  final Color textMuted;
  final Color userBubble;
  final Color aiBubble;
  final Brightness brightness;

  ThemePalette copyWith({
    Color? background,
    Color? backgroundAlt,
    Color? surface,
    Color? surfaceHigh,
    Color? accent,
    Color? accentDeep,
    Color? header,
    Color? text,
    Color? textMuted,
    Color? userBubble,
    Color? aiBubble,
    Brightness? brightness,
  }) {
    return ThemePalette(
      background: background ?? this.background,
      backgroundAlt: backgroundAlt ?? this.backgroundAlt,
      surface: surface ?? this.surface,
      surfaceHigh: surfaceHigh ?? this.surfaceHigh,
      accent: accent ?? this.accent,
      accentDeep: accentDeep ?? this.accentDeep,
      header: header ?? this.header,
      text: text ?? this.text,
      textMuted: textMuted ?? this.textMuted,
      userBubble: userBubble ?? this.userBubble,
      aiBubble: aiBubble ?? this.aiBubble,
      brightness: brightness ?? this.brightness,
    );
  }

  Map<String, dynamic> toJson() => {
    'background': colorToHex(background),
    'backgroundAlt': colorToHex(backgroundAlt),
    'surface': colorToHex(surface),
    'surfaceHigh': colorToHex(surfaceHigh),
    'accent': colorToHex(accent),
    'accentDeep': colorToHex(accentDeep),
    'header': colorToHex(header),
    'text': colorToHex(text),
    'textMuted': colorToHex(textMuted),
    'userBubble': colorToHex(userBubble),
    'aiBubble': colorToHex(aiBubble),
    'brightness': brightness == Brightness.light ? 'light' : 'dark',
  };

  factory ThemePalette.fromJson(
    Map<String, dynamic> json, {
    ThemePalette? fallback,
  }) {
    final base = fallback ?? ThemePresets.obsidianGold.palette;
    return ThemePalette(
      background: colorFromHex(json['background'], base.background),
      backgroundAlt: colorFromHex(json['backgroundAlt'], base.backgroundAlt),
      surface: colorFromHex(json['surface'], base.surface),
      surfaceHigh: colorFromHex(json['surfaceHigh'], base.surfaceHigh),
      accent: colorFromHex(json['accent'], base.accent),
      accentDeep: colorFromHex(json['accentDeep'], base.accentDeep),
      header: colorFromHex(json['header'], base.header),
      text: colorFromHex(json['text'], base.text),
      textMuted: colorFromHex(json['textMuted'], base.textMuted),
      userBubble: colorFromHex(json['userBubble'], base.userBubble),
      aiBubble: colorFromHex(json['aiBubble'], base.aiBubble),
      brightness: '${json['brightness'] ?? ''}'.toLowerCase() == 'light'
          ? Brightness.light
          : Brightness.dark,
    );
  }

  static String colorToHex(Color color) {
    final value = color
        .toARGB32()
        .toRadixString(16)
        .padLeft(8, '0')
        .toUpperCase();
    return '#$value';
  }

  static Color colorFromHex(Object? raw, Color fallback) {
    if (raw is! String) return fallback;
    var hex = raw.trim();
    if (hex.startsWith('#')) hex = hex.substring(1);
    if (hex.length == 6) hex = 'FF$hex';
    if (hex.length != 8) return fallback;
    final parsed = int.tryParse(hex, radix: 16);
    if (parsed == null) return fallback;
    return Color(parsed);
  }

  /// Rough WCAG contrast ratio for tests / sanity checks.
  static double contrastRatio(Color a, Color b) {
    double lum(Color c) {
      double channel(double v) {
        final s = v;
        return s <= 0.03928
            ? s / 12.92
            : math.pow((s + 0.055) / 1.055, 2.4).toDouble();
      }

      final r = channel(c.r);
      final g = channel(c.g);
      final bl = channel(c.b);
      return 0.2126 * r + 0.7152 * g + 0.0722 * bl;
    }

    final l1 = lum(a);
    final l2 = lum(b);
    final lighter = l1 > l2 ? l1 : l2;
    final darker = l1 > l2 ? l2 : l1;
    return (lighter + 0.05) / (darker + 0.05);
  }
}

/// One curated global look.
class ThemePreset {
  const ThemePreset({
    required this.id,
    required this.name,
    required this.description,
    required this.visualStyle,
    required this.backgroundMode,
    required this.palette,
    this.headingFont = AnimaFontChoice.outfit,
    this.bodyFont = AnimaFontChoice.plusJakartaSans,
    this.cornerRadius = 16,
    this.glassOpacity = 0.72,
    this.glassBlur = 18,
    this.chatFontScale = 1.0,
    this.textScale = 1.0,
    this.headingScale = 1.0,
  });

  final String id;
  final String name;
  final String description;
  final VisualStyle visualStyle;
  final BackgroundMode backgroundMode;
  final ThemePalette palette;
  final AnimaFontChoice headingFont;
  final AnimaFontChoice bodyFont;
  final double cornerRadius;
  final double glassOpacity;
  final double glassBlur;
  final double chatFontScale;
  final double textScale;
  final double headingScale;
}

/// Built-in Theme Studio presets (glass + solid).
class ThemePresets {
  static const customId = 'custom';

  static const obsidianGold = ThemePreset(
    id: 'obsidian_gold',
    name: 'Obsidian Gold',
    description: 'Classic dark glass with warm gold accents.',
    visualStyle: VisualStyle.glass,
    backgroundMode: BackgroundMode.softGlow,
    palette: ThemePalette(
      background: Color(0xFF050508),
      backgroundAlt: Color(0xFF0A0A12),
      surface: Color(0xFF14141A),
      surfaceHigh: Color(0xFF1E1E28),
      accent: Color(0xFFE8C547),
      accentDeep: Color(0xFFB8860B),
      header: Color(0xFF14141A),
      text: Color(0xFFF4F0E6),
      textMuted: Color(0xFFB8B0A0),
      userBubble: Color(0xE6B8860B),
      aiBubble: Color(0xB31A1A1F),
    ),
  );

  static const midnightSapphire = ThemePreset(
    id: 'midnight_sapphire',
    name: 'Midnight Sapphire',
    description: 'Deep navy glass with cool sapphire highlights.',
    visualStyle: VisualStyle.glass,
    backgroundMode: BackgroundMode.softGlow,
    palette: ThemePalette(
      background: Color(0xFF040814),
      backgroundAlt: Color(0xFF0A1630),
      surface: Color(0xFF121C30),
      surfaceHigh: Color(0xFF1A2740),
      accent: Color(0xFF6EB6FF),
      accentDeep: Color(0xFF3B7DD8),
      header: Color(0xFF121C30),
      text: Color(0xFFE8F0FF),
      textMuted: Color(0xFF9BB0CC),
      userBubble: Color(0xE63B7DD8),
      aiBubble: Color(0xB3141E30),
    ),
  );

  static const emeraldNoir = ThemePreset(
    id: 'emerald_noir',
    name: 'Emerald Noir',
    description: 'Black glass with emerald glow.',
    visualStyle: VisualStyle.glass,
    backgroundMode: BackgroundMode.softGlow,
    palette: ThemePalette(
      background: Color(0xFF030806),
      backgroundAlt: Color(0xFF0A1610),
      surface: Color(0xFF101A16),
      surfaceHigh: Color(0xFF18241E),
      accent: Color(0xFF4FD68A),
      accentDeep: Color(0xFF2E9B5E),
      header: Color(0xFF101A16),
      text: Color(0xFFE8F5EE),
      textMuted: Color(0xFF9DB8A8),
      userBubble: Color(0xE62E9B5E),
      aiBubble: Color(0xB3121C18),
    ),
  );

  static const roseAurora = ThemePreset(
    id: 'rose_aurora',
    name: 'Rose Aurora',
    description: 'Soft dusk glass with rose and lilac light.',
    visualStyle: VisualStyle.glass,
    backgroundMode: BackgroundMode.softGlow,
    palette: ThemePalette(
      background: Color(0xFF100810),
      backgroundAlt: Color(0xFF1A1018),
      surface: Color(0xFF22141E),
      surfaceHigh: Color(0xFF2C1A28),
      accent: Color(0xFFFF8FB8),
      accentDeep: Color(0xFFD45A8C),
      header: Color(0xFF22141E),
      text: Color(0xFFFFF0F5),
      textMuted: Color(0xFFC8A8B8),
      userBubble: Color(0xE6D45A8C),
      aiBubble: Color(0xB3221420),
    ),
  );

  static const slateMinimal = ThemePreset(
    id: 'slate_minimal',
    name: 'Slate Minimal',
    description: 'Clean solid dark slate — no glass blur.',
    visualStyle: VisualStyle.solid,
    backgroundMode: BackgroundMode.solid,
    palette: ThemePalette(
      background: Color(0xFF121417),
      backgroundAlt: Color(0xFF121417),
      surface: Color(0xFF1C1F24),
      surfaceHigh: Color(0xFF262A31),
      accent: Color(0xFF8AB4F8),
      accentDeep: Color(0xFF5B8DEF),
      header: Color(0xFF1C1F24),
      text: Color(0xFFE8EAED),
      textMuted: Color(0xFF9AA0A6),
      userBubble: Color(0xFF5B8DEF),
      aiBubble: Color(0xFF262A31),
    ),
  );

  static const ivoryInk = ThemePreset(
    id: 'ivory_ink',
    name: 'Ivory Ink',
    description: 'Readable light paper look with ink accents.',
    visualStyle: VisualStyle.solid,
    backgroundMode: BackgroundMode.solid,
    palette: ThemePalette(
      background: Color(0xFFF6F1E8),
      backgroundAlt: Color(0xFFEFE8DC),
      surface: Color(0xFFFFFBF5),
      surfaceHigh: Color(0xFFF0E8DA),
      accent: Color(0xFF8B5E34),
      accentDeep: Color(0xFF6B4423),
      header: Color(0xFFFFFBF5),
      text: Color(0xFF1E1A16),
      textMuted: Color(0xFF6B6258),
      userBubble: Color(0xFF8B5E34),
      aiBubble: Color(0xFFEDE4D4),
      brightness: Brightness.light,
    ),
    headingFont: AnimaFontChoice.merriweather,
    bodyFont: AnimaFontChoice.sourceSerif4,
  );

  static const cyberViolet = ThemePreset(
    id: 'cyber_violet',
    name: 'Cyber Violet',
    description: 'Bold neon violet on a solid dark canvas.',
    visualStyle: VisualStyle.solid,
    backgroundMode: BackgroundMode.gradient,
    palette: ThemePalette(
      background: Color(0xFF0B0614),
      backgroundAlt: Color(0xFF160B28),
      surface: Color(0xFF1A1028),
      surfaceHigh: Color(0xFF26183A),
      accent: Color(0xFFC084FC),
      accentDeep: Color(0xFF9333EA),
      header: Color(0xFF1A1028),
      text: Color(0xFFF5E9FF),
      textMuted: Color(0xFFB39BC9),
      userBubble: Color(0xFF9333EA),
      aiBubble: Color(0xFF221433),
    ),
    headingFont: AnimaFontChoice.inter,
    bodyFont: AnimaFontChoice.inter,
  );

  static const forestDusk = ThemePreset(
    id: 'forest_dusk',
    name: 'Forest Dusk',
    description: 'Earthy solid greens and warm amber.',
    visualStyle: VisualStyle.solid,
    backgroundMode: BackgroundMode.gradient,
    palette: ThemePalette(
      background: Color(0xFF0E120C),
      backgroundAlt: Color(0xFF1A2014),
      surface: Color(0xFF1C2418),
      surfaceHigh: Color(0xFF283220),
      accent: Color(0xFFD4A373),
      accentDeep: Color(0xFFB07D4A),
      header: Color(0xFF1C2418),
      text: Color(0xFFF2EDE4),
      textMuted: Color(0xFFA8A090),
      userBubble: Color(0xFFB07D4A),
      aiBubble: Color(0xFF222A1C),
    ),
    headingFont: AnimaFontChoice.merriweather,
    bodyFont: AnimaFontChoice.plusJakartaSans,
  );

  static const List<ThemePreset> all = [
    obsidianGold,
    midnightSapphire,
    emeraldNoir,
    roseAurora,
    slateMinimal,
    ivoryInk,
    cyberViolet,
    forestDusk,
  ];

  static ThemePreset byId(String? id) {
    final key = (id ?? '').trim();
    for (final preset in all) {
      if (preset.id == key) return preset;
    }
    return obsidianGold;
  }
}
