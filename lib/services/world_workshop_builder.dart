import 'dart:convert';

import '../models/character.dart';
import '../models/chat_message.dart';
import '../models/chat_session.dart';
import '../models/global_lorebook.dart';
import '../models/lorebook.dart';
import '../models/persona.dart';
import '../models/workshop_chat_import_options.dart';
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

  /// Newest raw messages kept when seeding a workshop from a saved chat.
  /// Matches [ContextSettings.defaultKeepRecent] / Summarize “keep recent”.
  static const importKeepRecentDefault = 10;

  /// Legacy cap when no memory summary exists (same as [importKeepRecentDefault]).
  static const importFallbackRecent = importKeepRecentDefault;

  /// Recent messages sent to live-chat character generation (smaller = faster).
  static const characterGenRecentMessages = 24;

  /// Minimum completion budget for workshop brainstorming chat.
  ///
  /// Roleplay presets like "Short replies" (350 tokens) are too small for
  /// numbered follow-up questions — this floor applies only in Creation Center.
  static const workshopChatMinMaxTokens = 2048;

  /// Minimum completion budget for workshop exports (lorebook, opening scene).
  ///
  /// RP "Short replies" caps truncate large JSON payloads — exports need room
  /// for many lore entries in one object.
  static const workshopExportMinMaxTokens = 8192;

  /// Short Creation Center chat replies (~quick ideas).
  static const workshopChatShortMaxTokens = 600;

  /// Detailed Creation Center chat replies (deep brainstorm + questions).
  static const workshopChatDetailedMaxTokens = 4096;

  /// JSON shape for Creation Center / chat-import character card generation.
  ///
  /// Omits scenario, greetings, and per-card system/post-history fields — Anima
  /// uses per-chat opening scenes and global prompts instead.
  static const slimCharacterCardJsonShape = '''
{
  "spec": "chara_card_v2",
  "spec_version": "2.0",
  "data": {
    "name": "Character Name",
    "description": "appearance, background, important facts",
    "personality": "traits, speech style, motives",
    "mes_example": "<START>\\n{{user}}: ...\\n{{char}}: ...",
    "creator_notes": "brief notes for the card author",
    "tags": ["tag1", "tag2"],
    "creator": "Anima Creation Center",
    "character_version": "1"
  }
}''';

  static const slimCharacterCardFieldRules = '''
- Generate ONLY these card fields: name, description, personality, mes_example,
  creator_notes, and tags.
- Do NOT output scenario, first_mes, alternate_greetings, system_prompt, or
  post_history_instructions. Anima uses per-chat opening scenes and app-wide
  system/post-history prompts instead of per-character copies of those fields.
- Do NOT include a character_book / lorebook on the card — world lore stays in
  the separate global lorebook.''';

  static const slimCharacterCardUpdateFieldRules = '''
- Update ONLY: description, personality, mes_example, creator_notes, and tags
  (plus name only if the workshop explicitly requests a rename).
- Do NOT output or change scenario, first_mes, alternate_greetings,
  system_prompt, or post_history_instructions — the app keeps the existing card's
  values for those fields.
- Do NOT include a character_book / lorebook on the card — world lore stays in
  the separate global lorebook. The app keeps the card's existing book.''';

  /// Applies reply-length presets for Creation Center brainstorming chat.
  static SamplingSettings workshopChatSampling(
    SamplingSettings base, {
    WorkshopReplyLength replyLength = WorkshopReplyLength.normal,
  }) {
    return switch (replyLength) {
      WorkshopReplyLength.short => _workshopChatWithCap(
          base,
          cap: workshopChatShortMaxTokens,
        ),
      WorkshopReplyLength.normal => _workshopChatWithFloor(
          base,
          floor: workshopChatMinMaxTokens,
        ),
      WorkshopReplyLength.detailed => _workshopChatWithFloor(
          base,
          floor: workshopChatDetailedMaxTokens,
        ),
    };
  }

  static SamplingSettings _workshopChatWithCap(
    SamplingSettings base, {
    required int cap,
  }) {
    return base.copyWith(maxTokens: cap.clamp(256, 8192));
  }

  static SamplingSettings _workshopChatWithFloor(
    SamplingSettings base, {
    required int floor,
  }) {
    final user = base.maxTokens;
    final effective = user == null || user < floor ? floor : user;
    return base.copyWith(maxTokens: effective.clamp(256, 8192));
  }

  /// Applies [workshopExportMinMaxTokens] for lorebook / opening-scene JSON.
  static SamplingSettings workshopExportSampling(SamplingSettings base) {
    const minTokens = workshopExportMinMaxTokens;
    final user = base.maxTokens;
    final effective = user == null || user < minTokens ? minTokens : user;
    return base.copyWith(maxTokens: effective.clamp(256, 8192));
  }

  /// System prompt for the ongoing workshop chat (questions + brainstorming).
  String chatSystemPrompt({
    String guidanceNote = CollaboratorSettings.defaultGuidanceNote,
    Lorebook? sourceLorebook,
    WorkshopSourceContext? importedSource,
    WorkshopReplyLength replyLength = WorkshopReplyLength.normal,
  }) {
    final guidance = guidanceNote.trim().isEmpty
        ? CollaboratorSettings.defaultGuidanceNote
        : guidanceNote.trim();

    final source = formatLorebookContext(sourceLorebook);
    final imported = formatImportedSource(importedSource);
    final lengthNote = switch (replyLength) {
      WorkshopReplyLength.short =>
        'Reply length: SHORT — give a concise, focused answer (a few paragraphs '
        'at most). Skip long question lists unless the user explicitly asks for them.',
      WorkshopReplyLength.normal =>
        'Reply length: NORMAL — balanced brainstorming. You may ask follow-up '
        'questions, but keep structure clear and avoid huge walls of text.',
      WorkshopReplyLength.detailed =>
        'Reply length: DETAILED — the user wants a thorough brainstorm. Lay out '
        'ideas fully, ask multiple follow-up questions, and finish every numbered '
        'or bulleted list you start.',
    };
    return '''
You are Anima's World Info collaborator. You help the user invent a setting,
factions, places, magic, history, and lore for a private roleplay app.

$lengthNote

Your job in this chat:
- Ask clear follow-up questions when useful.
- Suggest ideas, but let the user steer.
- Keep track of what they decide.
- Do NOT dump a finished lorebook JSON unless they explicitly ask for a draft
  preview in chat. The app has a separate "Create lorebook" button that will
  ask you for JSON later.
- Do NOT dump finished character-card JSON unless they ask. The app has a
  separate "Create characters" action for that.
- Opening scene prose is NOT stored in the lorebook. The app has a dedicated
  Opening scene field (Create opening scene button). When the user describes
  how the story should begin, help them shape it and remind them to save it
  there — do not bury opening narration only in lore entries.
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

When asking follow-up questions, finish every numbered or bulleted list —
never stop mid-question. Prefer clear structure over long prose walls, but
give yourself enough room to ask everything you need in one reply.
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
    WorkshopChatImportOptions options = WorkshopChatImportOptions.defaults,
  }) {
    final keepRecent = options.keepRecent.clamp(1, 80);
    final recent = selectRecentMessagesForImport(
      session,
      keepRecent: keepRecent,
      includeRecentMessages: options.includeRecentMessages,
    );
    final totalMessages = session.messages
        .where((m) => m.text.trim().isNotEmpty)
        .length;
    final userName = persona?.name.trim().isNotEmpty == true
        ? persona!.name.trim()
        : 'User';
    final characterNames = options.includeCharacters
        ? [
            for (final c in characters)
              if (c.name.trim().isNotEmpty) c.name.trim(),
          ]
        : <String>[];
    final loreNames = options.includeGlobalLorebooks
        ? [
            for (final g in linkedLorebooks)
              if (g.displayName.trim().isNotEmpty) g.displayName.trim(),
          ]
        : <String>[];

    final embeddedLoreCount = options.includeEmbeddedCharacterLore
        ? characters
            .where((c) => (c.lorebook?.entries.isNotEmpty ?? false))
            .length
        : 0;

    return WorkshopSourceContext(
      chatId: session.id,
      chatTitle: session.title.trim().isEmpty ? 'Chat' : session.title.trim(),
      isGroup: session.isGroup,
      memorySummary: options.includeMemorySummary
          ? session.memorySummary.trim()
          : '',
      recentTranscript: formatRoleplayTranscript(
        recent,
        userName: userName,
      ),
      recentMessageCount: recent.length,
      charactersText: options.includeCharacters
          ? formatCharactersForImport(characters)
          : '',
      characterNames: characterNames,
      personaText: options.includePersona
          ? formatPersonaForImport(persona)
          : '',
      personaName: options.includePersona &&
              persona?.name.trim().isNotEmpty == true
          ? persona!.name.trim()
          : null,
      loreReferenceText: formatLorebooksForImport(
        linkedLorebooks:
            options.includeGlobalLorebooks ? linkedLorebooks : const [],
        characters: options.includeEmbeddedCharacterLore ? characters : const [],
      ),
      lorebookNames: loreNames,
      authorsNote:
          options.includeAuthorsNote ? session.authorsNote.trim() : '',
      openingScene:
          options.includeOpeningScene ? session.openingScene.trim() : '',
      skippedNotes: skippedNotes,
      importProfile: options.summaryLine(
        totalMessages: totalMessages,
        recentCount: recent.length,
        hasMemory: session.memorySummary.trim().isNotEmpty,
        globalLoreCount: linkedLorebooks.length,
        embeddedLoreCount: embeddedLoreCount,
      ),
      totalMessageCount: totalMessages,
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
      openingScene: full.openingScene,
      skippedNotes: full.skippedNotes,
      importProfile: full.importProfile,
      totalMessageCount: full.totalMessageCount,
    );
  }

  /// Recent roleplay lines from a saved chat, with group speaker labels.
  String chatTranscriptForCharacterGen(
    ChatSession session, {
    String userName = 'User',
  }) {
    final messages = selectRecentMessagesForCharacterGen(session);
    return formatRoleplayTranscript(messages, userName: userName);
  }

  List<ChatMessage> selectRecentMessagesForCharacterGen(ChatSession session) {
    final recent = selectRecentMessagesForImport(session);
    if (recent.length <= characterGenRecentMessages) return recent;
    return recent.sublist(recent.length - characterGenRecentMessages);
  }

  /// Scan a live roleplay chat for characters mentioned in the story.
  List<Map<String, String>> buildChatCharacterDetectMessages({
    required ChatSession session,
    required List<Character> characters,
    Persona? persona,
    List<GlobalLorebook> linkedLorebooks = const [],
    String buildPromptNote = CharacterBuildSettings.defaultPromptNote,
  }) {
    final guidance = buildPromptNote.trim().isEmpty
        ? CharacterBuildSettings.defaultPromptNote
        : buildPromptNote.trim();
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
    String buildPromptNote = CharacterBuildSettings.defaultPromptNote,
  }) {
    final guidance = buildPromptNote.trim().isEmpty
        ? CharacterBuildSettings.defaultPromptNote
        : buildPromptNote.trim();
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
$slimCharacterCardJsonShape
$slimCharacterCardFieldRules
- Fill fields from the chat transcript and reference material. Invent only what
  is needed for a usable card that fits the current scene.
- Keep each field concise (a few sentences each). Do not write long essays.
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

  /// Recent roleplay lines for workshop import — same trim as Summarize:
  /// newest [keepRecent] messages only (not every uncovered line).
  List<ChatMessage> selectRecentMessagesForImport(
    ChatSession session, {
    int keepRecent = importKeepRecentDefault,
    bool includeRecentMessages = true,
  }) {
    if (!includeRecentMessages) return const [];

    final all = session.messages;
    final end = all.length;
    if (end == 0) return const [];

    final keep = keepRecent.clamp(1, 80);
    final recent = <ChatMessage>[];

    for (var i = end - 1; i >= 0 && recent.length < keep; i--) {
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
- Do NOT ask questions or offer to draft later — output the complete lorebook now.
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
- Do NOT ask questions or offer to draft later — output the character list now.
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
    String buildPromptNote = CharacterBuildSettings.defaultPromptNote,
    Lorebook? sourceLorebook,
    WorkshopSourceContext? importedSource,
  }) {
    final guidance = buildPromptNote.trim().isEmpty
        ? CharacterBuildSettings.defaultPromptNote
        : buildPromptNote.trim();
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
$slimCharacterCardJsonShape
$slimCharacterCardFieldRules
- Fill fields from the conversation. Invent only what is needed for a usable card.
- Keep each field concise (a few sentences each). Do not write long essays.
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
    String buildPromptNote = CharacterBuildSettings.defaultPromptNote,
    Lorebook? sourceLorebook,
    WorkshopSourceContext? importedSource,
  }) {
    final guidance = buildPromptNote.trim().isEmpty
        ? CharacterBuildSettings.defaultPromptNote
        : buildPromptNote.trim();
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
$slimCharacterCardJsonShape
$slimCharacterCardUpdateFieldRules
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
      scenario: original.scenario,
      firstMes: original.firstMes,
      mesExample: pick(parsed.mesExample, original.mesExample),
      systemPrompt: original.systemPrompt,
      postHistoryInstructions: original.postHistoryInstructions,
      alternateGreetings: original.alternateGreetings,
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

  /// Build NanoGPT messages to extract opening scene prose from a workshop.
  List<Map<String, String>> buildOpeningSceneExportMessages({
    required List<ChatMessage> conversation,
    String guidanceNote = CollaboratorSettings.defaultGuidanceNote,
    Lorebook? sourceLorebook,
    WorkshopSourceContext? importedSource,
    String existingOpeningScene = '',
  }) {
    final guidance = guidanceNote.trim().isEmpty
        ? CollaboratorSettings.defaultGuidanceNote
        : guidanceNote.trim();
    final existing = existingOpeningScene.trim();

    final system =
        '''
You convert a world-building conversation into ONE opening scene for a roleplay chat.

An opening scene is narrator/setup prose shown once at the start of a chat — NOT a
character's first line, NOT a lorebook entry, and NOT a scenario card field.

Guidance note (follow closely):
$guidance

Output rules:
- Reply with ONLY a single JSON object. No markdown fences. No preamble.
- Shape: {"openingScene": "..."}
- Write in third-person or omniscient narrator voice (stage-direction style is fine).
- Set the moment, place, mood, and what is happening when the story begins.
- Do NOT write dialogue as the character's official first message.
- Keep it readable on a phone (roughly 80–400 words unless the user asked for more).
- Preserve established facts. Do not sanitize or moralize.
${existing.isEmpty ? '' : '- Revise the existing opening scene below when the user asked for changes.'}
'''
            .trim();

    final source = formatLorebookContext(sourceLorebook);
    final imported = _importedBlock(importedSource);
    final user =
        '''
$imported${source.isEmpty ? '' : '''
Use this linked lorebook as source material:

$source

'''}${existing.isEmpty ? '' : '''
Current opening scene (revise when appropriate):

$existing

'''}Extract or write the opening scene from the linked lorebook, imported chat source, and workshop conversation:

${formatTranscript(conversation)}
'''
            .trim();

    return [
      {'role': 'system', 'content': system},
      {'role': 'user', 'content': user},
    ];
  }

  /// Parse model output into opening-scene prose. Throws [FormatException].
  String parseOpeningSceneJson(String raw) {
    final map = _extractJsonObject(
      raw,
      emptyMessage: 'The AI returned an empty opening scene.',
      missingMessage:
          'Could not find opening scene JSON in the AI reply. Try Create opening scene again.',
      notObjectMessage: 'Opening scene JSON must be an object.',
    );
    final text = (map['openingScene'] ?? map['opening_scene'] ?? '')
        .toString()
        .trim();
    if (text.isEmpty) {
      throw const FormatException(
        'The AI returned an opening scene with no text. Try chatting a bit more, then Create again.',
      );
    }
    return text;
  }

  /// Parse model output into a [Lorebook]. Throws [FormatException] on failure.
  Lorebook parseLorebookJson(String raw) {
    final map = _extractJsonObject(
      raw,
      emptyMessage: 'The AI returned an empty lorebook.',
      missingMessage: lorebookJsonMissingMessage(raw),
      notObjectMessage: 'Lorebook JSON must be an object.',
    );
    final book = Lorebook.parseImport(map);
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

  /// User-facing hint when export JSON could not be parsed.
  static String lorebookJsonMissingMessage(String raw) {
    final text = raw.trim();
    if (text.isEmpty) {
      return 'The AI returned an empty reply. Try Create lorebook again.';
    }
    if (text.contains('{') && !text.trim().endsWith('}')) {
      return 'The lorebook JSON was cut off before it finished. '
          'Try Create lorebook again — this build uses a higher token limit for exports.';
    }
    if (!text.contains('{')) {
      return 'The AI replied with text instead of lorebook JSON. '
          'Try Create lorebook again (do not ask in chat — use the ⋮ menu button).';
    }
    return 'Could not find valid lorebook JSON in the AI reply. Try Create lorebook again.';
  }

  /// Follow-up user message when the first export pass did not return JSON.
  static const lorebookExportRetryUserMessage =
      'Your previous reply was not valid lorebook JSON. '
      'Reply with ONLY one complete JSON object using the schema from the system '
      'message. No markdown fences, no preamble, no questions, no explanation.';

  /// Follow-up when character detection did not return JSON.
  static const characterDetectExportRetryUserMessage =
      'Your previous reply was not valid character-list JSON. '
      'Reply with ONLY one JSON object: {"characters":[{"name":"...","summary":"..."}]} '
      'No markdown fences, no preamble, no questions.';

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
    // Workshop exports: no embedded book, and no per-card scene/greeting/prompts.
    final cleaned = character.copyWith(
      clearCharacterBook: true,
      scenario: '',
      firstMes: '',
      alternateGreetings: const [],
      systemPrompt: '',
      postHistoryInstructions: '',
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
    final text = raw.trim();
    if (text.isEmpty) {
      throw FormatException(emptyMessage);
    }

    // Try each fenced block — models often wrap JSON and add prose outside.
    final fence = RegExp(r'```(?:json)?\s*([\s\S]*?)```', caseSensitive: false);
    for (final match in fence.allMatches(text)) {
      final fenced = match.group(1)?.trim() ?? '';
      final parsed = _tryParseJsonObject(
        fenced,
        notObjectMessage: notObjectMessage,
      );
      if (parsed != null) return parsed;
    }

    final parsed = _tryParseJsonObject(
      text,
      notObjectMessage: notObjectMessage,
    );
    if (parsed != null) return parsed;

    throw FormatException(missingMessage);
  }

  Map<String, dynamic>? _tryParseJsonObject(
    String text, {
    required String notObjectMessage,
  }) {
    final slice = _extractBalancedJsonObject(text);
    if (slice == null) return null;
    try {
      final decoded = jsonDecode(slice);
      if (decoded is! Map) {
        throw FormatException(notObjectMessage);
      }
      return Map<String, dynamic>.from(decoded);
    } on FormatException {
      rethrow;
    } catch (_) {
      return null;
    }
  }

  /// First top-level `{...}` using brace counting (respects strings).
  String? _extractBalancedJsonObject(String text) {
    final start = text.indexOf('{');
    if (start < 0) return null;

    var depth = 0;
    var inString = false;
    var escaped = false;
    for (var i = start; i < text.length; i++) {
      final char = text[i];
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (char == r'\') {
          escaped = true;
        } else if (char == '"') {
          inString = false;
        }
        continue;
      }
      if (char == '"') {
        inString = true;
        continue;
      }
      if (char == '{') {
        depth++;
      } else if (char == '}') {
        depth--;
        if (depth == 0) {
          return text.substring(start, i + 1);
        }
      }
    }
    return null;
  }
}
