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

/// Saved appearance prefs — currently chat avatars only (theme is fixed).
class UiStyleSettings {
  const UiStyleSettings({
    this.avatarStyle = const AvatarStyleSettings(),
  });

  final AvatarStyleSettings avatarStyle;

  UiStyleSettings copyWith({AvatarStyleSettings? avatarStyle}) {
    return UiStyleSettings(
      avatarStyle: avatarStyle ?? this.avatarStyle,
    );
  }

  Map<String, dynamic> toJson() => avatarStyle.toJson();

  factory UiStyleSettings.fromJson(Map<String, dynamic> json) {
    return UiStyleSettings(
      avatarStyle: AvatarStyleSettings.fromJson(json),
    );
  }
}

/// Fixed glass-theme extras for chat bubbles (hung on [ThemeData.extensions]).
class AnimaUiTheme extends ThemeExtension<AnimaUiTheme> {
  const AnimaUiTheme({
    required this.chatFontScale,
    required this.chatBubbleRadius,
    required this.messageSpacing,
    required this.userBubbleColor,
    required this.aiBubbleColor,
  });

  /// Default Obsidian & Gold glass values.
  static const standard = AnimaUiTheme(
    chatFontScale: 1.0,
    chatBubbleRadius: 18,
    messageSpacing: 6,
    userBubbleColor: Color(0xE6B8860B),
    aiBubbleColor: Color(0xB31A1A1F),
  );

  final double chatFontScale;
  final double chatBubbleRadius;
  final double messageSpacing;
  final Color userBubbleColor;
  final Color aiBubbleColor;

  static AnimaUiTheme of(BuildContext context) {
    return Theme.of(context).extension<AnimaUiTheme>() ?? standard;
  }

  @override
  AnimaUiTheme copyWith({
    double? chatFontScale,
    double? chatBubbleRadius,
    double? messageSpacing,
    Color? userBubbleColor,
    Color? aiBubbleColor,
  }) {
    return AnimaUiTheme(
      chatFontScale: chatFontScale ?? this.chatFontScale,
      chatBubbleRadius: chatBubbleRadius ?? this.chatBubbleRadius,
      messageSpacing: messageSpacing ?? this.messageSpacing,
      userBubbleColor: userBubbleColor ?? this.userBubbleColor,
      aiBubbleColor: aiBubbleColor ?? this.aiBubbleColor,
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
      userBubbleColor: Color.lerp(userBubbleColor, other.userBubbleColor, t) ??
          userBubbleColor,
      aiBubbleColor:
          Color.lerp(aiBubbleColor, other.aiBubbleColor, t) ?? aiBubbleColor,
    );
  }
}
