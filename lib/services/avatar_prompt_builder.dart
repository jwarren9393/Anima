/// Builds a text-to-image prompt for character or persona avatars.
///
/// NanoGPT image models reject prompts over ~1,200 characters, so prompts
/// focus on portrait-relevant visuals instead of dumping the whole card.
class AvatarPromptBuilder {
  const AvatarPromptBuilder();

  /// Safe ceiling under NanoGPT's ~1,200 character image prompt limit.
  static const int maxPromptLength = 1150;

  /// Default editable prompt filled into the Generate avatar sheet (characters).
  String buildPrompt({
    required String name,
    String description = '',
    String personality = '',
    String scenario = '',
    List<String> tags = const [],
  }) {
    final framing = _characterFraming(name);
    final tagLine = _formatVisualTags(tags);
    final overhead = framing.length +
        (tagLine.isEmpty ? 0 : tagLine.length + 1) +
        1; // newline between blocks
    final visualBudget = (maxPromptLength - overhead).clamp(180, 720);

    final visual = _extractVisualDescription(
      description,
      personality: personality,
      maxChars: visualBudget,
    );

    final parts = <String>[framing];
    if (visual.isNotEmpty) {
      parts.add(visual);
    }
    if (tagLine.isNotEmpty) {
      parts.add(tagLine);
    }
    return parts.join('\n');
  }

  /// Default editable prompt for a user persona ({{user}}) avatar.
  String buildPersonaPrompt({
    required String name,
    String description = '',
    String appearance = '',
    String personality = '',
  }) {
    final framing = _personaFraming(name);
    final overhead = framing.length + 1;
    final visualBudget = (maxPromptLength - overhead).clamp(180, 720);

    final look = appearance.trim();
    final visual = look.isNotEmpty
        ? _clip(_normalize(look), visualBudget)
        : _extractVisualDescription(
            description,
            personality: personality,
            maxChars: visualBudget,
          );

    final parts = <String>[framing];
    if (visual.isNotEmpty) {
      parts.add(visual);
    }
    return parts.join('\n');
  }

  String _characterFraming(String name) {
    final label =
        name.trim().isEmpty ? 'a character' : name.trim();
    return 'Portrait avatar of $label for a private roleplay chat app.\n'
        'Single character, head-and-shoulders or upper body, clear face, '
        'centered composition, high detail, no text, no watermark, '
        'no UI chrome.';
  }

  String _personaFraming(String name) {
    final label = name.trim().isEmpty ? 'a person' : name.trim();
    return 'Portrait avatar of $label as the player / user persona for a '
        'private roleplay chat app.\n'
        'Single person, head-and-shoulders or upper body, clear face, '
        'centered composition, high detail, no text, no watermark, '
        'no UI chrome.';
  }

  /// Pulls appearance-focused lines from card text; skips lore, plot, and RP.
  String _extractVisualDescription(
    String description, {
    String personality = '',
    required int maxChars,
  }) {
    final normalized = _normalize(description);
    if (normalized.isEmpty) {
      return _clipVisualMood(personality, maxChars);
    }

    final segments = _splitSegments(normalized);
    final visualSegments = <String>[];

    for (final segment in segments) {
      if (_looksVisual(segment)) {
        visualSegments.add(segment);
      }
    }

    var visual = visualSegments.join(' ');
    if (visual.isEmpty) {
      // ST cards often lead with looks even when keywords are sparse.
      visual = _firstParagraph(normalized);
    }

    visual = _clip(visual, maxChars);

    final mood = _clipVisualMood(personality, 72);
    if (mood.isEmpty || visual.contains(mood)) {
      return visual;
    }

    final combined = '$visual. Expression / mood: $mood';
    if (combined.length <= maxChars) {
      return combined;
    }
    return visual;
  }

  String _clipVisualMood(String personality, int maxChars) {
    final normalized = _normalize(personality);
    if (normalized.isEmpty || maxChars <= 0) return '';

    for (final segment in _splitSegments(normalized)) {
      if (!_looksVisual(segment) && !_looksMood(segment)) continue;
      final clipped = _clip(segment, maxChars);
      if (clipped.isNotEmpty) return clipped;
    }
    return '';
  }

  String _formatVisualTags(List<String> tags) {
    final picked = tags
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty && t.length <= 24)
        .where((t) => !_nonVisualTags.contains(t.toLowerCase()))
        .take(4)
        .toList();
    if (picked.isEmpty) return '';
    return 'Style tags: ${picked.join(', ')}';
  }

  static final Set<String> _nonVisualTags = {
    'nsfw',
    'sfw',
    'oc',
    'roleplay',
    'rp',
    'chatbot',
    'assistant',
    'english',
  };

  static final RegExp _appearancePattern = RegExp(
    r'\b('
    r'age|years?\s+old|'
    r'hair|bald|beard|mustache|stubble|'
    r'eyes?|eyebrows?|lashes|'
    r'skin|complexion|freckles?|scar|scars|tattoo|tattoos|'
    r'face|jaw|cheek|cheeks|nose|lips?|mouth|smile|grin|frown|'
    r'tall|short|slim|lean|muscular|athletic|petite|curvy|stocky|build|'
    r'wears?|wearing|dressed|clothes|clothing|outfit|armor|armour|'
    r'robe|cloak|cape|gown|dress|suit|jacket|coat|shirt|hood|veil|'
    r'hat|helmet|mask|gloves|boots|jewelry|jewellery|earrings?|necklace|'
    r'blonde|brunette|redhead|auburn|ginger|'
    r'pale|fair|tan|dark-skinned|olive|'
    r'human|elf|elven|dwarf|orc|demon|angel|vampire|werewolf|'
    r'horns?|wings?|tail|furry|scales|pointed\s+ears|'
    r'handsome|beautiful|pretty|stern|gentle|fierce|soft|cold'
    r')\b',
    caseSensitive: false,
  );

  static final RegExp _moodPattern = RegExp(
    r'\b('
    r'stern|gentle|warm|cold|fierce|soft|shy|confident|'
    r'serious|playful|mischievous|stoic|brooding|cheerful|'
    r'smiling|grinning|frowning|expression'
    r')\b',
    caseSensitive: false,
  );

  static final RegExp _nonVisualPattern = RegExp(
    r'\b('
    r'relationship|backstory|history|childhood|family|parents?|'
    r'brother|sister|friend|enemy|allied|alliance|'
    r'personality|speaking\s+style|goals?|motivation|secret|'
    r'plot|quest|mission|negotiat|manipulat|despise|hate|love'
    r')\b',
    caseSensitive: false,
  );

  bool _looksVisual(String segment) {
    if (segment.length < 8) return false;
    if (_nonVisualPattern.hasMatch(segment) && !_appearancePattern.hasMatch(segment)) {
      return false;
    }
    return _appearancePattern.hasMatch(segment);
  }

  bool _looksMood(String segment) => _moodPattern.hasMatch(segment);

  List<String> _splitSegments(String text) {
    return text
        .split(RegExp(r'[\n\r]+|(?<=[.!?])\s+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  String _firstParagraph(String text) {
    final paragraph = text.split(RegExp(r'\n\s*\n')).first.trim();
    return _clip(paragraph, 420);
  }

  String _normalize(String text) {
    return text
        .replaceAll(RegExp(r'\{\{user\}\}|\{\{char\}\}', caseSensitive: false), '')
        .replaceAll(RegExp(r'\*+'), '')
        .replaceAll(RegExp(r'"+'), '"')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _clip(String text, int max) {
    if (max <= 0) return '';
    final cleaned = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (cleaned.length <= max) return cleaned;
    return '${cleaned.substring(0, max - 1).trimRight()}…';
  }
}
