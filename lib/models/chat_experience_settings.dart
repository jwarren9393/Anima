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
    this.portraitBackground = false,
    this.portraitBlur = defaultPortraitBlur,
    this.showSpeakerHeader = false,
  });

  static const defaultPortraitBlur = 14.0;
  static const minPortraitBlur = 0.0;
  static const maxPortraitBlur = 30.0;

  final ChatLayoutMode layoutMode;
  final bool portraitBackground;
  final double portraitBlur;
  final bool showSpeakerHeader;

  bool get isStorybook => layoutMode == ChatLayoutMode.storybook;

  /// Curated Moonlit-inspired chat layout defaults.
  static const storybook = ChatExperienceSettings(
    layoutMode: ChatLayoutMode.storybook,
    portraitBackground: true,
    portraitBlur: 16,
    showSpeakerHeader: true,
  );

  ChatExperienceSettings copyWith({
    ChatLayoutMode? layoutMode,
    bool? portraitBackground,
    double? portraitBlur,
    bool? showSpeakerHeader,
  }) {
    return ChatExperienceSettings(
      layoutMode: layoutMode ?? this.layoutMode,
      portraitBackground: portraitBackground ?? this.portraitBackground,
      portraitBlur: portraitBlur ?? this.portraitBlur,
      showSpeakerHeader: showSpeakerHeader ?? this.showSpeakerHeader,
    );
  }

  Map<String, dynamic> toJson() => {
        'chatLayoutMode': layoutMode.toJson(),
        if (portraitBackground) 'chatPortraitBackground': true,
        if (portraitBlur != defaultPortraitBlur) 'chatPortraitBlur': portraitBlur,
        if (showSpeakerHeader) 'chatShowSpeakerHeader': true,
      };

  factory ChatExperienceSettings.fromJson(Map<String, dynamic> json) {
    final mode = ChatLayoutMode.fromJson(json['chatLayoutMode']);
    final storyDefaults = mode == ChatLayoutMode.storybook;

    double readBlur() {
      final raw = json['chatPortraitBlur'];
      final fallback = storyDefaults
          ? ChatExperienceSettings.storybook.portraitBlur
          : defaultPortraitBlur;
      final parsed = raw is num
          ? raw.toDouble()
          : double.tryParse('$raw') ?? fallback;
      return parsed.clamp(minPortraitBlur, maxPortraitBlur);
    }

    return ChatExperienceSettings(
      layoutMode: mode,
      portraitBackground: json.containsKey('chatPortraitBackground')
          ? json['chatPortraitBackground'] == true
          : storyDefaults,
      portraitBlur: readBlur(),
      showSpeakerHeader: json.containsKey('chatShowSpeakerHeader')
          ? json['chatShowSpeakerHeader'] == true
          : storyDefaults,
    );
  }
}
