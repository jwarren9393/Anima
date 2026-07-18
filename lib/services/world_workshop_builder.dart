import 'dart:convert';

import '../models/character.dart';
import '../models/chat_message.dart';
import '../models/lorebook.dart';
import '../models/persona.dart';
import 'character_card_codec.dart';
import 'settings_service.dart';

/// One character spotted in a Creation Center workshop (before full card gen).
class WorkshopCharacterCandidate {
  const WorkshopCharacterCandidate({required this.name, this.summary = ''});

  final String name;
  final String summary;

  WorkshopCharacterCandidate copyWith({String? name, String? summary}) {
    return WorkshopCharacterCandidate(
      name: name ?? this.name,
      summary: summary ?? this.summary,
    );
  }
}

/// Builds prompts and parses lorebooks / characters for the Creation Center.
class WorldWorkshopBuilder {
  WorldWorkshopBuilder({CharacterCardCodec? cardCodec})
    : _cardCodec = cardCodec ?? CharacterCardCodec();

  final CharacterCardCodec _cardCodec;

  /// System prompt for the ongoing workshop chat (questions + brainstorming).
  String chatSystemPrompt({
    String guidanceNote = CollaboratorSettings.defaultGuidanceNote,
    Lorebook? sourceLorebook,
  }) {
    final guidance = guidanceNote.trim().isEmpty
        ? CollaboratorSettings.defaultGuidanceNote
        : guidanceNote.trim();

    final source = formatLorebookContext(sourceLorebook);
    return '''
You are Anima's World Info collaborator. You help the user invent a setting,
factions, places, magic, history, and lore for a private roleplay app.

Your job in this chat:
- Ask clear follow-up questions when useful.
- Suggest ideas, but let the user steer.
- Keep track of what they decide.
- Do NOT dump a finished lorebook JSON unless they explicitly ask for a draft
  preview in chat. The app has a separate "Create lorebook" button that will
  ask you for JSON later.
- Do NOT dump finished character-card JSON unless they ask. The app has a
  separate "Create characters" action for that.
${source.isEmpty ? '' : '''
- A lorebook is linked below as the current source of truth. Discuss and revise
  it according to the user's requests. Do not silently discard entries or
  entry settings.

CURRENT LINKED LOREBOOK:
$source
'''}

Guidance note (follow closely):
$guidance

Keep replies conversational and useful on a phone — not huge walls of text
unless the user asks for depth.
'''
        .trim();
  }

  /// Full workshop transcript as plain `User:` / `Assistant:` text.
  String formatTranscript(List<ChatMessage> conversation) {
    final transcript = StringBuffer();
    for (final message in conversation) {
      final who = message.isUser ? 'User' : 'Assistant';
      transcript.writeln('$who: ${message.text.trim()}');
      transcript.writeln();
    }
    return transcript.toString().trim();
  }

  /// Structured source material for an imported / linked lorebook.
  String formatLorebookContext(Lorebook? book) {
    if (book == null) return '';
    return const JsonEncoder.withIndent('  ').convert(book.toJson());
  }

  /// Messages for the final “turn this chat into a lorebook” NanoGPT call.
  List<Map<String, String>> buildExportMessages({
    required List<ChatMessage> conversation,
    String guidanceNote = CollaboratorSettings.defaultGuidanceNote,
    Lorebook? sourceLorebook,
  }) {
    final guidance = guidanceNote.trim().isEmpty
        ? CollaboratorSettings.defaultGuidanceNote
        : guidanceNote.trim();

    final system =
        '''
You convert a world-building conversation into one SillyTavern-compatible
World Info lorebook JSON object for the Anima app.

Guidance note (follow closely):
$guidance

Output rules:
- Reply with ONLY a single JSON object. No markdown fences. No preamble.
- Shape:
{
  "name": "short book title",
  "description": "one-line summary",
  "scan_depth": 4,
  "token_budget": 512,
  "recursive_scanning": false,
  "entries": [
    {
      "name": "optional label",
      "keys": ["keyword", "alias"],
      "secondary_keys": [],
      "content": "lore text injected when keys match",
      "enabled": true,
      "constant": false,
      "selective": false,
      "insertion_order": 100,
      "priority": 10,
      "case_sensitive": false,
      "position": "before_char",
      "comment": ""
    }
  ]
}
- Create useful keyword entries (places, people, factions, rules, items).
- Prefer several focused entries over one giant dump.
- Use "constant": true only for a short always-on overview if helpful.
- keys should be words/phrases that would appear in chat to trigger the entry.
- content should be raw lore text (not JSON). Do not sanitize or moralize.
'''
            .trim();

    final source = formatLorebookContext(sourceLorebook);
    final user =
        '''
${source.isEmpty ? '' : '''
This is the current linked lorebook. Preserve its entries, IDs, settings, and
extensions unless the conversation explicitly asks to change or remove them:

$source

'''}Turn this workshop conversation into one complete lorebook JSON object:

${formatTranscript(conversation)}
'''
            .trim();

    return [
      {'role': 'system', 'content': system},
      {'role': 'user', 'content': user},
    ];
  }

  /// Lightweight pass: list distinct characters developed in the workshop.
  List<Map<String, String>> buildCharacterDetectMessages({
    required List<ChatMessage> conversation,
    String guidanceNote = CollaboratorSettings.defaultGuidanceNote,
    Lorebook? sourceLorebook,
  }) {
    final guidance = guidanceNote.trim().isEmpty
        ? CollaboratorSettings.defaultGuidanceNote
        : guidanceNote.trim();

    final system =
        '''
You scan a world-building conversation and list distinct characters who are
developed enough to become playable SillyTavern-style character cards.

Guidance note (follow closely):
$guidance

Include:
- Named people / beings the user clearly wants as characters
- Recurring figures with personality, role, or backstory

Skip:
- Vague crowd mentions with no identity
- Pure places, factions, or items (unless they are also a person/being)

Output rules:
- Reply with ONLY a single JSON object. No markdown fences. No preamble.
- Shape:
{
  "characters": [
    {
      "name": "Exact character name",
      "summary": "one short sentence: who they are / role"
    }
  ]
}
- Use distinct names; do not duplicate the same person under aliases.
- If none qualify, return {"characters":[]}.
'''
            .trim();

    final source = formatLorebookContext(sourceLorebook);
    final user =
        '''
${source.isEmpty ? '' : '''
Use this linked lorebook as source material:

$source

'''}List playable characters from the linked lorebook and workshop conversation:

${formatTranscript(conversation)}
'''
            .trim();

    return [
      {'role': 'system', 'content': system},
      {'role': 'user', 'content': user},
    ];
  }

  /// Full card generation for one selected character from the workshop.
  List<Map<String, String>> buildCharacterExportMessages({
    required List<ChatMessage> conversation,
    required String characterName,
    String characterSummary = '',
    String guidanceNote = CollaboratorSettings.defaultGuidanceNote,
    Lorebook? sourceLorebook,
  }) {
    final guidance = guidanceNote.trim().isEmpty
        ? CollaboratorSettings.defaultGuidanceNote
        : guidanceNote.trim();
    final name = characterName.trim();
    final summary = characterSummary.trim();

    final system =
        '''
You convert a world-building conversation into ONE SillyTavern Character Card
V2 JSON object for the Anima app (playable chat character).

Guidance note (follow closely):
$guidance

Target character: $name
${summary.isEmpty ? '' : 'Identity hint: $summary'}

Output rules:
- Reply with ONLY a single JSON object. No markdown fences. No preamble.
- Prefer this shape (chara_card_v2):
{
  "spec": "chara_card_v2",
  "spec_version": "2.0",
  "data": {
    "name": "$name",
    "description": "appearance, background, important facts",
    "personality": "traits, speech, motives",
    "scenario": "starting situation for roleplay with {{user}}",
    "first_mes": "opening greeting as this character",
    "alternate_greetings": ["optional other opening"],
    "mes_example": "<START>\\n{{user}}: ...\\n{{char}}: ...",
    "system_prompt": "optional short card system instructions",
    "post_history_instructions": "optional after-history nudge",
    "creator_notes": "brief notes for the card author",
    "tags": ["tag1", "tag2"],
    "creator": "Anima Creation Center",
    "character_version": "1"
  }
}
- Fill fields from the conversation. Invent only what is needed for a usable card.
- Do NOT include a character_book / lorebook on the card — world lore stays in
  the separate global lorebook.
- Do not sanitize or moralize. Output only the JSON object.
'''
            .trim();

    final source = formatLorebookContext(sourceLorebook);
    final user =
        '''
${source.isEmpty ? '' : '''
Use this linked lorebook as source material:

$source

'''}Build a full character card for "$name" from the linked lorebook and workshop conversation:

${formatTranscript(conversation)}
'''
            .trim();

    return [
      {'role': 'system', 'content': system},
      {'role': 'user', 'content': user},
    ];
  }

  /// Player-focused persona generation for one selected workshop character.
  List<Map<String, String>> buildPersonaExportMessages({
    required List<ChatMessage> conversation,
    required String personaName,
    String personaSummary = '',
    String guidanceNote = CollaboratorSettings.defaultGuidanceNote,
    Lorebook? sourceLorebook,
  }) {
    final guidance = guidanceNote.trim().isEmpty
        ? CollaboratorSettings.defaultGuidanceNote
        : guidanceNote.trim();
    final name = personaName.trim();
    final summary = personaSummary.trim();

    final system =
        '''
You convert a world-building conversation into ONE user persona JSON object
for the Anima roleplay app. This is the identity the human user will play,
not an AI-controlled character.

Guidance note (follow closely):
$guidance

Target persona: $name
${summary.isEmpty ? '' : 'Identity hint: $summary'}

Output rules:
- Reply with ONLY a single JSON object. No markdown fences. No preamble.
- Shape:
{
  "name": "$name",
  "description": "concise identity, title, occupation, and role in the setting",
  "appearance": "physical features, clothing, and distinguishing details",
  "personality": "traits, habits, temperament, and speech style",
  "background": "history, relationships, abilities, and important personal facts",
  "goals": "current goals, motives, fears, loyalties, and conflicts"
}
- Write facts about the target persona only. Keep broad world history in the
  separate lorebook instead of repeating it here.
- Do not include greetings, example dialogue, system instructions, or commands
  telling the assistant to roleplay this persona.
- Preserve established facts. Do not sanitize or moralize.
'''
            .trim();

    final source = formatLorebookContext(sourceLorebook);
    final user =
        '''
${source.isEmpty ? '' : '''
Use this linked lorebook as source material:

$source

'''}Build the player persona "$name" from the linked lorebook and workshop conversation:

${formatTranscript(conversation)}
'''
            .trim();

    return [
      {'role': 'system', 'content': system},
      {'role': 'user', 'content': user},
    ];
  }

  /// Parse model output into a [Lorebook]. Throws [FormatException] on failure.
  Lorebook parseLorebookJson(String raw) {
    final map = _extractJsonObject(
      raw,
      emptyMessage: 'The AI returned an empty lorebook.',
      missingMessage:
          'Could not find lorebook JSON in the AI reply. Try Create lorebook again.',
      notObjectMessage: 'Lorebook JSON must be an object.',
    );
    final book = Lorebook.fromJson(map);
    if (book.entries.isEmpty) {
      throw const FormatException(
        'The AI returned a lorebook with no entries. Try chatting a bit more, then Create again.',
      );
    }
    if (book.name.trim().isEmpty) {
      return book.copyWith(name: 'Workshop lorebook');
    }
    return book;
  }

  /// Parse the detection pass into candidates (may be empty).
  List<WorkshopCharacterCandidate> parseCharacterCandidatesJson(String raw) {
    final map = _extractJsonObject(
      raw,
      emptyMessage: 'The AI returned an empty character list.',
      missingMessage:
          'Could not find character list JSON in the AI reply. Try Create characters again.',
      notObjectMessage: 'Character list JSON must be an object.',
    );

    final listRaw = map['characters'] ?? map['candidates'];
    if (listRaw == null) {
      throw const FormatException(
        'Character list JSON must include a “characters” array.',
      );
    }
    if (listRaw is! List) {
      throw const FormatException(
        'Character list “characters” must be an array.',
      );
    }

    final seen = <String>{};
    final out = <WorkshopCharacterCandidate>[];
    for (final item in listRaw) {
      if (item is! Map) continue;
      final data = Map<String, dynamic>.from(item);
      final name = '${data['name'] ?? ''}'.trim();
      if (name.isEmpty) continue;
      final key = name.toLowerCase();
      if (seen.contains(key)) continue;
      seen.add(key);
      out.add(
        WorkshopCharacterCandidate(
          name: name,
          summary: '${data['summary'] ?? data['description'] ?? ''}'.trim(),
        ),
      );
    }
    return out;
  }

  /// Parse one character card. Always assigns a fresh local [preferredId].
  Character parseCharacterJson(
    String raw, {
    String? preferredId,
    String? fallbackName,
  }) {
    final map = _extractJsonObject(
      raw,
      emptyMessage: 'The AI returned an empty character card.',
      missingMessage:
          'Could not find character card JSON in the AI reply. Try again.',
      notObjectMessage: 'Character card JSON must be an object.',
    );

    final id = (preferredId != null && preferredId.trim().isNotEmpty)
        ? preferredId.trim()
        : 'char_${DateTime.now().microsecondsSinceEpoch}';

    final character = _cardCodec.fromCardMap(map, preferredId: id);
    // Never keep an embedded book from workshop character export.
    final cleaned = character.copyWith(
      clearCharacterBook: true,
      name: character.name.trim().isEmpty
          ? (fallbackName?.trim() ?? '')
          : character.name.trim(),
      creator: character.creator.trim().isEmpty
          ? 'Anima Creation Center'
          : character.creator,
    );

    if (cleaned.name.trim().isEmpty) {
      throw const FormatException(
        'The AI returned a character card without a name.',
      );
    }
    return cleaned;
  }

  /// Parse one generated player persona. Always assigns [preferredId].
  Persona parsePersonaJson(
    String raw, {
    String? preferredId,
    String? fallbackName,
  }) {
    final map = _extractJsonObject(
      raw,
      emptyMessage: 'The AI returned an empty persona.',
      missingMessage: 'Could not find persona JSON in the AI reply. Try again.',
      notObjectMessage: 'Persona JSON must be an object.',
    );
    final id = (preferredId != null && preferredId.trim().isNotEmpty)
        ? preferredId.trim()
        : 'persona_${DateTime.now().microsecondsSinceEpoch}';
    final generatedName = '${map['name'] ?? ''}'.trim();
    final name = generatedName.isEmpty
        ? (fallbackName?.trim() ?? '')
        : generatedName;
    if (name.isEmpty) {
      throw const FormatException('The AI returned a persona without a name.');
    }
    return Persona(
      id: id,
      name: name,
      description: '${map['description'] ?? map['role'] ?? ''}'.trim(),
      appearance: '${map['appearance'] ?? ''}'.trim(),
      personality: '${map['personality'] ?? ''}'.trim(),
      background: '${map['background'] ?? map['backstory'] ?? ''}'.trim(),
      goals: '${map['goals'] ?? map['motivation'] ?? ''}'.trim(),
    );
  }

  /// Guess a short workshop title from the first user message.
  String suggestTitle(
    List<ChatMessage> messages, {
    String fallback = 'New workshop',
  }) {
    for (final message in messages) {
      if (!message.isUser) continue;
      final text = message.text.trim();
      if (text.isEmpty) continue;
      final firstLine = text.split('\n').first.trim();
      if (firstLine.length <= 48) return firstLine;
      return '${firstLine.substring(0, 45).trimRight()}…';
    }
    return fallback;
  }

  Map<String, dynamic> _extractJsonObject(
    String raw, {
    required String emptyMessage,
    required String missingMessage,
    required String notObjectMessage,
  }) {
    var text = raw.trim();
    if (text.isEmpty) {
      throw FormatException(emptyMessage);
    }

    // Strip ```json ... ``` if the model ignores instructions.
    final fence = RegExp(r'```(?:json)?\s*([\s\S]*?)```', caseSensitive: false);
    final fenceMatch = fence.firstMatch(text);
    if (fenceMatch != null) {
      text = fenceMatch.group(1)!.trim();
    }

    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start < 0 || end <= start) {
      throw FormatException(missingMessage);
    }

    final slice = text.substring(start, end + 1);
    final decoded = jsonDecode(slice);
    if (decoded is! Map) {
      throw FormatException(notObjectMessage);
    }
    return Map<String, dynamic>.from(decoded);
  }
}
