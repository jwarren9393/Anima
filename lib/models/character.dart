import 'lorebook.dart';

/// Anima character stored on device, mapped to SillyTavern Character Card fields.
///
/// Card specs supported for import/export:
/// - V1 flat JSON (`name`, `description`, …)
/// - V2 `chara_card_v2` / `data` block
/// - V3 `chara_card_v3` / `data` block (extra fields preserved in [extensions]/[characterBook])
class Character {
  const Character({
    required this.id,
    required this.name,
    this.description = '',
    this.personality = '',
    this.scenario = '',
    this.firstMes = '',
    this.mesExample = '',
    this.systemPrompt = '',
    this.postHistoryInstructions = '',
    this.alternateGreetings = const [],
    this.creatorNotes = '',
    this.creator = '',
    this.characterVersion = '',
    this.tags = const [],
    this.characterBook,
    this.extensions = const {},
    this.avatarFileName,
  });

  /// Anima-only stable id (not part of the ST card spec).
  final String id;

  final String name;
  final String description;
  final String personality;
  final String scenario;

  /// SillyTavern `first_mes` — opening greeting.
  final String firstMes;

  /// SillyTavern `mes_example` — example dialogue blocks.
  final String mesExample;

  /// Optional card `system_prompt` (overrides the default system wording when set).
  final String systemPrompt;

  /// SillyTavern `post_history_instructions` (author’s note / after-history nudge).
  final String postHistoryInstructions;

  /// Extra opening messages (swipes on the first message).
  final List<String> alternateGreetings;

  final String creatorNotes;
  final String creator;
  final String characterVersion;
  final List<String> tags;

  /// Embedded lorebook from the card (World Info); preserved on export.
  final Map<String, dynamic>? characterBook;

  /// Spec `extensions` object — unknown keys must be preserved.
  final Map<String, dynamic> extensions;

  /// Local avatar file name under app `avatars/` (Anima-only; not an ST field).
  final String? avatarFileName;

  /// Typed view of [characterBook], or null if missing/empty.
  Lorebook? get lorebook {
    final raw = characterBook;
    if (raw == null || raw.isEmpty) return null;
    try {
      final book = Lorebook.fromJson(raw);
      return book;
    } catch (_) {
      return null;
    }
  }

  /// How many lore entries are enabled (for UI badges).
  int get enabledLoreEntryCount {
    final book = lorebook;
    if (book == null) return 0;
    return book.entries.where((e) => e.enabled).length;
  }

  /// All greetings: primary first message + alternates (empty strings dropped).
  List<String> get allGreetings {
    final list = <String>[
      if (firstMes.trim().isNotEmpty) firstMes.trim(),
      ...alternateGreetings.map((g) => g.trim()).where((g) => g.isNotEmpty),
    ];
    return list;
  }

  Character copyWith({
    String? id,
    String? name,
    String? description,
    String? personality,
    String? scenario,
    String? firstMes,
    String? mesExample,
    String? systemPrompt,
    String? postHistoryInstructions,
    List<String>? alternateGreetings,
    String? creatorNotes,
    String? creator,
    String? characterVersion,
    List<String>? tags,
    Map<String, dynamic>? characterBook,
    Map<String, dynamic>? extensions,
    String? avatarFileName,
    bool clearCharacterBook = false,
    bool clearAvatar = false,
  }) {
    return Character(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      personality: personality ?? this.personality,
      scenario: scenario ?? this.scenario,
      firstMes: firstMes ?? this.firstMes,
      mesExample: mesExample ?? this.mesExample,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      postHistoryInstructions:
          postHistoryInstructions ?? this.postHistoryInstructions,
      alternateGreetings: alternateGreetings ?? this.alternateGreetings,
      creatorNotes: creatorNotes ?? this.creatorNotes,
      creator: creator ?? this.creator,
      characterVersion: characterVersion ?? this.characterVersion,
      tags: tags ?? this.tags,
      characterBook:
          clearCharacterBook ? null : (characterBook ?? this.characterBook),
      extensions: extensions ?? this.extensions,
      avatarFileName:
          clearAvatar ? null : (avatarFileName ?? this.avatarFileName),
    );
  }

  /// Anima on-device JSON (includes [id] plus card fields).
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'personality': personality,
        'scenario': scenario,
        'first_mes': firstMes,
        'mes_example': mesExample,
        'system_prompt': systemPrompt,
        'post_history_instructions': postHistoryInstructions,
        'alternate_greetings': alternateGreetings,
        'creator_notes': creatorNotes,
        'creator': creator,
        'character_version': characterVersion,
        'tags': tags,
        if (characterBook != null) 'character_book': characterBook,
        'extensions': extensions,
        if (avatarFileName != null && avatarFileName!.isNotEmpty)
          'avatar_file': avatarFileName,
      };

  factory Character.fromJson(Map<String, dynamic> json) {
    // Migrate older Anima saves (systemPrompt / firstMessage).
    final legacyPrompt = (json['systemPrompt'] as String? ?? '').trim();
    final legacyFirst = (json['firstMessage'] as String? ?? '').trim();

    var description = _str(json['description']);
    var personality = _str(json['personality']);
    if (description.isEmpty && personality.isEmpty && legacyPrompt.isNotEmpty) {
      description = legacyPrompt;
    }

    var firstMes = _str(json['first_mes']);
    if (firstMes.isEmpty && legacyFirst.isNotEmpty) {
      firstMes = legacyFirst;
    }

    final alternates = <String>[];
    final rawAlts = json['alternate_greetings'];
    if (rawAlts is List) {
      for (final item in rawAlts) {
        final text = '$item'.trim();
        if (text.isNotEmpty) alternates.add(text);
      }
    }

    final tags = <String>[];
    final rawTags = json['tags'];
    if (rawTags is List) {
      for (final item in rawTags) {
        final text = '$item'.trim();
        if (text.isNotEmpty) tags.add(text);
      }
    }

    Map<String, dynamic>? book;
    final rawBook = json['character_book'];
    if (rawBook is Map) {
      book = Map<String, dynamic>.from(rawBook);
    }

    Map<String, dynamic> extensions = {};
    final rawExt = json['extensions'];
    if (rawExt is Map) {
      extensions = Map<String, dynamic>.from(rawExt);
    }

    return Character(
      id: _str(json['id']).isEmpty
          ? 'char_${DateTime.now().millisecondsSinceEpoch}'
          : _str(json['id']),
      name: _str(json['name']),
      description: description,
      personality: personality,
      scenario: _str(json['scenario']),
      firstMes: firstMes,
      mesExample: _str(json['mes_example']),
      systemPrompt: _str(json['system_prompt']),
      postHistoryInstructions: _str(json['post_history_instructions']),
      alternateGreetings: alternates,
      creatorNotes: _str(json['creator_notes']),
      creator: _str(json['creator']),
      characterVersion: _str(json['character_version']),
      tags: tags,
      characterBook: book,
      extensions: extensions,
      avatarFileName: () {
        final raw = _str(json['avatar_file']);
        return raw.isEmpty ? null : raw;
      }(),
    );
  }

  static String _str(dynamic value) => ('$value' == 'null' ? '' : '$value').trim();

  /// Starter character for a brand-new install.
  static Character starter() {
    return Character(
      id: 'char_starter',
      name: 'Anima',
      description:
          '{{char}} is a warm, thoughtful companion who listens carefully '
          'and replies in clear, natural language.',
      personality: 'Supportive, curious, never overbearing.',
      scenario: '{{user}} is chatting privately with {{char}}.',
      firstMes:
          'Hey — I\'m Anima. Whenever you\'re ready, tell me what\'s on your mind.',
      mesExample:
          '<START>\n{{user}}: How are you?\n{{char}}: I\'m here and listening. What would you like to talk about?',
      characterVersion: '1.0',
      creator: 'Anima',
      tags: const ['anima', 'companion'],
    );
  }
}
