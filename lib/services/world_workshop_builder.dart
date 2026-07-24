import 'dart:convert';

import '../models/character.dart';
import '../models/chat_message.dart';
import '../models/chat_session.dart';
import '../models/global_lorebook.dart';
import '../models/lorebook.dart';
import '../models/persona.dart';
import '../models/world_workshop.dart';
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

  /// Newest raw messages kept when a memory summary already covers the rest.
  static const importKeepWhenCovered = 12;

  /// Cap for recent raw messages when a chat has no memory summary yet.
  static const importFallbackRecent = 40;

  /// System prompt for the ongoing workshop chat (questions + brainstorming).
  String chatSystemPrompt({
    String guidanceNote = CollaboratorSettings.defaultGuidanceNote,
    Lorebook? sourceLorebook,
    WorkshopSourceContext? importedSource,
  }) {
    final guidance = guidanceNote.trim().isEmpty
        ? CollaboratorSettings.defaultGuidanceNote
        : guidanceNote.trim();

    final source = formatLorebookContext(sourceLorebook);
    final imported = formatImportedSource(importedSource);
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
${imported.isEmpty ? '' : '''
- An existing roleplay chat was imported below as read-only source material.
  Use it to propose a NEW lorebook and optional NEW characters. Do not treat
  imported roleplay lines as prior workshop assistant replies.

$imported
'''}
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

  /// Build read-only Creation Center source from a saved roleplay chat.
  WorkshopSourceContext buildImportedChatSource({
    required ChatSession session,
    required List<Character> characters,
    Persona? persona,
    List<GlobalLorebook> linkedLorebooks = const [],
    List<String> skippedNotes = const [],
  }) {
    final recent = selectRecentMessagesForImport(session);
    final userName = persona?.name.trim().isNotEmpty == true
        ? persona!.name.trim()
        : 'User';
    final characterNames = [
      for (final c in characters)
        if (c.name.trim().isNotEmpty) c.name.trim(),
    ];
    final loreNames = [
      for (final g in linkedLorebooks)
        if (g.displayName.trim().isNotEmpty) g.displayName.trim(),
    ];

    return WorkshopSourceContext(
      chatId: session.id,
      chatTitle: session.title.trim().isEmpty ? 'Chat' : session.title.trim(),
      isGroup: session.isGroup,
      memorySummary: session.memorySummary.trim(),
      recentTranscript: formatRoleplayTranscript(
        recent,
        userName: userName,
      ),
      recentMessageCount: recent.length,
      charactersText: formatCharactersForImport(characters),
      characterNames: characterNames,
      personaText: formatPersonaForImport(persona),
      personaName: persona?.name.trim().isEmpty == false
          ? persona!.name.trim()
          : null,
      loreReferenceText: formatLorebooksForImport(
        linkedLorebooks: linkedLorebooks,
        characters: characters,
      ),
      lorebookNames: loreNames,
      authorsNote: session.authorsNote.trim(),
      skippedNotes: skippedNotes,
    );
  }

  /// Metadata from a live chat (memory, cards, persona, lore) without duplicating
  /// the transcript block used in [buildChatCharacterDetectMessages].
  WorkshopSourceContext chatMetadataContext({
    required ChatSession session,
    required List<Character> characters,
    Persona? persona,
    List<GlobalLorebook> linkedLorebooks = const [],
    List<String> skippedNotes = const [],
  }) {
    final full = buildImportedChatSource(
      session: session,
      characters: characters,
      persona: persona,
      linkedLorebooks: linkedLorebooks,
      skippedNotes: skippedNotes,
    );
    return WorkshopSourceContext(
      chatId: full.chatId,
      chatTitle: full.chatTitle,
      isGroup: full.isGroup,
      memorySummary: full.memorySummary,
      recentTranscript: '',
      recentMessageCount: 0,
      charactersText: full.charactersText,
      characterNames: full.characterNames,
      personaText: full.personaText,
      personaName: full.personaName,
      loreReferenceText: full.loreReferenceText,
      lorebookNames: full.lorebookNames,
      authorsNote: full.authorsNote,
      skippedNotes: full.skippedNotes,
    );
  }

  /// Recent roleplay lines from a saved chat, with group speaker labels.
  String chatTranscriptForCharacterGen(
    ChatSession session, {
    String userName = 'User',
  }) {
    final messages = selectRecentMessagesForImport(session);
    return formatRoleplayTranscript(messages, userName: userName);
  }

  /// Scan a live roleplay chat for characters mentioned in the story.
  List<Map<String, String>> buildChatCharacterDetectMessages({
    required ChatSession session,
    required List<Character> characters,
    Persona? persona,
    List<GlobalLorebook> linkedLorebooks = const [],
    String guidanceNote = CollaboratorSettings.defaultGuidanceNote,
  }) {
    final guidance = guidanceNote.trim().isEmpty
        ? CollaboratorSettings.defaultGuidanceNote
        : guidanceNote.trim();
    final userName = persona?.name.trim().isNotEmpty == true
        ? persona!.name.trim()
        : 'User';

    final system =
        '''
You scan a roleplay chat and list distinct characters who are developed enough
to become playable SillyTavern-style character cards.

Guidance note (follow closely):
$guidance

Include:
- Named people / beings the user or story clearly refers to
- Figures with personality, role, or backstory in the chat

Skip:
- The player persona ({{user}})
- Characters who already have full cards in the "Character cards" section
  unless the chat adds major new details worth a separate temp NPC
- Vague crowd mentions with no identity

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

    final metadata = chatMetadataContext(
      session: session,
      characters: characters,
      persona: persona,
      linkedLorebooks: linkedLorebooks,
    );
    final imported = _importedBlock(metadata);
    final transcript = chatTranscriptForCharacterGen(
      session,
      userName: userName,
    );
    final transcriptBlock = transcript.isEmpty
        ? ''
        : '''
CURRENT CHAT TRANSCRIPT (read-only — find characters here):

$transcript

''';

    final user =
        '''
$imported$transcriptBlock List playable characters mentioned in this roleplay chat:
'''
            .trim();

    return [
      {'role': 'system', 'content': system},
      {'role': 'user', 'content': user},
    ];
  }

  /// Build one character card from a live roleplay chat + optional name hint.
  List<Map<String, String>> buildChatCharacterExportMessages({
    required ChatSession session,
    required List<Character> characters,
    required String characterName,
    String characterSummary = '',
    Persona? persona,
    List<GlobalLorebook> linkedLorebooks = const [],
    String guidanceNote = CollaboratorSettings.defaultGuidanceNote,
  }) {
    final guidance = guidanceNote.trim().isEmpty
        ? CollaboratorSettings.defaultGuidanceNote
        : guidanceNote.trim();
    final name = characterName.trim();
    final summary = characterSummary.trim();
    final userName = persona?.name.trim().isNotEmpty == true
        ? persona!.name.trim()
        : 'User';

    final system =
        '''
You convert a roleplay chat into ONE SillyTavern Character Card V2 JSON object
for the Anima app (playable chat character).

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
    "creator": "Anima",
    "character_version": "1"
  }
}
- Fill fields from the chat transcript and reference material. Invent only what
  is needed for a usable card that fits the current scene.
- Do NOT include a character_book / lorebook on the card.
- Do not sanitize or moralize. Output only the JSON object.
'''
            .trim();

    final metadata = chatMetadataContext(
      session: session,
      characters: characters,
      persona: persona,
      linkedLorebooks: linkedLorebooks,
    );
    final imported = _importedBlock(metadata);
    final transcript = chatTranscriptForCharacterGen(
      session,
      userName: userName,
    );
    final transcriptBlock = transcript.isEmpty
        ? '(No recent messages — use memory summary and character cards only.)'
        : transcript;

    final user =
        '''
$imported
Build a full character card for "$name" from this roleplay chat:

$transcriptBlock
'''
            .trim();

    return [
      {'role': 'system', 'content': system},
      {'role': 'user', 'content': user},
    ];
  }

  /// Full workshop transcript as plain `User:` / `Assistant:` text.
  List<ChatMessage> selectRecentMessagesForImport(ChatSession session) {
    final all = session.messages;
    final end = all.length;
    if (end == 0) return const [];

    final hasSummary = session.memorySummary.trim().isNotEmpty;
    final recent = <ChatMessage>[];

    if (hasSummary) {
      final covered = session.memoryCoveredCount.clamp(0, end);
      for (var i = covered; i < end; i++) {
        if (all[i].text.trim().isEmpty) continue;
        recent.add(all[i]);
      }
      if (recent.isEmpty) {
        for (var i = end - 1;
            i >= 0 && recent.length < importKeepWhenCovered;
            i--) {
          if (all[i].text.trim().isEmpty) continue;
          recent.insert(0, all[i]);
        }
      }
      return recent;
    }

    for (var i = end - 1; i >= 0 && recent.length < importFallbackRecent; i--) {
      if (all[i].text.trim().isEmpty) continue;
      recent.insert(0, all[i]);
    }
    return recent;
  }

  /// Roleplay transcript with group speaker labels preserved.
  String formatRoleplayTranscript(
    List<ChatMessage> messages, {
    String userName = 'User',
  }) {
    final transcript = StringBuffer();
    final safeUser =
        userName.trim().isEmpty ? 'User' : userName.trim();
    for (final message in messages) {
      final text = message.text.trim();
      if (text.isEmpty) continue;
      final who = message.isUser
          ? safeUser
          : (message.speakerName?.trim().isNotEmpty == true
              ? message.speakerName!.trim()
              : 'Character');
      transcript.writeln('$who: $text');
      transcript.writeln();
    }
    return transcript.toString().trim();
  }

  String formatPersonaForImport(Persona? persona) {
    if (persona == null) return '';
    final body = persona.promptText.trim();
    if (body.isEmpty && persona.name.trim().isEmpty) return '';
    final buffer = StringBuffer();
    buffer.writeln('Player persona ({{user}}):');
    buffer.writeln('Name: ${persona.name.trim()}');
    if (body.isNotEmpty) {
      buffer.writeln(body);
    }
    return buffer.toString().trim();
  }

  String formatCharactersForImport(List<Character> characters) {
    if (characters.isEmpty) return '';
    final buffer = StringBuffer('Character cards:');
    for (final character in characters) {
      buffer.writeln();
      buffer.writeln();
      buffer.writeln('### ${character.name.trim().isEmpty ? 'Unnamed' : character.name.trim()}');
      void field(String label, String value) {
        final trimmed = value.trim();
        if (trimmed.isEmpty) return;
        buffer.writeln('$label:');
        buffer.writeln(trimmed);
        buffer.writeln();
      }

      field('Description', character.description);
      field('Personality', character.personality);
      field('Scenario', character.scenario);
      field('First message', character.firstMes);
      field('Example dialogue', character.mesExample);
      field('System prompt', character.systemPrompt);
      field('Post-history instructions', character.postHistoryInstructions);
      field('Creator notes', character.creatorNotes);
      if (character.tags.isNotEmpty) {
        buffer.writeln('Tags: ${character.tags.join(', ')}');
      }
    }
    return buffer.toString().trim();
  }

  String formatLorebooksForImport({
    required List<GlobalLorebook> linkedLorebooks,
    required List<Character> characters,
  }) {
    final buffer = StringBuffer();
    if (linkedLorebooks.isNotEmpty) {
      buffer.writeln(
        'Linked World Info lorebooks (reference only — create a NEW book '
        'unless the user asks to revise an existing linked workshop book):',
      );
      for (final global in linkedLorebooks) {
        buffer.writeln();
        buffer.writeln('## ${global.displayName}');
        buffer.writeln(formatLorebookContext(global.book));
      }
    }

    final embedded = <String>[];
    for (final character in characters) {
      final book = character.lorebook;
      if (book == null || book.entries.isEmpty) continue;
      embedded.add(
        '## Embedded on ${character.name.trim().isEmpty ? 'character' : character.name.trim()}\n'
        '${formatLorebookContext(book)}',
      );
    }
    if (embedded.isNotEmpty) {
      if (buffer.isNotEmpty) buffer.writeln();
      buffer.writeln('Character-embedded lorebooks (reference only):');
      for (final block in embedded) {
        buffer.writeln();
        buffer.writeln(block);
      }
    }
    return buffer.toString().trim();
  }

  String formatImportedSource(WorkshopSourceContext? source) {
    if (source == null || !source.hasContent) return '';
    return source.promptText;
  }

  String _importedBlock(WorkshopSourceContext? importedSource) {
    final text = formatImportedSource(importedSource);
    if (text.isEmpty) return '';
    return '$text\n\n';
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
    WorkshopSourceContext? importedSource,
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
    final imported = _importedBlock(importedSource);
    final user =
        '''
$imported${source.isEmpty ? '' : '''
This is the current linked lorebook. Preserve its entries, IDs, settings, and
extensions unless the conversation explicitly asks to change or remove them:

$source

'''}Turn this workshop conversation${imported.isEmpty ? '' : ' (and imported chat source)'} into one complete lorebook JSON object:

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
    WorkshopSourceContext? importedSource,
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
    final imported = _importedBlock(importedSource);
    final user =
        '''
$imported${source.isEmpty ? '' : '''
Use this linked lorebook as source material:

$source

'''}List playable characters from the linked lorebook, imported chat source, and workshop conversation:

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
    WorkshopSourceContext? importedSource,
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
    final imported = _importedBlock(importedSource);
    final user =
        '''
$imported${source.isEmpty ? '' : '''
Use this linked lorebook as source material:

$source

'''}Build a full character card for "$name" from the linked lorebook, imported chat source, and workshop conversation:

${formatTranscript(conversation)}
'''
            .trim();

    return [
      {'role': 'system', 'content': system},
      {'role': 'user', 'content': user},
    ];
  }

  /// Full card JSON for an existing character (no avatar bytes / id).
  String formatCharacterCardJson(Character character) {
    return _cardCodec.toCardV2Json(character, pretty: true);
  }

  /// Sort saved characters so imported-chat cast appears first.
  List<Character> prioritizeCharactersForUpdate({
    required List<Character> characters,
    WorkshopSourceContext? importedSource,
  }) {
    final priorityNames = <String>{
      for (final name in importedSource?.characterNames ?? const <String>[])
        if (name.trim().isNotEmpty) name.trim().toLowerCase(),
    };
    final prioritized = <Character>[];
    final rest = <Character>[];
    for (final character in characters) {
      final key = character.name.trim().toLowerCase();
      if (priorityNames.contains(key)) {
        prioritized.add(character);
      } else {
        rest.add(character);
      }
    }
    int byName(Character a, Character b) =>
        a.name.toLowerCase().compareTo(b.name.toLowerCase());
    prioritized.sort(byName);
    rest.sort(byName);
    return [...prioritized, ...rest];
  }

  bool isImportedChatCharacter(
    Character character,
    WorkshopSourceContext? importedSource,
  ) {
    final key = character.name.trim().toLowerCase();
    if (key.isEmpty) return false;
    for (final name in importedSource?.characterNames ?? const <String>[]) {
      if (name.trim().toLowerCase() == key) return true;
    }
    return false;
  }

  /// Preserve-and-merge update for an existing saved character card.
  List<Map<String, String>> buildCharacterUpdateMessages({
    required List<ChatMessage> conversation,
    required Character existing,
    String guidanceNote = CollaboratorSettings.defaultGuidanceNote,
    Lorebook? sourceLorebook,
    WorkshopSourceContext? importedSource,
  }) {
    final guidance = guidanceNote.trim().isEmpty
        ? CollaboratorSettings.defaultGuidanceNote
        : guidanceNote.trim();
    final name = existing.name.trim().isEmpty ? 'Character' : existing.name.trim();
    final currentCard = formatCharacterCardJson(existing);

    final system =
        '''
You update ONE existing SillyTavern Character Card for the Anima app.

Guidance note (follow closely):
$guidance

Target character: $name

Preserve-and-merge rules:
- Keep established facts from the CURRENT CARD unless the workshop conversation
  clearly revises them.
- Merge in new details established or requested in the workshop / imported chat
  source / linked lorebook.
- Do not invent large contradictions or erase personality, history, or looks
  that the current card already states.
- Prefer richer, specific wording over vague replacements.
- Keep the same character identity (same person). Do not rename unless the
  workshop explicitly asks for a name change.

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
- Do NOT include a character_book / lorebook on the card — world lore stays in
  the separate global lorebook. The app keeps the card's existing book.
- Do not sanitize or moralize. Output only the JSON object.
'''
            .trim();

    final source = formatLorebookContext(sourceLorebook);
    final imported = _importedBlock(importedSource);
    final user =
        '''
CURRENT CHARACTER CARD (preserve established facts; merge workshop updates):
$currentCard

$imported${source.isEmpty ? '' : '''
Use this linked lorebook as additional source material:

$source

'''}Update the character card for "$name" using the current card plus workshop conversation:

${formatTranscript(conversation)}
'''
            .trim();

    return [
      {'role': 'system', 'content': system},
      {'role': 'user', 'content': user},
    ];
  }

  /// Parse an update draft, keeping [original] id/avatar/book/extensions/metadata
  /// and any core field the model left empty.
  Character parseCharacterUpdateJson(
    String raw, {
    required Character original,
  }) {
    final parsed = parseCharacterJson(
      raw,
      preferredId: original.id,
      fallbackName: original.name,
    );

    String pick(String next, String previous) {
      final trimmed = next.trim();
      return trimmed.isEmpty ? previous : trimmed;
    }

    return Character(
      id: original.id,
      name: pick(parsed.name, original.name),
      description: pick(parsed.description, original.description),
      personality: pick(parsed.personality, original.personality),
      scenario: pick(parsed.scenario, original.scenario),
      firstMes: pick(parsed.firstMes, original.firstMes),
      mesExample: pick(parsed.mesExample, original.mesExample),
      systemPrompt: pick(parsed.systemPrompt, original.systemPrompt),
      postHistoryInstructions: pick(
        parsed.postHistoryInstructions,
        original.postHistoryInstructions,
      ),
      alternateGreetings: parsed.alternateGreetings.isEmpty
          ? original.alternateGreetings
          : parsed.alternateGreetings,
      creatorNotes: original.creatorNotes.trim().isNotEmpty
          ? original.creatorNotes
          : pick(parsed.creatorNotes, original.creatorNotes),
      creator: original.creator.trim().isNotEmpty
          ? original.creator
          : pick(parsed.creator, original.creator),
      characterVersion: original.characterVersion.trim().isNotEmpty
          ? original.characterVersion
          : pick(parsed.characterVersion, original.characterVersion),
      tags: parsed.tags.isEmpty ? original.tags : parsed.tags,
      characterBook: original.characterBook,
      extensions: original.extensions,
      avatarFileName: original.avatarFileName,
    );
  }

  /// Player-focused persona generation for one selected workshop character.
  List<Map<String, String>> buildPersonaExportMessages({
    required List<ChatMessage> conversation,
    required String personaName,
    String personaSummary = '',
    String guidanceNote = CollaboratorSettings.defaultGuidanceNote,
    Lorebook? sourceLorebook,
    WorkshopSourceContext? importedSource,
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
    final imported = _importedBlock(importedSource);
    final user =
        '''
$imported${source.isEmpty ? '' : '''
Use this linked lorebook as source material:

$source

'''}Build the player persona "$name" from the linked lorebook, imported chat source, and workshop conversation:

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
