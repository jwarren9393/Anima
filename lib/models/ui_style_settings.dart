import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

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

  static const defaultShape = AvatarShape.roundedRect;
  static const defaultSizeTier = AvatarSizeTier.medium;
  static const defaultScale = 1.0;
  static const minScale = 0.75;
  static const maxScale = 1.5;

  final AvatarShape shape;
  final AvatarSizeTier sizeTier;
  final double scale;

  double get resolvedSize =>
      sizeTier.baseSize * scale.clamp(minScale, maxScale);

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
}

/// Full look-and-feel pack for Anima (presets + fine controls).
///
/// Saved as one JSON blob in secure storage. Theme builders read this and
/// produce Material [ThemeData] + chat extras.
class UiStyleSettings {
  const UiStyleSettings({
    this.preset = VisualPreset.parchment,
    this.primaryColor,
    this.accentColor,
    this.backgroundColor,
    this.surfaceColor,
    this.inkColor,
    this.userBubbleColor,
    this.aiBubbleColor,
    this.fontPairing = FontPairing.fantasy,
    this.fontScale = defaultFontScale,
    this.chatFontScale = defaultChatFontScale,
    this.backgroundStyle = BackgroundStyle.parchment,
    this.showTexture = false,
    this.textureIntensity = defaultTextureIntensity,
    this.showVignette = true,
    this.cornerRadius = defaultCornerRadius,
    this.chatBubbleRadius = defaultChatBubbleRadius,
    this.messageSpacing = defaultMessageSpacing,
    this.density = UiDensity.comfortable,
    this.motion = MotionPreference.normal,
    this.avatarStyle = const AvatarStyleSettings(),
  });

  static const defaultFontScale = 1.0;
  static const defaultChatFontScale = 1.0;
  static const defaultTextureIntensity = 0.55;
  static const defaultCornerRadius = 12.0;
  static const defaultChatBubbleRadius = 14.0;
  static const defaultMessageSpacing = 4.0;

  static const minFontScale = 0.85;
  static const maxFontScale = 1.35;
  static const minChatFontScale = 0.85;
  static const maxChatFontScale = 1.45;
  static const minTexture = 0.0;
  static const maxTexture = 1.0;
  static const minCorner = 6.0;
  static const maxCorner = 24.0;
  static const minBubbleRadius = 4.0;
  static const maxBubbleRadius = 28.0;
  static const minMessageSpacing = 0.0;
  static const maxMessageSpacing = 12.0;

  /// Named palette — used when individual colors are null.
  final VisualPreset preset;

  /// Optional color overrides (ARGB). Null = take from [preset].
  final Color? primaryColor;
  final Color? accentColor;
  final Color? backgroundColor;
  final Color? surfaceColor;
  final Color? inkColor;
  final Color? userBubbleColor;
  final Color? aiBubbleColor;

  final FontPairing fontPairing;
  final double fontScale;
  final double chatFontScale;

  final BackgroundStyle backgroundStyle;
  final bool showTexture;
  final double textureIntensity;
  final bool showVignette;

  /// App-wide control / card corner radius.
  final double cornerRadius;

  /// Chat message bubble corner radius.
  final double chatBubbleRadius;

  /// Extra vertical gap between chat rows.
  final double messageSpacing;

  final UiDensity density;
  final MotionPreference motion;

  final AvatarStyleSettings avatarStyle;

  bool get reduceMotion => motion == MotionPreference.off;

  /// Multiplier for animation durations (1.0 = normal).
  double get animationScale => switch (motion) {
        MotionPreference.off => 0.0,
        MotionPreference.slow => 1.55,
        MotionPreference.normal => 1.0,
        MotionPreference.lively => 0.65,
      };

  UiStyleSettings copyWith({
    VisualPreset? preset,
    Color? primaryColor,
    Color? accentColor,
    Color? backgroundColor,
    Color? surfaceColor,
    Color? inkColor,
    Color? userBubbleColor,
    Color? aiBubbleColor,
    bool clearPrimary = false,
    bool clearAccent = false,
    bool clearBackground = false,
    bool clearSurface = false,
    bool clearInk = false,
    bool clearUserBubble = false,
    bool clearAiBubble = false,
    FontPairing? fontPairing,
    double? fontScale,
    double? chatFontScale,
    BackgroundStyle? backgroundStyle,
    bool? showTexture,
    double? textureIntensity,
    bool? showVignette,
    double? cornerRadius,
    double? chatBubbleRadius,
    double? messageSpacing,
    UiDensity? density,
    MotionPreference? motion,
    AvatarStyleSettings? avatarStyle,
  }) {
    return UiStyleSettings(
      preset: preset ?? this.preset,
      primaryColor: clearPrimary ? null : (primaryColor ?? this.primaryColor),
      accentColor: clearAccent ? null : (accentColor ?? this.accentColor),
      backgroundColor:
          clearBackground ? null : (backgroundColor ?? this.backgroundColor),
      surfaceColor: clearSurface ? null : (surfaceColor ?? this.surfaceColor),
      inkColor: clearInk ? null : (inkColor ?? this.inkColor),
      userBubbleColor:
          clearUserBubble ? null : (userBubbleColor ?? this.userBubbleColor),
      aiBubbleColor:
          clearAiBubble ? null : (aiBubbleColor ?? this.aiBubbleColor),
      fontPairing: fontPairing ?? this.fontPairing,
      fontScale: fontScale ?? this.fontScale,
      chatFontScale: chatFontScale ?? this.chatFontScale,
      backgroundStyle: backgroundStyle ?? this.backgroundStyle,
      showTexture: showTexture ?? this.showTexture,
      textureIntensity: textureIntensity ?? this.textureIntensity,
      showVignette: showVignette ?? this.showVignette,
      cornerRadius: cornerRadius ?? this.cornerRadius,
      chatBubbleRadius: chatBubbleRadius ?? this.chatBubbleRadius,
      messageSpacing: messageSpacing ?? this.messageSpacing,
      density: density ?? this.density,
      motion: motion ?? this.motion,
      avatarStyle: avatarStyle ?? this.avatarStyle,
    );
  }

  /// Apply a preset and clear color overrides so the preset owns the palette.
  UiStyleSettings withPreset(VisualPreset next) {
    return copyWith(
      preset: next,
      clearPrimary: true,
      clearAccent: true,
      clearBackground: true,
      clearSurface: true,
      clearInk: true,
      clearUserBubble: true,
      clearAiBubble: true,
      backgroundStyle: next == VisualPreset.parchment
          ? BackgroundStyle.parchment
          : (next == VisualPreset.mist
              ? BackgroundStyle.softGradient
              : BackgroundStyle.solid),
      showTexture: false,
    );
  }

  Map<String, dynamic> toJson() => {
        'preset': preset.storageValue,
        if (primaryColor != null) 'primary': _colorToInt(primaryColor!),
        if (accentColor != null) 'accent': _colorToInt(accentColor!),
        if (backgroundColor != null) 'background': _colorToInt(backgroundColor!),
        if (surfaceColor != null) 'surface': _colorToInt(surfaceColor!),
        if (inkColor != null) 'ink': _colorToInt(inkColor!),
        if (userBubbleColor != null) 'userBubble': _colorToInt(userBubbleColor!),
        if (aiBubbleColor != null) 'aiBubble': _colorToInt(aiBubbleColor!),
        'fontPairing': fontPairing.storageValue,
        'fontScale': fontScale,
        'chatFontScale': chatFontScale,
        'backgroundStyle': backgroundStyle.storageValue,
        'showTexture': showTexture,
        'textureIntensity': textureIntensity,
        'showVignette': showVignette,
        'cornerRadius': cornerRadius,
        'chatBubbleRadius': chatBubbleRadius,
        'messageSpacing': messageSpacing,
        'density': density.storageValue,
        'motion': motion.storageValue,
        'avatarShape': avatarStyle.shape.storageValue,
        'avatarSize': avatarStyle.sizeTier.storageValue,
        'avatarScale': avatarStyle.scale,
      };

  factory UiStyleSettings.fromJson(Map<String, dynamic> json) {
    return UiStyleSettings(
      preset: VisualPreset.fromStorage('${json['preset'] ?? ''}'),
      primaryColor: _colorFrom(json['primary']),
      accentColor: _colorFrom(json['accent']),
      backgroundColor: _colorFrom(json['background']),
      surfaceColor: _colorFrom(json['surface']),
      inkColor: _colorFrom(json['ink']),
      userBubbleColor: _colorFrom(json['userBubble']),
      aiBubbleColor: _colorFrom(json['aiBubble']),
      fontPairing: FontPairing.fromStorage('${json['fontPairing'] ?? ''}'),
      fontScale: _clampDouble(
        json['fontScale'],
        defaultFontScale,
        minFontScale,
        maxFontScale,
      ),
      chatFontScale: _clampDouble(
        json['chatFontScale'],
        defaultChatFontScale,
        minChatFontScale,
        maxChatFontScale,
      ),
      backgroundStyle:
          BackgroundStyle.fromStorage('${json['backgroundStyle'] ?? ''}'),
      showTexture: json['showTexture'] == true,
      textureIntensity: _clampDouble(
        json['textureIntensity'],
        defaultTextureIntensity,
        minTexture,
        maxTexture,
      ),
      showVignette: json['showVignette'] != false,
      cornerRadius: _clampDouble(
        json['cornerRadius'],
        defaultCornerRadius,
        minCorner,
        maxCorner,
      ),
      chatBubbleRadius: _clampDouble(
        json['chatBubbleRadius'],
        defaultChatBubbleRadius,
        minBubbleRadius,
        maxBubbleRadius,
      ),
      messageSpacing: _clampDouble(
        json['messageSpacing'],
        defaultMessageSpacing,
        minMessageSpacing,
        maxMessageSpacing,
      ),
      density: UiDensity.fromStorage('${json['density'] ?? ''}'),
      motion: MotionPreference.fromStorage('${json['motion'] ?? ''}'),
      avatarStyle: AvatarStyleSettings(
        shape: AvatarShape.fromStorage('${json['avatarShape'] ?? ''}'),
        sizeTier: AvatarSizeTier.fromStorage('${json['avatarSize'] ?? ''}'),
        scale: _clampDouble(
          json['avatarScale'],
          AvatarStyleSettings.defaultScale,
          AvatarStyleSettings.minScale,
          AvatarStyleSettings.maxScale,
        ),
      ),
    );
  }

  static int _colorToInt(Color c) => c.toARGB32();

  static Color? _colorFrom(dynamic raw) {
    if (raw == null) return null;
    if (raw is int) return Color(raw);
    final parsed = int.tryParse('$raw');
    if (parsed == null) return null;
    return Color(parsed);
  }

  static double _clampDouble(
    dynamic raw,
    double fallback,
    double min,
    double max,
  ) {
    final value = raw is num
        ? raw.toDouble()
        : double.tryParse('$raw') ?? fallback;
    return value.clamp(min, max);
  }
}

/// Named look packs (colors + default background mood).
enum VisualPreset {
  parchment,
  teal,
  midnight,
  ember,
  mist;

  String get storageValue => name;

  String get label => switch (this) {
        VisualPreset.parchment => 'Parchment',
        VisualPreset.teal => 'Teal classic',
        VisualPreset.midnight => 'Midnight ink',
        VisualPreset.ember => 'Ember hearth',
        VisualPreset.mist => 'Mist & steel',
      };

  String get blurb => switch (this) {
        VisualPreset.parchment => 'Woodland journal — aged paper & pine',
        VisualPreset.teal => 'Original Anima calm teal',
        VisualPreset.midnight => 'Deep night, silver moonlight',
        VisualPreset.ember => 'Warm firelight & leather',
        VisualPreset.mist => 'Cool fog, slate & steel',
      };

  static VisualPreset fromStorage(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'teal':
        return VisualPreset.teal;
      case 'midnight':
        return VisualPreset.midnight;
      case 'ember':
        return VisualPreset.ember;
      case 'mist':
        return VisualPreset.mist;
      default:
        return VisualPreset.parchment;
    }
  }
}

enum FontPairing {
  fantasy,
  classicSerif,
  cleanSans,
  softRounded;

  String get storageValue => name;

  String get label => switch (this) {
        FontPairing.fantasy => 'Fantasy (Cinzel)',
        FontPairing.classicSerif => 'Classic serif',
        FontPairing.cleanSans => 'Clean sans',
        FontPairing.softRounded => 'Soft rounded',
      };

  String get blurb => switch (this) {
        FontPairing.fantasy => 'Carved titles + Literata body',
        FontPairing.classicSerif => 'Bookish Libre Baskerville',
        FontPairing.cleanSans => 'Modern Outfit + Source Sans',
        FontPairing.softRounded => 'Friendly Nunito',
      };

  static FontPairing fromStorage(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'classicserif':
      case 'classic_serif':
        return FontPairing.classicSerif;
      case 'cleansans':
      case 'clean_sans':
        return FontPairing.cleanSans;
      case 'softrounded':
      case 'soft_rounded':
        return FontPairing.softRounded;
      default:
        return FontPairing.fantasy;
    }
  }
}

enum BackgroundStyle {
  solid,
  softGradient,
  parchment;

  String get storageValue => name;

  String get label => switch (this) {
        BackgroundStyle.solid => 'Solid',
        BackgroundStyle.softGradient => 'Soft gradient',
        BackgroundStyle.parchment => 'Parchment wash',
      };

  static BackgroundStyle fromStorage(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'solid':
        return BackgroundStyle.solid;
      case 'softgradient':
      case 'soft_gradient':
      case 'gradient':
        return BackgroundStyle.softGradient;
      default:
        return BackgroundStyle.parchment;
    }
  }
}

enum UiDensity {
  comfortable,
  cozy,
  compact;

  String get storageValue => name;

  String get label => switch (this) {
        UiDensity.comfortable => 'Comfortable',
        UiDensity.cozy => 'Cozy',
        UiDensity.compact => 'Compact',
      };

  double get listTileFactor => switch (this) {
        UiDensity.comfortable => 1.0,
        UiDensity.cozy => 0.92,
        UiDensity.compact => 0.82,
      };

  static UiDensity fromStorage(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'cozy':
        return UiDensity.cozy;
      case 'compact':
        return UiDensity.compact;
      default:
        return UiDensity.comfortable;
    }
  }
}

enum MotionPreference {
  off,
  slow,
  normal,
  lively;

  String get storageValue => name;

  String get label => switch (this) {
        MotionPreference.off => 'Off',
        MotionPreference.slow => 'Slow',
        MotionPreference.normal => 'Normal',
        MotionPreference.lively => 'Lively',
      };

  static MotionPreference fromStorage(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'off':
      case 'reduce':
      case 'none':
        return MotionPreference.off;
      case 'slow':
        return MotionPreference.slow;
      case 'lively':
      case 'fast':
        return MotionPreference.lively;
      default:
        return MotionPreference.normal;
    }
  }
}

/// Chat / animation extras hung on [ThemeData.extensions].
class AnimaUiTheme extends ThemeExtension<AnimaUiTheme> {
  const AnimaUiTheme({
    required this.chatFontScale,
    required this.chatBubbleRadius,
    required this.messageSpacing,
    required this.animationScale,
    required this.reduceMotion,
    required this.showTexture,
    required this.textureIntensity,
    required this.showVignette,
    required this.backgroundStyle,
    this.userBubbleColor,
    this.aiBubbleColor,
    this.backdropBackground,
  });

  final double chatFontScale;
  final double chatBubbleRadius;
  final double messageSpacing;
  final double animationScale;
  final bool reduceMotion;
  final bool showTexture;
  final double textureIntensity;
  final bool showVignette;
  final BackgroundStyle backgroundStyle;
  final Color? userBubbleColor;
  final Color? aiBubbleColor;
  final Color? backdropBackground;

  static AnimaUiTheme of(BuildContext context) {
    return Theme.of(context).extension<AnimaUiTheme>() ??
        AnimaUiTheme.fromSettings(const UiStyleSettings());
  }

  factory AnimaUiTheme.fromSettings(UiStyleSettings style) {
    return AnimaUiTheme(
      chatFontScale: style.chatFontScale,
      chatBubbleRadius: style.chatBubbleRadius,
      messageSpacing: style.messageSpacing,
      animationScale: style.animationScale,
      reduceMotion: style.reduceMotion,
      showTexture: style.showTexture,
      textureIntensity: style.textureIntensity,
      showVignette: style.showVignette,
      backgroundStyle: style.backgroundStyle,
      userBubbleColor: style.userBubbleColor,
      aiBubbleColor: style.aiBubbleColor,
      backdropBackground: style.backgroundColor,
    );
  }

  @override
  AnimaUiTheme copyWith({
    double? chatFontScale,
    double? chatBubbleRadius,
    double? messageSpacing,
    double? animationScale,
    bool? reduceMotion,
    bool? showTexture,
    double? textureIntensity,
    bool? showVignette,
    BackgroundStyle? backgroundStyle,
    Color? userBubbleColor,
    Color? aiBubbleColor,
    Color? backdropBackground,
  }) {
    return AnimaUiTheme(
      chatFontScale: chatFontScale ?? this.chatFontScale,
      chatBubbleRadius: chatBubbleRadius ?? this.chatBubbleRadius,
      messageSpacing: messageSpacing ?? this.messageSpacing,
      animationScale: animationScale ?? this.animationScale,
      reduceMotion: reduceMotion ?? this.reduceMotion,
      showTexture: showTexture ?? this.showTexture,
      textureIntensity: textureIntensity ?? this.textureIntensity,
      showVignette: showVignette ?? this.showVignette,
      backgroundStyle: backgroundStyle ?? this.backgroundStyle,
      userBubbleColor: userBubbleColor ?? this.userBubbleColor,
      aiBubbleColor: aiBubbleColor ?? this.aiBubbleColor,
      backdropBackground: backdropBackground ?? this.backdropBackground,
    );
  }

  @override
  AnimaUiTheme lerp(ThemeExtension<AnimaUiTheme>? other, double t) {
    if (other is! AnimaUiTheme) return this;
    return AnimaUiTheme(
      chatFontScale: lerpDouble(chatFontScale, other.chatFontScale, t) ??
          chatFontScale,
      chatBubbleRadius:
          lerpDouble(chatBubbleRadius, other.chatBubbleRadius, t) ??
              chatBubbleRadius,
      messageSpacing:
          lerpDouble(messageSpacing, other.messageSpacing, t) ?? messageSpacing,
      animationScale:
          lerpDouble(animationScale, other.animationScale, t) ?? animationScale,
      reduceMotion: t < 0.5 ? reduceMotion : other.reduceMotion,
      showTexture: t < 0.5 ? showTexture : other.showTexture,
      textureIntensity:
          lerpDouble(textureIntensity, other.textureIntensity, t) ??
              textureIntensity,
      showVignette: t < 0.5 ? showVignette : other.showVignette,
      backgroundStyle: t < 0.5 ? backgroundStyle : other.backgroundStyle,
      userBubbleColor: Color.lerp(userBubbleColor, other.userBubbleColor, t),
      aiBubbleColor: Color.lerp(aiBubbleColor, other.aiBubbleColor, t),
      backdropBackground:
          Color.lerp(backdropBackground, other.backdropBackground, t),
    );
  }
}
