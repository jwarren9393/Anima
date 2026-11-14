import 'package:flutter/material.dart';

/// How the chat screen lays out messages and backgrounds.
enum ChatLayoutMode {
  classic,
  storybook;

  String get label => switch (this) {
        ChatLayoutMode.classic => 'Classic',
        ChatLayoutMode.storybook => 'Storybook',
      };

  static ChatLayoutMode fromJson(dynamic raw) {
    return switch ('$raw'.trim().toLowerCase()) {
      'storybook' => ChatLayoutMode.storybook,
      _ => ChatLayoutMode.classic,
    };
  }

  String toJson() => name;
}

/// Chat-screen look options (Theme Studio → Chat experience).
class ChatExperienceSettings {
  const ChatExperienceSettings({
    this.layoutMode = ChatLayoutMode.classic,
    this.backgroundEnabled = false,
    this.backgroundImageFileName,
    this.backgroundBlur = defaultBackgroundBlur,
    this.showSpeakerHeader = false,
    this.showSideHeroPortrait = false,
    this.bubbleOpacity = defaultBubbleOpacity,
  });

  static const defaultBackgroundBlur = 14.0;
  static const minBackgroundBlur = 0.0;
  static const maxBackgroundBlur = 30.0;

  static const defaultBubbleOpacity = 1.0;
  static const minBubbleOpacity = 0.12;
  static const maxBubbleOpacity = 1.0;

  final ChatLayoutMode layoutMode;
  final bool backgroundEnabled;
  /// Stored file name under [ChatBackgroundService] (user-picked image).
  final String? backgroundImageFileName;
  final double backgroundBlur;
  final bool showSpeakerHeader;
  final bool showSideHeroPortrait;
  /// Multiplier on palette bubble alpha (0.12–1.0).
  final double bubbleOpacity;

  bool get isStorybook => layoutMode == ChatLayoutMode.storybook;

  bool get hasBackgroundImage =>
      backgroundImageFileName != null &&
      backgroundImageFileName!.trim().isNotEmpty;

  /// Applies [bubbleOpacity] on top of a palette bubble color.
  Color bubbleFill(Color paletteColor) {
    return paletteColor.withValues(alpha: paletteColor.a * bubbleOpacity);
  }

  /// Curated Moonlit-inspired chat layout defaults.
  static const storybook = ChatExperienceSettings(
    layoutMode: ChatLayoutMode.storybook,
    backgroundEnabled: true,
    backgroundBlur: 16,
    showSpeakerHeader: true,
    showSideHeroPortrait: true,
    bubbleOpacity: 0.48,
  );

  ChatExperienceSettings copyWith({
    ChatLayoutMode? layoutMode,
    bool? backgroundEnabled,
    String? backgroundImageFileName,
    bool clearBackgroundImage = false,
    double? backgroundBlur,
    bool? showSpeakerHeader,
    bool? showSideHeroPortrait,
    double? bubbleOpacity,
  }) {
    return ChatExperienceSettings(
      layoutMode: layoutMode ?? this.layoutMode,
      backgroundEnabled: backgroundEnabled ?? this.backgroundEnabled,
      backgroundImageFileName: clearBackgroundImage
          ? null
          : (backgroundImageFileName ?? this.backgroundImageFileName),
      backgroundBlur: backgroundBlur ?? this.backgroundBlur,
      showSpeakerHeader: showSpeakerHeader ?? this.showSpeakerHeader,
      showSideHeroPortrait: showSideHeroPortrait ?? this.showSideHeroPortrait,
      bubbleOpacity: bubbleOpacity ?? this.bubbleOpacity,
    );
  }

  Map<String, dynamic> toJson() => {
        'chatLayoutMode': layoutMode.toJson(),
        if (backgroundEnabled) 'chatBackgroundEnabled': true,
        if (hasBackgroundImage)
          'chatBackgroundImage': backgroundImageFileName,
        if (backgroundBlur != defaultBackgroundBlur)
          'chatBackgroundBlur': backgroundBlur,
        if (showSpeakerHeader) 'chatShowSpeakerHeader': true,
        if (showSideHeroPortrait) 'chatShowSideHeroPortrait': true,
        if (bubbleOpacity != defaultBubbleOpacity)
          'chatBubbleOpacity': bubbleOpacity,
      };

  factory ChatExperienceSettings.fromJson(Map<String, dynamic> json) {
    final mode = ChatLayoutMode.fromJson(json['chatLayoutMode']);
    final storyDefaults = mode == ChatLayoutMode.storybook;

    double readBlur() {
      final raw = json['chatBackgroundBlur'] ?? json['chatPortraitBlur'];
      final fallback = storyDefaults
          ? ChatExperienceSettings.storybook.backgroundBlur
          : defaultBackgroundBlur;
      final parsed = raw is num
          ? raw.toDouble()
          : double.tryParse('$raw') ?? fallback;
      return parsed.clamp(minBackgroundBlur, maxBackgroundBlur);
    }

    double readBubbleOpacity() {
      final raw = json['chatBubbleOpacity'];
      final fallback = storyDefaults
          ? ChatExperienceSettings.storybook.bubbleOpacity
          : defaultBubbleOpacity;
      final parsed = raw is num
          ? raw.toDouble()
          : double.tryParse('$raw') ?? fallback;
      return parsed.clamp(minBubbleOpacity, maxBubbleOpacity);
    }

    final imageRaw = json['chatBackgroundImage']?.toString().trim();
    final imageName =
        imageRaw != null && imageRaw.isNotEmpty ? imageRaw : null;

    bool readBackgroundEnabled() {
      if (json.containsKey('chatBackgroundEnabled')) {
        return json['chatBackgroundEnabled'] == true;
      }
      // Legacy key from build 29.
      if (json.containsKey('chatPortraitBackground')) {
        return json['chatPortraitBackground'] == true;
      }
      return storyDefaults;
    }

    return ChatExperienceSettings(
      layoutMode: mode,
      backgroundEnabled: readBackgroundEnabled(),
      backgroundImageFileName: imageName,
      backgroundBlur: readBlur(),
      showSpeakerHeader: json.containsKey('chatShowSpeakerHeader')
          ? json['chatShowSpeakerHeader'] == true
          : storyDefaults,
      showSideHeroPortrait: json.containsKey('chatShowSideHeroPortrait')
          ? json['chatShowSideHeroPortrait'] == true
          : storyDefaults,
      bubbleOpacity: readBubbleOpacity(),
    );
  }
}
