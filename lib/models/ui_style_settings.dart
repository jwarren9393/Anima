import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import 'theme_palette.dart';

/// How chat-message avatars look (shape, size tier, fine scale).
enum AvatarShape {
  circle,
  roundedRect,
  square;

  static AvatarShape fromStorage(String? raw) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case 'roundedrect':
      case 'rounded':
      case 'rect':
        return AvatarShape.roundedRect;
      case 'square':
        return AvatarShape.square;
      default:
        return AvatarShape.circle;
    }
  }

  String get storageValue => switch (this) {
    AvatarShape.circle => 'circle',
    AvatarShape.roundedRect => 'roundedRect',
    AvatarShape.square => 'square',
  };

  String get label => switch (this) {
    AvatarShape.circle => 'Circle',
    AvatarShape.roundedRect => 'Rectangle',
    AvatarShape.square => 'Square',
  };
}

/// Base chat-avatar size before the scale slider.
enum AvatarSizeTier {
  small,
  medium,
  large;

  static AvatarSizeTier fromStorage(String? raw) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case 'small':
        return AvatarSizeTier.small;
      case 'large':
        return AvatarSizeTier.large;
      default:
        return AvatarSizeTier.medium;
    }
  }

  String get storageValue => name;

  String get label => switch (this) {
    AvatarSizeTier.small => 'Small',
    AvatarSizeTier.medium => 'Medium',
    AvatarSizeTier.large => 'Large',
  };

  double get baseSize => switch (this) {
    AvatarSizeTier.small => 40,
    AvatarSizeTier.medium => 56,
    AvatarSizeTier.large => 72,
  };
}

class AvatarStyleSettings {
  const AvatarStyleSettings({
    this.shape = defaultShape,
    this.sizeTier = defaultSizeTier,
    this.scale = defaultScale,
  });

  static const defaultShape = AvatarShape.circle;
  static const defaultSizeTier = AvatarSizeTier.medium;
  static const defaultScale = 1.0;
  static const minScale = 0.75;
  static const maxScale = 1.5;

  final AvatarShape shape;
  final AvatarSizeTier sizeTier;
  final double scale;

  double get size => sizeTier.baseSize * scale;
  double get resolvedSize => size;

  AvatarStyleSettings copyWith({
    AvatarShape? shape,
    AvatarSizeTier? sizeTier,
    double? scale,
  }) {
    return AvatarStyleSettings(
      shape: shape ?? this.shape,
      sizeTier: sizeTier ?? this.sizeTier,
      scale: scale ?? this.scale,
    );
  }

  Map<String, dynamic> toJson() => {
    'avatarShape': shape.storageValue,
    'avatarSize': sizeTier.storageValue,
    'avatarScale': scale,
  };

  factory AvatarStyleSettings.fromJson(Map<String, dynamic> json) {
    final scale = (json['avatarScale'] is num)
        ? (json['avatarScale'] as num).toDouble()
        : double.tryParse('${json['avatarScale'] ?? ''}') ?? defaultScale;
    return AvatarStyleSettings(
      shape: AvatarShape.fromStorage('${json['avatarShape'] ?? ''}'),
      sizeTier: AvatarSizeTier.fromStorage('${json['avatarSize'] ?? ''}'),
      scale: scale.clamp(minScale, maxScale),
    );
  }
}

/// Saved appearance prefs — Theme Studio + chat avatars.
class UiStyleSettings {
  const UiStyleSettings({
    this.presetId = 'obsidian_gold',
    this.visualStyle = VisualStyle.glass,
    this.backgroundMode = BackgroundMode.softGlow,
    this.palette = _defaultPalette,
    this.headingFont = AnimaFontChoice.outfit,
    this.bodyFont = AnimaFontChoice.plusJakartaSans,
    this.textScale = 1.0,
    this.headingScale = 1.0,
    this.chatFontScale = 1.0,
    this.cornerRadius = 16,
    this.glassOpacity = 0.72,
    this.glassBlur = 18,
    this.avatarStyle = const AvatarStyleSettings(),
  });

  static const _defaultPalette = ThemePalette(
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
  );

  static const minTextScale = 0.85;
  static const maxTextScale = 1.35;
  static const minHeadingScale = 0.85;
  static const maxHeadingScale = 1.4;
  static const minChatFontScale = 0.85;
  static const maxChatFontScale = 1.4;
  static const minCornerRadius = 8.0;
  static const maxCornerRadius = 28.0;
  static const minGlassOpacity = 0.35;
  static const maxGlassOpacity = 0.95;
  static const minGlassBlur = 0.0;
  static const maxGlassBlur = 32.0;

  /// Known preset id, or [ThemePresets.customId] after manual tweaks.
  final String presetId;
  final VisualStyle visualStyle;
  final BackgroundMode backgroundMode;
  final ThemePalette palette;
  final AnimaFontChoice headingFont;
  final AnimaFontChoice bodyFont;
  final double textScale;
  final double headingScale;
  final double chatFontScale;
  final double cornerRadius;
  final double glassOpacity;
  final double glassBlur;
  final AvatarStyleSettings avatarStyle;

  bool get isGlass => visualStyle == VisualStyle.glass;
  bool get isCustom => presetId == ThemePresets.customId;
  ThemePreset get resolvedPreset => ThemePresets.byId(presetId);

  factory UiStyleSettings.fromPreset(
    ThemePreset preset, {
    AvatarStyleSettings avatarStyle = const AvatarStyleSettings(),
  }) {
    return UiStyleSettings(
      presetId: preset.id,
      visualStyle: preset.visualStyle,
      backgroundMode: preset.backgroundMode,
      palette: preset.palette,
      headingFont: preset.headingFont,
      bodyFont: preset.bodyFont,
      textScale: preset.textScale,
      headingScale: preset.headingScale,
      chatFontScale: preset.chatFontScale,
      cornerRadius: preset.cornerRadius,
      glassOpacity: preset.glassOpacity,
      glassBlur: preset.glassBlur,
      avatarStyle: avatarStyle,
    );
  }

  static UiStyleSettings defaults({
    AvatarStyleSettings avatarStyle = const AvatarStyleSettings(),
  }) {
    return UiStyleSettings.fromPreset(
      ThemePresets.obsidianGold,
      avatarStyle: avatarStyle,
    );
  }

  UiStyleSettings copyWith({
    String? presetId,
    VisualStyle? visualStyle,
    BackgroundMode? backgroundMode,
    ThemePalette? palette,
    AnimaFontChoice? headingFont,
    AnimaFontChoice? bodyFont,
    double? textScale,
    double? headingScale,
    double? chatFontScale,
    double? cornerRadius,
    double? glassOpacity,
    double? glassBlur,
    AvatarStyleSettings? avatarStyle,
    bool markCustom = false,
  }) {
    return UiStyleSettings(
      presetId: markCustom
          ? ThemePresets.customId
          : (presetId ?? this.presetId),
      visualStyle: visualStyle ?? this.visualStyle,
      backgroundMode: backgroundMode ?? this.backgroundMode,
      palette: palette ?? this.palette,
      headingFont: headingFont ?? this.headingFont,
      bodyFont: bodyFont ?? this.bodyFont,
      textScale: textScale ?? this.textScale,
      headingScale: headingScale ?? this.headingScale,
      chatFontScale: chatFontScale ?? this.chatFontScale,
      cornerRadius: cornerRadius ?? this.cornerRadius,
      glassOpacity: glassOpacity ?? this.glassOpacity,
      glassBlur: glassBlur ?? this.glassBlur,
      avatarStyle: avatarStyle ?? this.avatarStyle,
    );
  }

  Map<String, dynamic> toJson() => {
    'presetId': presetId,
    'visualStyle': visualStyle.storageValue,
    'backgroundMode': backgroundMode.storageValue,
    'palette': palette.toJson(),
    'headingFont': headingFont.storageValue,
    'bodyFont': bodyFont.storageValue,
    'textScale': textScale,
    'headingScale': headingScale,
    'chatFontScale': chatFontScale,
    'cornerRadius': cornerRadius,
    'glassOpacity': glassOpacity,
    'glassBlur': glassBlur,
    ...avatarStyle.toJson(),
  };

  factory UiStyleSettings.fromJson(Map<String, dynamic> json) {
    final avatar = AvatarStyleSettings.fromJson(json);
    final presetIdRaw = '${json['presetId'] ?? json['preset'] ?? ''}'.trim();

    // Legacy avatar-only saves → default Obsidian Gold + saved avatars.
    final hasThemeKeys =
        json.containsKey('palette') ||
        json.containsKey('visualStyle') ||
        json.containsKey('backgroundMode') ||
        json.containsKey('presetId');

    if (!hasThemeKeys) {
      return UiStyleSettings.defaults(avatarStyle: avatar);
    }

    ThemePreset? catalog;
    if (presetIdRaw.isNotEmpty && presetIdRaw != ThemePresets.customId) {
      final match = ThemePresets.byId(presetIdRaw);
      if (match.id == presetIdRaw) catalog = match;
    }

    final fallback = catalog ?? ThemePresets.obsidianGold;
    final paletteRaw = json['palette'];
    final palette = paletteRaw is Map
        ? ThemePalette.fromJson(
            Map<String, dynamic>.from(paletteRaw),
            fallback: fallback.palette,
          )
        : fallback.palette;

    double readScale(
      Object? raw,
      double fallbackValue,
      double min,
      double max,
    ) {
      final parsed = raw is num
          ? raw.toDouble()
          : double.tryParse('${raw ?? ''}') ?? fallbackValue;
      return parsed.clamp(min, max);
    }

    final resolvedPresetId =
        catalog?.id ??
        (presetIdRaw == ThemePresets.customId
            ? ThemePresets.customId
            : (presetIdRaw.isEmpty ? fallback.id : ThemePresets.customId));

    return UiStyleSettings(
      presetId: resolvedPresetId,
      visualStyle: VisualStyle.fromStorage(
        '${json['visualStyle'] ?? fallback.visualStyle.storageValue}',
      ),
      backgroundMode: BackgroundMode.fromStorage(
        '${json['backgroundMode'] ?? fallback.backgroundMode.storageValue}',
      ),
      palette: palette,
      headingFont: AnimaFontChoice.fromStorage(
        '${json['headingFont'] ?? fallback.headingFont.storageValue}',
      ),
      bodyFont: AnimaFontChoice.fromStorage(
        '${json['bodyFont'] ?? fallback.bodyFont.storageValue}',
      ),
      textScale: readScale(
        json['textScale'],
        fallback.textScale,
        minTextScale,
        maxTextScale,
      ),
      headingScale: readScale(
        json['headingScale'],
        fallback.headingScale,
        minHeadingScale,
        maxHeadingScale,
      ),
      chatFontScale: readScale(
        json['chatFontScale'],
        fallback.chatFontScale,
        minChatFontScale,
        maxChatFontScale,
      ),
      cornerRadius: readScale(
        json['cornerRadius'],
        fallback.cornerRadius,
        minCornerRadius,
        maxCornerRadius,
      ),
      glassOpacity: readScale(
        json['glassOpacity'],
        fallback.glassOpacity,
        minGlassOpacity,
        maxGlassOpacity,
      ),
      glassBlur: readScale(
        json['glassBlur'],
        fallback.glassBlur,
        minGlassBlur,
        maxGlassBlur,
      ),
      avatarStyle: avatar,
    );
  }
}

/// Chat / RP styling hung on [ThemeData.extensions].
class AnimaUiTheme extends ThemeExtension<AnimaUiTheme> {
  const AnimaUiTheme({
    required this.chatFontScale,
    required this.chatBubbleRadius,
    required this.messageSpacing,
    required this.userBubbleColor,
    required this.aiBubbleColor,
    required this.userBubbleForeground,
    required this.aiBubbleForeground,
    required this.bubbleShadowColor,
    required this.actionColor,
    required this.dialogueEmphasis,
    required this.cornerRadius,
    required this.glassOpacity,
    required this.glassBlur,
    required this.visualStyle,
    required this.backgroundMode,
    required this.background,
    required this.backgroundAlt,
    required this.accentDeep,
  });

  /// Default Obsidian Gold glass values.
  static final standard = AnimaUiTheme.fromSettings(UiStyleSettings.defaults());

  factory AnimaUiTheme.fromSettings(UiStyleSettings settings) {
    final palette = settings.palette;
    final onUser = _onColor(palette.userBubble);
    final onAi = _onColor(palette.aiBubble);
    return AnimaUiTheme(
      chatFontScale: settings.chatFontScale,
      chatBubbleRadius: settings.cornerRadius.clamp(12, 24),
      messageSpacing: 6,
      userBubbleColor: palette.userBubble,
      aiBubbleColor: palette.aiBubble,
      userBubbleForeground: onUser,
      aiBubbleForeground: onAi,
      bubbleShadowColor: palette.brightness == Brightness.light
          ? Colors.black.withValues(alpha: 0.12)
          : Colors.black.withValues(alpha: 0.35),
      actionColor: palette.accent,
      dialogueEmphasis: onAi,
      cornerRadius: settings.cornerRadius,
      glassOpacity: settings.glassOpacity,
      glassBlur: settings.glassBlur,
      visualStyle: settings.visualStyle,
      backgroundMode: settings.backgroundMode,
      background: palette.background,
      backgroundAlt: palette.backgroundAlt,
      accentDeep: palette.accentDeep,
    );
  }

  final double chatFontScale;
  final double chatBubbleRadius;
  final double messageSpacing;
  final Color userBubbleColor;
  final Color aiBubbleColor;
  final Color userBubbleForeground;
  final Color aiBubbleForeground;
  final Color bubbleShadowColor;
  final Color actionColor;
  final Color dialogueEmphasis;
  final double cornerRadius;
  final double glassOpacity;
  final double glassBlur;
  final VisualStyle visualStyle;
  final BackgroundMode backgroundMode;
  final Color background;
  final Color backgroundAlt;
  final Color accentDeep;

  static AnimaUiTheme of(BuildContext context) {
    return Theme.of(context).extension<AnimaUiTheme>() ?? standard;
  }

  static Color _onColor(Color background) {
    final luminance = background.computeLuminance();
    return luminance > 0.55 ? const Color(0xFF1A1400) : const Color(0xFFF4F0E6);
  }

  @override
  AnimaUiTheme copyWith({
    double? chatFontScale,
    double? chatBubbleRadius,
    double? messageSpacing,
    Color? userBubbleColor,
    Color? aiBubbleColor,
    Color? userBubbleForeground,
    Color? aiBubbleForeground,
    Color? bubbleShadowColor,
    Color? actionColor,
    Color? dialogueEmphasis,
    double? cornerRadius,
    double? glassOpacity,
    double? glassBlur,
    VisualStyle? visualStyle,
    BackgroundMode? backgroundMode,
    Color? background,
    Color? backgroundAlt,
    Color? accentDeep,
  }) {
    return AnimaUiTheme(
      chatFontScale: chatFontScale ?? this.chatFontScale,
      chatBubbleRadius: chatBubbleRadius ?? this.chatBubbleRadius,
      messageSpacing: messageSpacing ?? this.messageSpacing,
      userBubbleColor: userBubbleColor ?? this.userBubbleColor,
      aiBubbleColor: aiBubbleColor ?? this.aiBubbleColor,
      userBubbleForeground: userBubbleForeground ?? this.userBubbleForeground,
      aiBubbleForeground: aiBubbleForeground ?? this.aiBubbleForeground,
      bubbleShadowColor: bubbleShadowColor ?? this.bubbleShadowColor,
      actionColor: actionColor ?? this.actionColor,
      dialogueEmphasis: dialogueEmphasis ?? this.dialogueEmphasis,
      cornerRadius: cornerRadius ?? this.cornerRadius,
      glassOpacity: glassOpacity ?? this.glassOpacity,
      glassBlur: glassBlur ?? this.glassBlur,
      visualStyle: visualStyle ?? this.visualStyle,
      backgroundMode: backgroundMode ?? this.backgroundMode,
      background: background ?? this.background,
      backgroundAlt: backgroundAlt ?? this.backgroundAlt,
      accentDeep: accentDeep ?? this.accentDeep,
    );
  }

  @override
  AnimaUiTheme lerp(ThemeExtension<AnimaUiTheme>? other, double t) {
    if (other is! AnimaUiTheme) return this;
    return AnimaUiTheme(
      chatFontScale:
          lerpDouble(chatFontScale, other.chatFontScale, t) ?? chatFontScale,
      chatBubbleRadius:
          lerpDouble(chatBubbleRadius, other.chatBubbleRadius, t) ??
          chatBubbleRadius,
      messageSpacing:
          lerpDouble(messageSpacing, other.messageSpacing, t) ?? messageSpacing,
      userBubbleColor:
          Color.lerp(userBubbleColor, other.userBubbleColor, t) ??
          userBubbleColor,
      aiBubbleColor:
          Color.lerp(aiBubbleColor, other.aiBubbleColor, t) ?? aiBubbleColor,
      userBubbleForeground:
          Color.lerp(userBubbleForeground, other.userBubbleForeground, t) ??
          userBubbleForeground,
      aiBubbleForeground:
          Color.lerp(aiBubbleForeground, other.aiBubbleForeground, t) ??
          aiBubbleForeground,
      bubbleShadowColor:
          Color.lerp(bubbleShadowColor, other.bubbleShadowColor, t) ??
          bubbleShadowColor,
      actionColor: Color.lerp(actionColor, other.actionColor, t) ?? actionColor,
      dialogueEmphasis:
          Color.lerp(dialogueEmphasis, other.dialogueEmphasis, t) ??
          dialogueEmphasis,
      cornerRadius:
          lerpDouble(cornerRadius, other.cornerRadius, t) ?? cornerRadius,
      glassOpacity:
          lerpDouble(glassOpacity, other.glassOpacity, t) ?? glassOpacity,
      glassBlur: lerpDouble(glassBlur, other.glassBlur, t) ?? glassBlur,
      visualStyle: t < 0.5 ? visualStyle : other.visualStyle,
      backgroundMode: t < 0.5 ? backgroundMode : other.backgroundMode,
      background: Color.lerp(background, other.background, t) ?? background,
      backgroundAlt:
          Color.lerp(backgroundAlt, other.backgroundAlt, t) ?? backgroundAlt,
      accentDeep: Color.lerp(accentDeep, other.accentDeep, t) ?? accentDeep,
    );
  }
}
