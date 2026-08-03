import 'dart:convert';

import '../models/character.dart';
import '../models/chat_message.dart';
import '../models/chat_session.dart';
import '../models/global_lorebook.dart';
import '../models/lorebook.dart';
import '../models/opening_scene_length.dart';
import '../models/persona.dart';
import '../models/workshop_chat_import_options.dart';
import '../models/world_workshop.dart';
import '../models/workshop_hub_models.dart';
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
  static const workshopChatMinMaxTokens = 1536;

  /// Minimum completion budget for workshop exports (lorebook, opening scene).
  ///
  /// RP "Short replies" caps truncate large JSON payloads — exports need room
  /// for many lore entries in one object.
  static const workshopExportMinMaxTokens = 8192;

  /// Example for character-list detection — concrete names so models don't echo
  /// instructional placeholder text from the schema.
  static const characterListJsonExample = '''
{
  "characters": [
    {"name": "Mira Vale", "summary": "Dock smuggler who owes the Tide Guild"},
    {"name": "Captain Vex", "summary": "Hard-eyed night watch commander"}
  ]
}''';

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
    "description": "appearance, role, and factual backstory only",
    "personality": "temperament, speech style, and behavior only",
    "mes_example": "<START>\\n{{user}}: ...\\n{{char}}: ...",
    "creator_notes": "brief notes for the card author",
    "tags": ["tag1", "tag2"],
    "creator": "Anima Creation Center",
    "character_version": "1"
  }
}''';

  static const slimCharacterCardFieldSplitRules = '''
FIELD SPLIT (token efficiency — critical):
- description = physical appearance, age, role/occupation, and factual backstory
  (who they are on paper: looks, history, affiliations, concrete skills).
- personality = temperament, values, habits, speech style, and how they behave
  in scenes — not a repeat of description.
- Put each fact in ONE field only. Never copy the same sentence into both fields.
- If a detail could fit both, choose: facts/history → description; behavior/voice
  → personality.
- Keep each field 2–4 sentences unless the source is unusually rich.
- mes_example = short RP sample only (not a third copy of bio text).''';

  static const slimCharacterCardFieldRules = '''
- Generate ONLY these card fields: name, description, personality, mes_example,
  creator_notes, and tags.
- Do NOT output scenario, first_mes, alternate_greetings, system_prompt, or
  post_history_instructions. Anima uses per-chat opening scenes and app-wide
  system/post-history prompts instead of per-character copies of those fields.
- Do NOT include a character_book / lorebook on the card — world lore stays in
  the separate global lorebook.
$slimCharacterCardFieldSplitRules''';

  static const slimCharacterCardUpdateFieldRules = '''
- Update ONLY: description, personality, mes_example, creator_notes, and tags
  (plus name only if the workshop explicitly requests a rename).
- Do NOT output or change scenario, first_mes, alternate_greetings,
  system_prompt, or post_history_instructions — the app keeps the existing card's
  values for those fields.
- Do NOT include a character_book / lorebook on the card — world lore stays in
  the separate global lorebook. The app keeps the card's existing book.
$slimCharacterCardFieldSplitRules''';

  static const lorebookExportScopeRules = '''
LOREBOOK SCOPE (critical — Anima uses separate character cards):
- This lorebook is WORLD INFO only: places, factions, rules, items, history,
  events, organizations, magic/tech systems, locations, and minor NPCs.
- Do NOT create lore entries that duplicate full character cards for main cast
  members who have or will get playable character cards — their description and
  personality live on the card, not in World Info.
- For playable cast: at most one short cross-reference entry ONLY when world
  context must mention them (e.g. keys: faction name; content: 1–2 sentences on
  the guild, not a character biography). Never use a cast member's name as the
  only keyword for a full bio entry.
- NPCs with no character card may get a focused lore entry (role + 2–3 facts).
- Prefer keyword triggers that will appear naturally in chat (place names,
  faction names, artifact names) — not character names alone.''';

  static const slimPersonaJsonShape = '''
{
  "name": "Display name",
  "description": "identity, title, occupation, and role in the setting",
  "appearance": "physical features, clothing, and distinguishing details",
  "personality": "traits, habits, temperament, and speech style",
  "background": "history, relationships, abilities, and important facts",
  "goals": "motives, fears, loyalties, conflicts, and what they want"
}''';

  static const slimPersonaFieldRules = '''
- Generate ONLY these persona fields: name, description, appearance,
  personality, background, and goals.
- This is the human player ({{user}}), not an AI character card.
- Keep each field concise (a few sentences). Do not write long essays.''';

  static const slimPersonaUpdateFieldRules = '''
- Update ONLY: name (if notes request it), description, appearance,
  personality, background, and goals.
- This is the human player ({{user}}), not an AI character card.
- Merge updates; do not erase established facts unless the notes revise them.''';

  /// Applies reply-length presets for Creation Center brainstorming chat.
  static SamplingSettings workshopChatSampling(
    SamplingSettings base, {
    WorkshopReplyLength replyLength = WorkshopReplyLength.normal,
  }) {
    final withPenalties = base.copyWith(
      frequencyPenalty: base.frequencyPenalty < 0.35 ? 0.4 : base.frequencyPenalty,
      presencePenalty: base.presencePenalty < 0.15 ? 0.18 : base.presencePenalty,
      repetitionPenalty: base.repetitionPenalty ?? 1.08,
    );
    return switch (replyLength) {
      WorkshopReplyLength.short => _workshopChatWithCap(
          withPenalties,
          cap: workshopChatShortMaxTokens,
        ),
      WorkshopReplyLength.normal => _workshopChatWithFloor(
          withPenalties,
          floor: workshopChatMinMaxTokens,
        ),
      WorkshopReplyLength.detailed => _workshopChatWithFloor(
          withPenalties,
          floor: workshopChatDetailedMaxTokens,
        ),
    };
  }

  /// Workshop chat should not inherit the character-card wand note by default.
  static String resolveWorkshopGuidance({
    String guidanceNote = CollaboratorSettings.defaultGuidanceNote,
    String workshopGuidanceNote = '',
  }) {
    final local = workshopGuidanceNote.trim();
    if (local.isNotEmpty) return local;
    final global = guidanceNote.trim();
    if (global.isNotEmpty &&
        global != CollaboratorSettings.defaultGuidanceNote) {
      return global;
    }
    return CollaboratorSettings.defaultWorkshopGuidanceNote;
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

  /// Minimum completion budget for consistency-check prose reports.
  static const consistencyReportMinMaxTokens = 2048;

  /// Applies [consistencyReportMinMaxTokens] for read-only consistency reports.
  static SamplingSettings consistencyReportSampling(SamplingSettings base) {
    const minTokens = consistencyReportMinMaxTokens;
    final user = base.maxTokens;
    final effective = user == null || user < minTokens ? minTokens : user;
    return base.copyWith(maxTokens: effective.clamp(512, 8192));
  }

  /// Applies [workshopExportMinMaxTokens] for JSON consistency-fix replies.
  static SamplingSettings consistencyFixSampling(SamplingSettings base) {
    return workshopExportSampling(base);
  }

  static const plainEnglishUpdateTargetFieldRules = '''
TARGET FIELD RULES (read the user's notes carefully):
- If they ask to change only one area, update ONLY that field:
  · description / appearance / backstory / role / looks → description only
  · personality / traits / temperament / how they act / speech → personality only
  · example dialogue / mes_example / sample lines / chat style → mes_example only
  · tags only → tags only
- If they name multiple fields, update only those named fields.
- If they give a general update with no specific field, merge into the fields
  their notes clearly affect — do not rewrite unrelated fields.
- Never duplicate the same facts in both description and personality.''';

  /// Applies [workshopExportMinMaxTokens] for lorebook / opening-scene JSON.
  static SamplingSettings workshopExportSampling(SamplingSettings base) {
    const minTokens = workshopExportMinMaxTokens;
    final user = base.maxTokens;
    final effective = user == null || user < minTokens ? minTokens : user;
    return base.copyWith(maxTokens: effective.clamp(256, 8192));
  }

  /// Tight cap for revising the last workshop reply in place (correction notes).
  static SamplingSettings workshopCorrectionSampling(
    SamplingSettings base, {
    required int originalCharCount,
  }) {
    final estTokens = (originalCharCount / 4).ceil() + 256;
    final cap = estTokens.clamp(512, workshopChatMinMaxTokens);
    return base.copyWith(
      maxTokens: cap,
      temperature: base.temperature.clamp(0.1, 1.0) <= 0.45
          ? base.temperature
          : 0.35,
    );
  }

  /// System prompt for the ongoing workshop chat (questions + brainstorming).
  String chatSystemPrompt({
    String guidanceNote = CollaboratorSettings.defaultGuidanceNote,
    Lorebook? sourceLorebook,
    WorkshopSourceContext? importedSource,
    WorkshopReplyLength replyLength = WorkshopReplyLength.normal,
    WorkshopMode mode = WorkshopMode.explore,
    String workshopGuidanceNote = '',
    String worldSummary = '',
    List<ChatMessage> conversation = const [],
    List<String> canonPinMessageIds = const [],
  }) {
    final globalGuidance = guidanceNote.trim().isEmpty
        ? CollaboratorSettings.defaultGuidanceNote
        : guidanceNote.trim();
    final guidance = resolveWorkshopGuidance(
      guidanceNote: globalGuidance,
      workshopGuidanceNote: workshopGuidanceNote,
    );

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
    final modeNote = switch (mode) {
      WorkshopMode.explore =>
        'Mode: EXPLORE — brainstorm freely, ask questions, propose ideas.',
      WorkshopMode.canon =>
        'Mode: CANON — consolidate established facts, flag contradictions, '
        'and help lock in what is officially true in this world.',
      WorkshopMode.characters =>
        'Mode: CHARACTERS — focus on cast, voices, relationships, and motives.',
      WorkshopMode.playtest =>
        'Mode: PLAYTEST — write short in-character vignettes to test tone and dynamics.',
    };
    final summaryBlock = worldSummary.trim().isEmpty
        ? ''
        : '''
WORLD SUMMARY (established facts — treat as canon unless the user revises):
${worldSummary.trim()}
''';
    final canonBlock = formatCanonPins(conversation, canonPinMessageIds);
    return '''
You are Anima's Creation Center collaborator — a brainstorming partner inside a
private roleplay app. This chat is ONLY for inventing and revising ideas together.
You do not run the app and you cannot save anything by replying here.

YOUR ACTUAL ROLE IN THE APP:
- Help the user explore setting, factions, places, rules, history, cast, tone, and
  story hooks through conversation.
- Track what they decide and reflect it back clearly.
- When they confirm or revise ideas, give SHORT deltas (do not reprint huge
  recaps every turn unless they ask for a full rewrite).
- Honor WORLD SUMMARY, canon pins, linked lorebook, and imported chat source
  when present.

WHAT YOU CANNOT DO (never pretend you did these in chat):
- Create, update, or save World Info / lorebook entries.
- Create, update, or save character cards or personas.
- Save opening scene prose to the app.
- Start a roleplay chat or change app settings.
- Execute "I'll build the lorebook now" or "I created those entries" — you only
  send text; the app saves through separate buttons the user taps.

HOW THE USER ACTUALLY SAVES WORK (tell them when relevant, using exact labels):
- ⋮ menu → **Create lorebook** / **Update lorebook** — exports keyword **world** lore
  (places, factions, rules — not full character bios; use **Create AI characters**
  for cast cards).
- ⋮ menu → **Create AI characters** — generates new cards from the workshop;
  user reviews each before save.
- ⋮ menu → **Update workshop cast** — revises characters already tied to THIS
  workshop (created here or linked here); user reviews before overwrite.
- ⋮ menu → **Create my persona** / **Update my persona** — player identity for
  this workshop; update merges the full workshop chat into the linked persona.
- ⋮ menu → **Opening scene** / chip **Add scene** — narrator setup for roleplay
  (not stored in the lorebook).
- ⋮ menu → **World dashboard** → **Play this world** — starts solo/group chat.
- Long-press messages → **Pin as canon**, **Fold older chat into summary**.
- **Fix last** composer chip — small in-place correction to your previous reply.

CONVERSATION STYLE (stay immersive):
- Do NOT end with faux menu choices like "A) build lore entries B) pause and play"
  as if typing A or B will run the app. That feels broken.
- Instead: continue brainstorming OR briefly note what they could tap next when
  the workshop is ready (e.g. "We've locked in the estate — when you want World
  Info saved, tap ⋮ → Update lorebook.").
- If they say they want lore or cards saved, acknowledge and point to the control
  above; do not output finished lorebook JSON or card JSON unless they explicitly
  ask for a draft preview in chat (rare).
- Opening scene prose belongs in **Opening scene**, not buried only in lore entries.

$lengthNote

$modeNote

TOKEN EFFICIENCY (important):
- The app keeps a WORLD SUMMARY and only sends recent chat lines to you.
  Do not repeat the entire world overview every turn — reference the summary
  and add only what changed.
- When the user confirms ideas or asks for a small revision ("change X",
  "update that part", "sounds good but…"), reply with a SHORT delta: only the
  lines that changed or the one section they asked about. Do NOT reprint the
  full character sheet, estate layout, or numbered recap unless they explicitly
  ask for a full rewrite.
- Prefer bullet deltas over walls of prose. If you already laid out a big block
  in a prior turn, later turns should be brief unless they request depth.
- After a large brainstorm dump, suggest they fold into summary (long-press →
  Fold older chat into summary, or ⋮ → World dashboard → Summarize workshop).
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
${summaryBlock.isEmpty ? '' : '$summaryBlock\n'}
${canonBlock.isEmpty ? '' : '$canonBlock\n'}

Guidance note (follow closely):
$guidance

When asking follow-up questions, finish numbered or bulleted lists you start —
but keep each reply proportional to the reply-length setting above; do not
pad with repetition to fill the token budget.
'''
        .trim();
  }

  /// Characters created in or linked to a Creation Center workshop.
  List<Character> workshopCastCharacters({
    required WorldWorkshop workshop,
    required List<Character> allCharacters,
  }) {
    final cast = <Character>[];
    final seen = <String>{};
    for (final id in workshop.linkedCharacterIds) {
      for (final c in allCharacters) {
        if (c.id == id && seen.add(c.id)) cast.add(c);
      }
    }
    for (final c in allCharacters) {
      if (c.sourceWorkshopId == workshop.id && seen.add(c.id)) cast.add(c);
    }
    cast.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    return cast;
  }

  /// Pinned canon lines from workshop messages.
  String formatCanonPins(
    List<ChatMessage> conversation,
    List<String> canonPinMessageIds,
  ) {
    if (canonPinMessageIds.isEmpty) return '';
    final lines = <String>[];
    for (final id in canonPinMessageIds) {
      for (final msg in conversation) {
        if (msg.id != id) continue;
        final role = msg.role == ChatRole.user ? 'User' : 'Collaborator';
        final text = msg.text.trim();
        if (text.isEmpty) continue;
        lines.add('$role: $text');
        break;
      }
    }
    if (lines.isEmpty) return '';
    return '''
CANON PINS (user-locked facts — always honor these):
${lines.join('\n')}
''';
  }

  static const workshopPromptChips = [
    'Describe the setting in 3 sentences',
    'Who are the main factions?',
    'What is the central conflict?',
    'Suggest 5 lorebook entry ideas',
    'What locations matter most?',
    'Who should the cast include?',
  ];

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
- Use REAL names from the transcript below — never copy schema placeholder text.
- Example shape (fill with actual people from the chat; names are illustrative only):
$characterListJsonExample
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

  /// Build one slim character card from plain-English notes (no chat transcript).
  List<Map<String, String>> buildPlainEnglishCharacterExportMessages({
    required String userBrief,
    String characterName = '',
    String buildPromptNote = CharacterBuildSettings.defaultPromptNote,
  }) {
    final guidance = buildPromptNote.trim().isEmpty
        ? CharacterBuildSettings.defaultPromptNote
        : buildPromptNote.trim();
    final brief = userBrief.trim();
    if (brief.isEmpty) {
      throw ArgumentError('userBrief must not be empty');
    }
    final name = characterName.trim();

    final system =
        '''
You convert plain-English character notes into ONE SillyTavern Character Card V2
JSON object for the Anima app (playable chat character).

Guidance note (follow closely):
$guidance

${name.isEmpty ? '' : 'Suggested name: $name\n'}
Output rules:
- Reply with ONLY a single JSON object. No markdown fences. No preamble.
- Prefer this shape (chara_card_v2):
$slimCharacterCardJsonShape
$slimCharacterCardFieldRules
- Fill fields from the user's notes. Invent only what is needed for a usable card.
- Keep each field concise (a few sentences each). Do not write long essays.
- Do not sanitize or moralize. Output only the JSON object.
'''
            .trim();

    final user =
        '''
Turn these character notes into a full slim character card:

$brief
'''
            .trim();

    return [
      {'role': 'system', 'content': system},
      {'role': 'user', 'content': user},
    ];
  }

  /// Preserve-and-merge update from plain-English change notes.
  List<Map<String, String>> buildPlainEnglishCharacterUpdateMessages({
    required Character existing,
    required String userBrief,
    String buildPromptNote = CharacterBuildSettings.defaultPromptNote,
  }) {
    final guidance = buildPromptNote.trim().isEmpty
        ? CharacterBuildSettings.defaultPromptNote
        : buildPromptNote.trim();
    final brief = userBrief.trim();
    if (brief.isEmpty) {
      throw ArgumentError('userBrief must not be empty');
    }
    final name =
        existing.name.trim().isEmpty ? 'Character' : existing.name.trim();
    final currentCard = formatCharacterCardJson(existing);

    final system =
        '''
You update ONE existing SillyTavern Character Card for the Anima app using the
user's plain-English change notes.

Guidance note (follow closely):
$guidance

Target character: $name

Preserve-and-merge rules:
- Keep established facts from the CURRENT CARD unless the notes clearly revise them.
- Merge in new details from the user's notes.
- Do not invent large contradictions or erase personality, history, or looks
  that the current card already states.
- Prefer richer, specific wording over vague replacements.
- Keep the same character identity (same person). Do not rename unless the
  notes explicitly ask for a name change.

$plainEnglishUpdateTargetFieldRules

Output rules:
- Reply with ONLY a single JSON object. No markdown fences. No preamble.
- Prefer this shape (chara_card_v2):
$slimCharacterCardJsonShape
$slimCharacterCardUpdateFieldRules
- Do not sanitize or moralize. Output only the JSON object.
'''
            .trim();

    final user =
        '''
CURRENT CHARACTER CARD (preserve established facts; merge updates from notes):
$currentCard

User change notes:
$brief
'''
            .trim();

    return [
      {'role': 'system', 'content': system},
      {'role': 'user', 'content': user},
    ];
  }

  /// Build one persona from plain-English notes (no chat transcript).
  List<Map<String, String>> buildPlainEnglishPersonaExportMessages({
    required String userBrief,
    String personaName = '',
    String buildPromptNote = CharacterBuildSettings.defaultPromptNote,
  }) {
    final guidance = buildPromptNote.trim().isEmpty
        ? CharacterBuildSettings.defaultPromptNote
        : buildPromptNote.trim();
    final brief = userBrief.trim();
    if (brief.isEmpty) {
      throw ArgumentError('userBrief must not be empty');
    }
    final name = personaName.trim();

    final system =
        '''
You convert plain-English player notes into ONE user persona JSON object for
the Anima roleplay app (who {{user}} is — not an AI character).

Guidance note (follow closely):
$guidance

${name.isEmpty ? '' : 'Suggested name: $name\n'}
Output rules:
- Reply with ONLY a single JSON object. No markdown fences. No preamble.
- Shape:
$slimPersonaJsonShape
$slimPersonaFieldRules
- Fill fields from the user's notes. Invent only what is needed for a usable persona.
- Do not sanitize or moralize. Output only the JSON object.
'''
            .trim();

    final user =
        '''
Turn these player persona notes into a full persona:

$brief
'''
            .trim();

    return [
      {'role': 'system', 'content': system},
      {'role': 'user', 'content': user},
    ];
  }

  /// Preserve-and-merge persona update from plain-English change notes.
  List<Map<String, String>> buildPlainEnglishPersonaUpdateMessages({
    required Persona existing,
    required String userBrief,
    String buildPromptNote = CharacterBuildSettings.defaultPromptNote,
  }) {
    final guidance = buildPromptNote.trim().isEmpty
        ? CharacterBuildSettings.defaultPromptNote
        : buildPromptNote.trim();
    final brief = userBrief.trim();
    if (brief.isEmpty) {
      throw ArgumentError('userBrief must not be empty');
    }
    final name = existing.name.trim().isEmpty ? 'User' : existing.name.trim();
    final currentPersona = formatPersonaJson(existing);

    final system =
        '''
You update ONE existing user persona JSON object for the Anima roleplay app
using the user's plain-English change notes.

Guidance note (follow closely):
$guidance

Target persona: $name

Preserve-and-merge rules:
- Keep established facts from CURRENT PERSONA unless the notes clearly revise them.
- Merge in new details from the user's notes.
- Do not invent contradictions or erase identity the persona already states.
- Keep the same person unless the notes explicitly ask for a rename.

Output rules:
- Reply with ONLY a single JSON object. No markdown fences. No preamble.
- Shape:
$slimPersonaJsonShape
$slimPersonaUpdateFieldRules
- Do not sanitize or moralize. Output only the JSON object.
'''
            .trim();

    final user =
        '''
CURRENT PERSONA (preserve established facts; merge updates from notes):
$currentPersona

User change notes:
$brief
'''
            .trim();

    return [
      {'role': 'system', 'content': system},
      {'role': 'user', 'content': user},
    ];
  }

  /// Preserve-and-merge update for a saved character using a live roleplay chat.
  List<Map<String, String>> buildChatCharacterUpdateMessages({
    required ChatSession session,
    required List<Character> characters,
    required Character existing,
    Persona? persona,
    List<GlobalLorebook> linkedLorebooks = const [],
    String changeNotes = '',
    String buildPromptNote = CharacterBuildSettings.defaultPromptNote,
  }) {
    final guidance = buildPromptNote.trim().isEmpty
        ? CharacterBuildSettings.defaultPromptNote
        : buildPromptNote.trim();
    final name =
        existing.name.trim().isEmpty ? 'Character' : existing.name.trim();
    final currentCard = formatCharacterCardJson(existing);
    final notes = changeNotes.trim();
    final userName = persona?.name.trim().isNotEmpty == true
        ? persona!.name.trim()
        : 'User';

    final system =
        '''
You update ONE existing SillyTavern Character Card for the Anima app using a
live roleplay chat as source material.

Guidance note (follow closely):
$guidance

Target character: $name

Preserve-and-merge rules:
- Keep established facts from the CURRENT CARD unless the chat or user notes
  clearly revise them.
- Merge in new details established in the roleplay transcript.
- Do not invent large contradictions or erase personality, history, or looks
  that the current card already states.
- Prefer richer, specific wording over vague replacements.
- Keep the same character identity (same person). Do not rename unless the
  chat or notes explicitly ask for a name change.

Output rules:
- Reply with ONLY a single JSON object. No markdown fences. No preamble.
- Prefer this shape (chara_card_v2):
$slimCharacterCardJsonShape
$slimCharacterCardUpdateFieldRules
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
    final notesBlock = notes.isEmpty
        ? ''
        : '''

User change notes (apply these on top of the card and chat):
$notes
''';

    final user =
        '''
CURRENT CHARACTER CARD (preserve established facts; merge chat updates):
$currentCard

$imported$notesBlock
Update the character card for "$name" using the current card plus this roleplay chat:

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

  /// Names (+ optional one-line role) for lore export — cards already cover bios.
  String formatWorkshopCastForLoreExport(List<Character> cast) {
    if (cast.isEmpty) return '';
    final lines = <String>[
      'WORKSHOP CAST (already have or will get character cards — do NOT duplicate '
      'these people as full lorebook bio entries):',
    ];
    for (final character in cast) {
      final name = character.name.trim();
      if (name.isEmpty) continue;
      final role = character.description.trim();
      if (role.isEmpty) {
        lines.add('- $name');
      } else {
        final short = role.length > 120 ? '${role.substring(0, 117).trimRight()}…' : role;
        lines.add('- $name — $short');
      }
    }
    if (lines.length <= 1) return '';
    return '${lines.join('\n')}\n';
  }

  /// Messages for the final “turn this chat into a lorebook” NanoGPT call.
  List<Map<String, String>> buildExportMessages({
    required List<ChatMessage> conversation,
    String guidanceNote = CollaboratorSettings.defaultGuidanceNote,
    Lorebook? sourceLorebook,
    WorkshopSourceContext? importedSource,
    String worldSummary = '',
    List<String> canonPinMessageIds = const [],
    List<Character> workshopCast = const [],
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
- Create useful keyword entries (places, factions, rules, items, events).
- Prefer several focused entries over one giant dump.
- Use "constant": true only for a short always-on overview if helpful.
- keys should be words/phrases that would appear in chat to trigger the entry.
- content should be raw lore text (not JSON). Do not sanitize or moralize.

$lorebookExportScopeRules
'''
            .trim();

    final source = formatLorebookContext(sourceLorebook);
    final imported = _importedBlock(importedSource);
    final castBlock = formatWorkshopCastForLoreExport(workshopCast);
    final summaryBlock = worldSummary.trim().isEmpty
        ? ''
        : 'World summary:\n${worldSummary.trim()}\n\n';
    final canonBlock = formatCanonPins(conversation, canonPinMessageIds);
    final isUpdate = sourceLorebook != null;
    final updateRules = isUpdate
        ? '''
UPDATE MODE (linked lorebook present):
- This is an UPDATE, not a blank slate. Preserve existing entry IDs, extensions,
  and settings unless the workshop explicitly asks to remove them.
- ADD new world entries (places, factions, rules, items) established in the
  workshop but missing from the current book — not duplicate character bios.
- REMOVE or shorten lore entries that only repeat character-card bios for cast
  members listed below (world context may stay if keyed on factions/places).
- REVISE existing entries when the chat updates or contradicts older lore —
  prefer workshop conversation, canon pins, and world summary over stale book text.
- Resolve contradictions by aligning the book with the latest workshop canon.
'''
        : '';
    final user =
        '''
$imported$summaryBlock${castBlock.isEmpty ? '' : '$castBlock\n'}${canonBlock.isEmpty ? '' : '$canonBlock\n'}${source.isEmpty ? '' : '''
This is the current linked lorebook. Preserve its entries, IDs, settings, and
extensions unless the conversation explicitly asks to change or remove them:

$source

$updateRules
'''}Turn this workshop conversation${imported.isEmpty ? '' : ' (and imported chat source)'} into one complete lorebook JSON object:

${formatTranscript(conversation)}
'''
            .trim();

    return [
      {'role': 'system', 'content': system},
      {'role': 'user', 'content': user},
    ];
  }

  String formatPersonaJson(Persona persona) {
    return const JsonEncoder.withIndent('  ').convert({
      'name': persona.name,
      'description': persona.description,
      'appearance': persona.appearance,
      'personality': persona.personality,
      'background': persona.background,
      'goals': persona.goals,
    });
  }

  /// Preserve-and-merge update for an existing player persona.
  List<Map<String, String>> buildPersonaUpdateMessages({
    required List<ChatMessage> conversation,
    required Persona existing,
    String guidanceNote = CollaboratorSettings.defaultGuidanceNote,
    Lorebook? sourceLorebook,
    WorkshopSourceContext? importedSource,
    String worldSummary = '',
    List<String> canonPinMessageIds = const [],
  }) {
    final guidance = guidanceNote.trim().isEmpty
        ? CollaboratorSettings.defaultGuidanceNote
        : guidanceNote.trim();
    final name = existing.name.trim().isEmpty ? 'User' : existing.name.trim();
    final currentPersona = formatPersonaJson(existing);

    final system =
        '''
You update ONE existing user persona JSON object for the Anima roleplay app.
This is who the human player is — not an AI character.

Guidance note (follow closely):
$guidance

Target persona: $name

Preserve-and-merge rules:
- Keep established facts from CURRENT PERSONA unless the workshop clearly revises them.
- Merge in new details from the workshop conversation, imported source, and lorebook.
- Do not invent contradictions or erase identity the persona already states.
- Keep the same person (same name unless the workshop explicitly renames them).

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
- Do not sanitize or moralize.
'''
            .trim();

    final source = formatLorebookContext(sourceLorebook);
    final imported = _importedBlock(importedSource);
    final summaryBlock = worldSummary.trim().isEmpty
        ? ''
        : 'World summary:\n${worldSummary.trim()}\n\n';
    final canonBlock = formatCanonPins(conversation, canonPinMessageIds);
    final user =
        '''
CURRENT PERSONA (preserve established facts; merge workshop updates):
$currentPersona

$imported$summaryBlock${canonBlock.isEmpty ? '' : '$canonBlock\n'}${source.isEmpty ? '' : '''
Linked lorebook:

$source

'''}Update the persona for "$name" using the current persona plus workshop conversation:

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
    String buildPromptNote = CharacterBuildSettings.defaultPromptNote,
    Lorebook? sourceLorebook,
    WorkshopSourceContext? importedSource,
    List<Character> existingCast = const [],
  }) {
    final guidance = buildPromptNote.trim().isEmpty
        ? CharacterBuildSettings.defaultPromptNote
        : buildPromptNote.trim();

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
- Characters who already have cards in the workshop cast list below

Output rules:
- Reply with ONLY a single JSON object. No markdown fences. No preamble.
- Do NOT ask questions or offer to draft later — output the character list now.
- Use REAL names from the conversation below — never copy schema placeholder text.
- Example shape (fill with actual people from the transcript; names are illustrative only):
$characterListJsonExample
- Use distinct names; do not duplicate the same person under aliases.
- If none qualify, return {"characters":[]}.
'''
            .trim();

    final source = formatLorebookContext(sourceLorebook);
    final imported = _importedBlock(importedSource);
    final castBlock = formatWorkshopCastForLoreExport(existingCast);
    final user =
        '''
$imported${castBlock.isEmpty ? '' : '$castBlock\n'}${source.isEmpty ? '' : '''
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

  /// Characters in [participants] first, then the rest alphabetically.
  List<Character> prioritizeCharactersForChatUpdate({
    required List<Character> allCharacters,
    required List<Character> participants,
  }) {
    final inChatIds = {for (final c in participants) c.id};
    final inChat = <Character>[];
    final rest = <Character>[];
    for (final character in allCharacters) {
      if (inChatIds.contains(character.id)) {
        inChat.add(character);
      } else {
        rest.add(character);
      }
    }
    int byName(Character a, Character b) =>
        a.name.toLowerCase().compareTo(b.name.toLowerCase());
    inChat.sort(byName);
    rest.sort(byName);
    return [...inChat, ...rest];
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

  /// Parse a consistency-fix draft — merges all editable card text fields.
  Character parseCharacterConsistencyFixJson(
    String raw, {
    required Character original,
  }) {
    final map = _extractJsonObject(
      raw,
      emptyMessage: 'The AI returned an empty character card.',
      missingMessage:
          'Could not find character card JSON in the AI reply. Try again.',
      notObjectMessage: 'Character card JSON must be an object.',
    );
    final parsed = _cardCodec.fromCardMap(map, preferredId: original.id);

    String pick(String next, String previous) {
      final trimmed = next.trim();
      return trimmed.isEmpty ? previous : trimmed;
    }

    return consolidateSlimCharacterFields(
      Character(
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
        tags: parsed.tags.isEmpty ? original.tags : parsed.tags,
        creatorNotes: original.creatorNotes,
        creator: original.creator,
        characterVersion: original.characterVersion,
        characterBook: original.characterBook,
        extensions: original.extensions,
        avatarFileName: original.avatarFileName,
      ),
    );
  }

  /// Parse a lorebook consistency fix, preserving book settings when omitted.
  Lorebook parseLorebookConsistencyFixJson(
    String raw, {
    required Lorebook original,
  }) {
    final fixed = parseLorebookJson(raw);
    return Lorebook(
      name: fixed.name.trim().isEmpty ? original.name : fixed.name,
      description: fixed.description.trim().isEmpty
          ? original.description
          : fixed.description,
      scanDepth: fixed.scanDepth,
      tokenBudget: fixed.tokenBudget,
      recursiveScanning: fixed.recursiveScanning,
      entries: fixed.entries,
      extensions: fixed.extensions.isEmpty ? original.extensions : fixed.extensions,
    );
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

    return consolidateSlimCharacterFields(
      Character(
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
      ),
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
    bool reviseExisting = true,
    OpeningSceneLength length = OpeningSceneLength.medium,
  }) {
    final guidance = guidanceNote.trim().isEmpty
        ? CollaboratorSettings.defaultGuidanceNote
        : guidanceNote.trim();
    final existing = reviseExisting ? existingOpeningScene.trim() : '';

    final revisionRule = existing.isEmpty
        ? '- Write a NEW opening scene from scratch using the conversation and '
            'source material. Do not copy wording from any prior saved scene '
            'unless the user explicitly asked to keep it.'
        : '- Revise the existing opening scene below when the user asked for changes.';

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
- ${length.promptHint}
- Preserve established facts. Do not sanitize or moralize.
$revisionRule
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
  Lorebook parseLorebookJson(
    String raw, {
    List<Character> workshopCast = const [],
  }) {
    final map = _extractJsonObject(
      raw,
      emptyMessage: 'The AI returned an empty lorebook.',
      missingMessage: lorebookJsonMissingMessage(raw),
      notObjectMessage: 'Lorebook JSON must be an object.',
    );
    var book = Lorebook.parseImport(map);
    if (book.entries.isEmpty) {
      throw const FormatException(
        'The AI returned a lorebook with no entries. Try chatting a bit more, then Create again.',
      );
    }
    book = filterCastBioDuplicates(book, workshopCast: workshopCast);
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
      'Your previous reply was not valid character-list JSON, or it used '
      'placeholder schema text instead of real names from the conversation. '
      'Reply with ONLY one JSON object listing actual characters: '
      '{"characters":[{"name":"Real Name","summary":"short role sentence"}]} '
      'No markdown fences, no preamble, no questions.';

  static bool isTemplateCharacterCandidate(String name, String summary) {
    final n = name.trim().toLowerCase();
    final s = summary.trim().toLowerCase();
    if (n.isEmpty) return true;
    if (n == 'exact character name' ||
        n == 'character name' ||
        n == 'name' ||
        n == 'example name') {
      return true;
    }
    if (s.contains('one short sentence') ||
        s.contains('who they are / role') ||
        s == 'short role sentence') {
      return true;
    }
    return false;
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
  var rawCount = 0;
    for (final item in listRaw) {
      if (item is! Map) continue;
      rawCount++;
      final data = Map<String, dynamic>.from(item);
      final name = '${data['name'] ?? ''}'.trim();
      if (name.isEmpty) continue;
      final summary =
          '${data['summary'] ?? data['description'] ?? ''}'.trim();
      if (isTemplateCharacterCandidate(name, summary)) continue;
      final key = name.toLowerCase();
      if (seen.contains(key)) continue;
      seen.add(key);
      out.add(
        WorkshopCharacterCandidate(
          name: name,
          summary: summary,
        ),
      );
    }
    if (out.isEmpty && rawCount > 0) {
      throw const FormatException(
        'The AI returned placeholder text instead of real character names. '
        'Try Create characters again.',
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
    return consolidateSlimCharacterFields(cleaned);
  }

  /// Removes sentences from personality that duplicate description (post-parse).
  Character consolidateSlimCharacterFields(Character character) {
    final desc = character.description.trim();
    final pers = character.personality.trim();
    if (desc.isEmpty || pers.isEmpty) return character;

    final descNorm = _normalizeOverlapText(desc);
    final kept = <String>[];
    for (final sentence in _splitIntoSentences(pers)) {
      final trimmed = sentence.trim();
      if (trimmed.isEmpty) continue;
      final sentNorm = _normalizeOverlapText(trimmed);
      if (sentNorm.length >= 12) {
        if (descNorm.contains(sentNorm)) continue;
        if (_wordOverlapRatio(sentNorm, descNorm) >= 0.72) continue;
      }
      kept.add(trimmed);
    }

    if (kept.isEmpty) return character;
    final merged = kept.join(' ').trim();
    if (merged == pers) return character;
    return character.copyWith(personality: merged);
  }

  /// Drops lore entries that only repeat workshop cast character-card bios.
  Lorebook filterCastBioDuplicates(
    Lorebook book, {
    List<Character> workshopCast = const [],
  }) {
    if (workshopCast.isEmpty) return book;
    final castNames = {
      for (final c in workshopCast)
        if (c.name.trim().isNotEmpty) c.name.trim().toLowerCase(),
    };
    if (castNames.isEmpty) return book;

    final filtered = [
      for (final entry in book.entries)
        if (!_entryDuplicatesCastCard(entry, workshopCast, castNames)) entry,
    ];
    if (filtered.isEmpty || filtered.length == book.entries.length) {
      return book;
    }
    return book.copyWith(entries: filtered);
  }

  bool _entryDuplicatesCastCard(
    LorebookEntry entry,
    List<Character> cast,
    Set<String> castNames,
  ) {
    if (entry.constant) return false;
    final keyList = [
      ...entry.keys,
      ...entry.secondaryKeys,
    ].map((k) => k.trim().toLowerCase()).where((k) => k.isNotEmpty).toList();
    if (keyList.isEmpty) return false;
    if (!keyList.every(castNames.contains)) return false;

    final content = entry.content.trim();
    if (content.length < 80) return false;

    final contentNorm = _normalizeOverlapText(content);
    for (final character in cast) {
      final cardText = _normalizeOverlapText(
        '${character.description} ${character.personality}',
      );
      if (cardText.isEmpty) continue;
      if (_wordOverlapRatio(contentNorm, cardText) > 0.45) return true;
    }
    return false;
  }

  static String _normalizeOverlapText(String text) {
    return text.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static List<String> _splitIntoSentences(String text) {
    return text.split(RegExp(r'(?<=[.!?])\s+|\n+'));
  }

  static double _wordOverlapRatio(String a, String b) {
    final wordsA = a.split(RegExp(r'\s+')).where((w) => w.length > 2).toSet();
    if (wordsA.isEmpty) return 0;
    final wordsB = b.split(RegExp(r'\s+')).where((w) => w.length > 2).toSet();
    if (wordsB.isEmpty) return 0;
    final overlap = wordsA.where(wordsB.contains).length;
    return overlap / wordsA.length;
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

  /// Parse persona update draft, preserving id, avatar, and workshop link.
  Persona parsePersonaUpdateJson(String raw, {required Persona original}) {
    final parsed = parsePersonaJson(
      raw,
      preferredId: original.id,
      fallbackName: original.name,
    );
    String pick(String next, String prev) =>
        next.trim().isNotEmpty ? next.trim() : prev.trim();

    return Persona(
      id: original.id,
      name: pick(parsed.name, original.name),
      description: pick(parsed.description, original.description),
      appearance: pick(parsed.appearance, original.appearance),
      personality: pick(parsed.personality, original.personality),
      background: pick(parsed.background, original.background),
      goals: pick(parsed.goals, original.goals),
      avatarFileName: original.avatarFileName,
      sourceWorkshopId: original.sourceWorkshopId,
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

  List<Map<String, String>> buildWorldSummaryMessages({
    required List<ChatMessage> conversation,
    String existingSummary = '',
    String guidanceNote = CollaboratorSettings.defaultGuidanceNote,
    WorkshopSourceContext? importedSource,
    Lorebook? sourceLorebook,
    List<String> canonPinMessageIds = const [],
    List<ChatMessage>? chunk,
  }) {
    final guidance = guidanceNote.trim().isEmpty
        ? CollaboratorSettings.defaultGuidanceNote
        : guidanceNote.trim();
    final system =
        '''
You maintain a concise WORLD SUMMARY for a Creation Center workshop.
Output plain prose only (no JSON). Revise stale facts, keep key names and facts.
Max ~800 words. Do not moralize.
Guidance: $guidance
'''
            .trim();
    final imported = _importedBlock(importedSource);
    final canon = formatCanonPins(conversation, canonPinMessageIds);
    final transcriptSource = chunk ?? conversation;
    final transcriptLabel = chunk != null
        ? 'New workshop segment to fold in:'
        : 'Workshop transcript:';
    final user =
        '''
$imported
${existingSummary.trim().isEmpty ? '' : 'Current summary:\n${existingSummary.trim()}\n\n'}
${canon.isEmpty ? '' : '$canon\n'}
$transcriptLabel
${formatTranscript(transcriptSource)}

Write an updated world summary.
'''
            .trim();
    return [
      {'role': 'system', 'content': system},
      {'role': 'user', 'content': user},
    ];
  }

  /// Revise the last workshop assistant bubble in place from a short user correction.
  List<Map<String, String>> buildApplyCorrectionMessages({
    required String assistantReply,
    required String correctionNote,
  }) {
    final original = assistantReply.trim();
    final note = correctionNote.trim();
    if (original.isEmpty || note.isEmpty) {
      throw ArgumentError('Need both the assistant reply and a correction note.');
    }
    return [
      {
        'role': 'system',
        'content':
            'You revise ONE Creation Center workshop assistant message in place. '
            'The user likes almost everything in the original. Apply ONLY their '
            'correction. Output the FULL revised message (complete replacement text) '
            'with the same structure, sections, and bullets as the original — but '
            'with the correction applied. Do not add new plot facts unless the '
            'correction requires them. Do not add preamble or meta commentary. '
            'Keep length close to the original.',
      },
      {
        'role': 'user',
        'content':
            '''
Original assistant message:
$original

User correction (apply this; keep everything else unchanged):
$note

Output the full revised assistant message only.
'''
                .trim(),
      },
    ];
  }

  List<Map<String, String>> buildWorldOverviewMessages({
    required List<ChatMessage> conversation,
    String worldSummary = '',
    WorkshopSourceContext? importedSource,
    Lorebook? sourceLorebook,
    List<String> canonPinMessageIds = const [],
  }) {
    final system =
        '''
You write a one-page WORLD OVERVIEW (markdown) for a roleplay setting.
Sections: Setting, Tone, Rules (magic/tech), Factions, Key locations, Timeline, Cast.
Plain markdown only. No JSON. ~600-1200 words max.
'''
            .trim();
    final imported = _importedBlock(importedSource);
    final source = formatLorebookContext(sourceLorebook);
    final canon = formatCanonPins(conversation, canonPinMessageIds);
    final user =
        '''
$imported
${worldSummary.trim().isEmpty ? '' : 'Summary:\n${worldSummary.trim()}\n\n'}
${source.isEmpty ? '' : 'Lorebook:\n$source\n\n'}
${canon.isEmpty ? '' : '$canon\n'}
Transcript:
${formatTranscript(conversation)}

Generate the world overview document.
'''
            .trim();
    return [
      {'role': 'system', 'content': system},
      {'role': 'user', 'content': user},
    ];
  }

  List<Map<String, String>> buildGlossaryExportMessages({
    required List<ChatMessage> conversation,
    WorkshopSourceContext? importedSource,
    Lorebook? sourceLorebook,
    List<String> canonPinMessageIds = const [],
  }) {
    final system =
        '''
Extract glossary terms from a world-building workshop. Reply with ONLY JSON:
{
  "entries": [
    {"term": "Name", "definition": "short definition", "keywords": ["alias1"]}
  ]
}
At least 3 entries when possible. keywords are trigger words for lorebook entries.
'''
            .trim();
    final imported = _importedBlock(importedSource);
    final canon = formatCanonPins(conversation, canonPinMessageIds);
    final user =
        '''
$imported
${canon.isEmpty ? '' : '$canon\n'}
${formatTranscript(conversation)}
'''
            .trim();
    return [
      {'role': 'system', 'content': system},
      {'role': 'user', 'content': user},
    ];
  }

  List<GlossaryEntry> parseGlossaryJson(String raw) {
    final map = _extractJsonObject(
      raw,
      emptyMessage: 'Glossary response was empty.',
      missingMessage: 'Could not find glossary JSON.',
      notObjectMessage: 'Glossary JSON must be an object.',
    );
    final rawEntries = map['entries'];
    if (rawEntries is! List) return const [];
    final out = <GlossaryEntry>[];
    for (final item in rawEntries) {
      if (item is! Map) continue;
      final term = '${item['term'] ?? ''}'.trim();
      if (term.isEmpty) continue;
      final keywords = <String>[];
      final rawKeys = item['keywords'];
      if (rawKeys is List) {
        for (final k in rawKeys) {
          final s = '$k'.trim();
          if (s.isNotEmpty) keywords.add(s);
        }
      }
      out.add(
        GlossaryEntry(
          term: term,
          definition: '${item['definition'] ?? ''}'.trim(),
          keywords: keywords.isEmpty ? [term] : keywords,
        ),
      );
    }
    return out;
  }

  List<Map<String, String>> buildGreetingsExportMessages({
    required List<ChatMessage> conversation,
    required String characterName,
    WorkshopSourceContext? importedSource,
    Lorebook? sourceLorebook,
    int count = 3,
  }) {
    final name = characterName.trim();
    final system =
        '''
Generate $count alternate opening greetings for character "$name" in this world.
Reply with ONLY JSON: {"greetings": ["line1", "line2", ...]}
Use *actions* and "dialogue" RP style. Each greeting is a full opening message.
'''
            .trim();
    final imported = _importedBlock(importedSource);
    final user =
        '''
$imported
Character: $name
${formatTranscript(conversation)}
'''
            .trim();
    return [
      {'role': 'system', 'content': system},
      {'role': 'user', 'content': user},
    ];
  }

  List<String> parseGreetingsJson(String raw) {
    final map = _extractJsonObject(
      raw,
      emptyMessage: 'Greetings response was empty.',
      missingMessage: 'Could not find greetings JSON.',
      notObjectMessage: 'Greetings JSON must be an object.',
    );
    final rawG = map['greetings'];
    if (rawG is! List) return const [];
    return [
      for (final g in rawG)
        if ('$g'.trim().isNotEmpty) '$g'.trim(),
    ];
  }

  List<Map<String, String>> buildSheetsExtractMessages({
    required List<ChatMessage> conversation,
    WorkshopSourceContext? importedSource,
  }) {
    final system =
        '''
Extract locations and relationships from a workshop. Reply with ONLY JSON:
{
  "locations": [{"name": "Place", "description": "vibe"}],
  "relationships": [{"fromName": "A", "toName": "B", "dynamic": "allies"}]
}
'''
            .trim();
    final imported = _importedBlock(importedSource);
    final user = '$imported\n${formatTranscript(conversation)}';
    return [
      {'role': 'system', 'content': system},
      {'role': 'user', 'content': user},
    ];
  }

  (List<WorkshopLocation>, List<WorkshopRelationship>) parseSheetsJson(
    String raw,
  ) {
    final map = _extractJsonObject(
      raw,
      emptyMessage: 'Sheets response was empty.',
      missingMessage: 'Could not find sheets JSON.',
      notObjectMessage: 'Sheets JSON must be an object.',
    );
    final locations = <WorkshopLocation>[];
    final rawLocs = map['locations'];
    if (rawLocs is List) {
      for (final item in rawLocs) {
        if (item is Map) {
          locations.add(
            WorkshopLocation.fromJson(Map<String, dynamic>.from(item)),
          );
        }
      }
    }
    final relationships = <WorkshopRelationship>[];
    final rawRels = map['relationships'];
    if (rawRels is List) {
      for (final item in rawRels) {
        if (item is Map) {
          relationships.add(
            WorkshopRelationship.fromJson(Map<String, dynamic>.from(item)),
          );
        }
      }
    }
    return (locations, relationships);
  }

  List<Map<String, String>> buildPreExportChecklistMessages({
    required List<ChatMessage> conversation,
    WorkshopSourceContext? importedSource,
    Lorebook? sourceLorebook,
    String worldSummary = '',
    List<String> canonPinMessageIds = const [],
  }) {
    final system =
        '''
Audit a workshop before lorebook export. Reply with ONLY JSON:
{"items": ["short actionable note", ...]}
List gaps: missing locations, unnamed factions, thin world rules, contradictions,
stale lorebook vs chat, lore entries that duplicate character-card bios for cast.
Max 8 items. Empty list if ready.
'''
            .trim();
    final imported = _importedBlock(importedSource);
    final source = formatLorebookContext(sourceLorebook);
    final canon = formatCanonPins(conversation, canonPinMessageIds);
    final user =
        '''
$imported
${worldSummary.trim().isEmpty ? '' : 'Summary:\n${worldSummary.trim()}\n\n'}
${source.isEmpty ? '' : 'Lorebook:\n$source\n\n'}
${canon.isEmpty ? '' : '$canon\n'}
${formatTranscript(conversation)}
'''
            .trim();
    return [
      {'role': 'system', 'content': system},
      {'role': 'user', 'content': user},
    ];
  }

  List<String> parseChecklistJson(String raw) {
    final map = _extractJsonObject(
      raw,
      emptyMessage: 'Checklist response was empty.',
      missingMessage: 'Could not find checklist JSON.',
      notObjectMessage: 'Checklist JSON must be an object.',
    );
    final rawItems = map['items'];
    if (rawItems is! List) return const [];
    return [
      for (final item in rawItems)
        if ('$item'.trim().isNotEmpty) '$item'.trim(),
    ];
  }

  List<Map<String, String>> buildSceneIdeasMessages({
    required List<ChatMessage> conversation,
    int count = 3,
    WorkshopSourceContext? importedSource,
  }) {
    final system =
        '''
Suggest $count mid-story SCENE IDEAS (not opening scenes). Reply with ONLY JSON:
{"scenes": [{"title": "short label", "text": "2-4 sentences of setup"}]}
'''
            .trim();
    final imported = _importedBlock(importedSource);
    final user = '$imported\n${formatTranscript(conversation)}';
    return [
      {'role': 'system', 'content': system},
      {'role': 'user', 'content': user},
    ];
  }

  List<WorkshopSceneIdea> parseSceneIdeasJson(String raw) {
    final map = _extractJsonObject(
      raw,
      emptyMessage: 'Scene ideas response was empty.',
      missingMessage: 'Could not find scene ideas JSON.',
      notObjectMessage: 'Scene ideas JSON must be an object.',
    );
    final rawScenes = map['scenes'];
    if (rawScenes is! List) return const [];
    final out = <WorkshopSceneIdea>[];
    for (final item in rawScenes) {
      if (item is! Map) continue;
      final title = '${item['title'] ?? ''}'.trim();
      final text = '${item['text'] ?? ''}'.trim();
      if (title.isEmpty && text.isEmpty) continue;
      out.add(
        WorkshopSceneIdea(
          id: WorkshopSceneIdea.newId(),
          title: title.isEmpty ? 'Scene idea' : title,
          text: text,
          updatedAt: DateTime.now(),
        ),
      );
    }
    return out;
  }
}
