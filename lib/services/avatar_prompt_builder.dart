/// Builds a text-to-image prompt for character or persona avatars.
class AvatarPromptBuilder {
  const AvatarPromptBuilder();

  /// Default editable prompt filled into the Generate avatar sheet (characters).
  String buildPrompt({
    required String name,
    String description = '',
    String personality = '',
    String scenario = '',
    List<String> tags = const [],
  }) {
    final parts = <String>[
      'Portrait avatar of ${name.trim().isEmpty ? 'a character' : name.trim()} '
          'for a private roleplay chat app.',
      'Single character, head-and-shoulders or upper body, clear face, '
          'centered composition, high detail, no text, no watermark, '
          'no UI chrome.',
    ];

    final appearance = description.trim();
    if (appearance.isNotEmpty) {
      parts.add('Appearance and background: ${_clip(appearance, 500)}');
    }
    final traits = personality.trim();
    if (traits.isNotEmpty) {
      parts.add('Personality / vibe: ${_clip(traits, 240)}');
    }
    final setting = scenario.trim();
    if (setting.isNotEmpty) {
      parts.add('Scene hints: ${_clip(setting, 180)}');
    }
    final tagText = tags
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .take(8)
        .join(', ');
    if (tagText.isNotEmpty) {
      parts.add('Tags: $tagText');
    }

    return parts.join('\n');
  }

  /// Default editable prompt for a user persona ({{user}}) avatar.
  String buildPersonaPrompt({
    required String name,
    String description = '',
  }) {
    final parts = <String>[
      'Portrait avatar of '
          '${name.trim().isEmpty ? 'a person' : name.trim()} '
          'as the player / user persona for a private roleplay chat app.',
      'Single person, head-and-shoulders or upper body, clear face, '
          'centered composition, high detail, no text, no watermark, '
          'no UI chrome.',
    ];

    final about = description.trim();
    if (about.isNotEmpty) {
      parts.add('About this persona: ${_clip(about, 500)}');
    }

    return parts.join('\n');
  }

  String _clip(String text, int max) {
    final cleaned = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (cleaned.length <= max) return cleaned;
    return '${cleaned.substring(0, max - 1).trimRight()}…';
  }
}
