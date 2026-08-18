import '../models/chat_message.dart';
import 'presence_service.dart';
import 'settings_service.dart';

/// Builds prompts for the universal chat Narrator and formats narrator lines
/// for the roleplay API payload.
class NarratorService {
  const NarratorService({this.presence = const PresenceService()});

  final PresenceService presence;

  static const defaultNote = CollaboratorSettings.defaultNarratorNote;

  /// Messages that define the *current* scene for narrator generation.
  static const sceneLookback = 10;

  /// Older lines included only as light background (not who is "present").
  static const backgroundLookback = 6;

  /// Narrator lines should stay short; uncapped max_tokens causes tail degeneration.
  static const generateMaxTokens = 420;

  /// Tighter sampling for one-shot narrator generation.
  static SamplingSettings generateSampling(SamplingSettings base) {
    final capped = base.maxTokens == null || base.maxTokens! > generateMaxTokens
        ? generateMaxTokens
        : base.maxTokens!;
    return base.copyWith(
      temperature: base.temperature > 0.62 ? 0.62 : base.temperature,
      maxTokens: capped,
      frequencyPenalty: base.frequencyPenalty < 0.25 ? 0.35 : base.frequencyPenalty,
      presencePenalty: base.presencePenalty < 0.1 ? 0.15 : base.presencePenalty,
      repetitionPenalty: base.repetitionPenalty ?? 1.08,
    );
  }

  /// Strips prompt echo, instruction leaks, and repetition loops from model output.
  String cleanGeneratedOutput(String raw) {
    var text = raw.trim();
    if (text.isEmpty) return text;

    text = _cutInstructionLeak(text);
    text = _trimRepetitionLoops(text);
    text = _trimCharCap(text, 1600);
    return text.trim();
  }

  /// How narrator lines appear in the live prompt (chronological history).
  ///
  /// Prefer [historyBlockFor] + [activeSceneLawBlock] so the latest narrator
  /// is injected as mandatory scene law at the end of the stack.
  String formatForPrompt({
    required String text,
    required String userName,
    required String charName,
    bool isGroup = false,
  }) =>
      formatActiveSceneLaw(
        text: text,
        userName: userName,
        charName: charName,
        isGroup: isGroup,
      );

  /// Mandatory scene law — mirrors Director priority (placed late in prompt).
  ///
  /// For group chats prefer [formatGroupSceneLaw] with a [physicallyPresent] set.
  String formatActiveSceneLaw({
    required String text,
    required String userName,
    required String charName,
    bool isGroup = false,
    String speakingAsName = '',
    bool narratorAlreadyAddressed = false,
    bool sceneContinuedInChat = false,
    Iterable<String> castNames = const [],
  }) {
    final rawBody = text.trim();
    if (rawBody.isEmpty) return '';
    final speaker = speakingAsName.trim().isEmpty ? charName.trim() : speakingAsName.trim();
    final body = presence.sanitizeStagingTextForCharacter(
      text: rawBody,
      focusCharacterName: speaker,
      castNames: castNames,
    );
    if (body.isEmpty) return '';
    final user = userName.trim().isEmpty ? 'User' : userName.trim();
    final char = charName.trim().isEmpty ? 'Character' : charName.trim();
    final cast = isGroup
        ? 'Every character in this scene'
        : char;
    final continueFromChat = narratorAlreadyAddressed || sceneContinuedInChat;
    final namedInBeat = _narratorNamesCharacter(body, speaker);
    final beatLine = continueFromChat
        ? 'The scene has already moved on — continue from the latest chat '
            'messages. Do NOT re-walk-in, re-arrive, or replay entrances or '
            'first reactions that already happened in chat.\n'
        : namedInBeat
            ? 'You are $speaker — this reply MUST enact the narrator beat from your '
                'perspective (your entrance, what you see, your first reaction). '
                'Do NOT behave as if you were already doing something unrelated '
                '(phone, script, reading, etc.) unless the narrator says so.\n'
            : '';

    return '''
PLAYER NARRATOR — SCENE LAW (MANDATORY):
$body

${beatLine}This is authoritative scene fact from the player — NOT optional flavor, NOT a suggestion, NOT mood you may ignore.
$cast and $user (when present) MUST treat location and who is present as true.
Secrets explicitly marked as unknown to you are NOT your knowledge — never speak them or act as if you witnessed them.
${continueFromChat ? 'Honor the narrator as ongoing scene backdrop only — new actions come from chat history, not a fresh entrance or surprise reaction.' : 'React and reply as if these facts already happened. Do not ignore, soften, reinterpret, or contradict this narrator beat.'}
Do not speak as the Narrator. Do not repeat this passage verbatim or attribute it to $user or $char as dialogue.
'''
        .trim();
  }

  /// Group scene law: everyone knows location/situation; only [physicallyPresent]
  /// characters heard private dialogue in this scene.
  String formatGroupSceneLaw({
    required String text,
    required String userName,
    required String speakingAsName,
    required Set<String> physicallyPresent,
    required bool inScene,
    bool narratorAlreadyAddressed = false,
    Set<String> departedPresent = const {},
    Set<String> narratorBeatFor = const {},
    bool userSpokeAfterNarratorBeat = false,
    bool sceneContinuedInChat = false,
    Set<String> castWhoContinuedScene = const {},
    Iterable<String> castNames = const [],
  }) {
    final rawBody = text.trim();
    if (rawBody.isEmpty) return '';
    final body = presence.sanitizeStagingTextForCharacter(
      text: rawBody,
      focusCharacterName: speakingAsName,
      castNames: castNames,
    );
    if (body.isEmpty) return '';
    final user = userName.trim().isEmpty ? 'User' : userName.trim();
    final speaker = speakingAsName.trim().isEmpty
        ? 'Character'
        : speakingAsName.trim();
    final continueFromChat = narratorAlreadyAddressed || sceneContinuedInChat;

    final presentLine = physicallyPresent.isEmpty
        ? 'Physically present: (see narrator text)'
        : 'Physically present: ${physicallyPresent.join(', ')}';

    final absentLine = departedPresent.isEmpty
        ? ''
        : 'NOT physically present (left / away): ${departedPresent.join(', ')}';

    final enactedBeatOwners = narratorBeatFor
        .where(
          (name) => castWhoContinuedScene.any((who) => _namesMatch(who, name)),
        )
        .toList();

    final beatOwnerLine = !continueFromChat && narratorBeatFor.isNotEmpty
        ? speakerInPresentSet(speaker, narratorBeatFor)
            ? 'You are $speaker — this narrator beat is YOUR action. Enact it '
                'exactly; other cast must not steal it.\n'
            : userSpokeAfterNarratorBeat &&
                    narratorBeatFor.any(
                      (name) => _namesMatch(name, user),
                    )
                ? '$user already spoke after this narrator beat — respond to '
                    'their last line. Do NOT wait for them to arrive or speak '
                    'again.\n'
                : 'Active narrator beat belongs to: ${narratorBeatFor.join(', ')}. '
                    'You are $speaker — do NOT perform their action (walking in, '
                    'coming downstairs, leaving, etc.). React only from your own '
                    'perspective.\n'
        : enactedBeatOwners.isNotEmpty &&
                !speakerInPresentSet(speaker, enactedBeatOwners.toSet())
            ? '${enactedBeatOwners.join(', ')} already enacted this narrator '
                'beat in chat. You ($speaker) must answer their last line — do '
                'NOT act surprised by their arrival, do NOT re-hug or re-greet '
                'them as if they just walked in.\n'
            : sceneContinuedInChat && castWhoContinuedScene.isNotEmpty
                ? 'Chat already continued after this narrator beat '
                    '(${castWhoContinuedScene.join(', ')} spoke). You ($speaker) '
                    'must follow what was actually said — do NOT rewind to the '
                    'narrator moment as if nothing happened yet.\n'
                : sceneContinuedInChat && userSpokeAfterNarratorBeat
                    ? '$user already spoke after this narrator beat — respond '
                        'to their last line. Do NOT replay the narrator entrance.\n'
                    : '';

    final namedInBeat = _narratorNamesCharacter(body, speaker);
    final beatLine = continueFromChat
        ? 'The scene has already moved on — continue from the latest chat '
            'messages. Do NOT re-walk-in, re-arrive, or replay entrances or '
            'first reactions that already happened in chat.\n'
        : namedInBeat && inScene && narratorBeatFor.isEmpty
            ? 'You are $speaker — enact your entrance / first reaction exactly as '
                'the narrator describes. Do NOT default to unrelated activities '
                '(phone, script, reading, etc.) unless the narrator says so.\n'
            : '';

    final roleLine = continueFromChat
        ? 'You ($speaker) are in this scene. The narrator still defines location '
            'and who is physically present — honor that backdrop. Your next '
            'line must follow what just happened in chat, not restart the beat.'
        : inScene
            ? 'You ($speaker) ARE physically in this scene. React from inside it — '
                'positions, sights, and beats are immediate.'
            : 'You ($speaker) are NOT physically in this scene yet. You still know '
                'the location and situation below so you can enter naturally when '
                'brought in — but you did NOT hear private dialogue from this scene. '
                'Do not invent a conflicting location or unrelated activity.';

    return '''
PLAYER NARRATOR — SCENE LAW (MANDATORY):
$body

$presentLine
${absentLine.isEmpty ? '' : '$absentLine\n'}$roleLine

$beatOwnerLine${beatLine}ALL cast treat the narrator as authoritative scene fact for location and who is physically present — NOT a suggestion.
Location, who is physically present, and what is happening in the room are law for the story.
Secrets or events explicitly marked as unknown to you ($speaker) in the narrator text are NOT your knowledge — never speak them or react as if you heard them.
${departedPresent.isNotEmpty ? 'Characters who left are GONE — do not speak to them as if they are still in the room.\n' : ''}${continueFromChat ? 'Do not replay entrances, hugs, or first reactions already shown in chat.' : 'Characters physically present MUST react as if these facts already happened.'}
Off-screen characters know only the sanitized scene brief below — not private dialogue or secrets from this scene.
Do not speak as the Narrator. Do not repeat this passage verbatim.
Do not attribute narrator prose to $user or cast as dialogue.
'''
        .trim();
  }

  bool speakerInPresentSet(String speakerName, Set<String> physicallyPresent) {
    final focus = speakerName.trim().toLowerCase();
    if (focus.isEmpty) return false;
    if (physicallyPresent.contains(focus)) return true;
    final first = focus.split(RegExp(r'\s+')).first;
    for (final name in physicallyPresent) {
      if (name == focus) return true;
      final parts = name.split(RegExp(r'\s+'));
      if (parts.isNotEmpty && parts.first == first && first.length >= 3) {
        return true;
      }
    }
    return false;
  }

  /// Whether [characterName] appears in narrator text (first or full name).
  bool _narratorNamesCharacter(String text, String characterName) {
    final lower = text.toLowerCase();
    for (final token in _nameTokens(characterName)) {
      if (RegExp(
        '\\b${RegExp.escape(token)}\\b',
        caseSensitive: false,
      ).hasMatch(lower)) {
        return true;
      }
    }
    return false;
  }

  Iterable<String> _nameTokens(String name) sync* {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    yield trimmed.toLowerCase();
    final parts = trimmed.split(RegExp(r'\s+'));
    if (parts.length > 1) {
      final first = parts.first.toLowerCase();
      if (first.length >= 3) yield first;
    }
  }

  /// Older narrator beats already addressed — weak context only.
  String formatHistoricalNote({
    required String text,
    String focusCharacterName = '',
    Iterable<String> castNames = const [],
  }) {
    var body = text.trim();
    if (body.isEmpty) return '';
    if (focusCharacterName.trim().isNotEmpty) {
      body = presence.sanitizeStagingTextForCharacter(
        text: body,
        focusCharacterName: focusCharacterName,
        castNames: castNames,
      );
      if (body.isEmpty) return '';
    }
    return '''
Earlier narrator beat (superseded by any newer narrator line — do not contradict the latest narrator):
$body
'''
        .trim();
  }

  /// Most recent narrator message id before [endExclusive], if any.
  String? latestNarratorId(
    List<ChatMessage> messages, {
    int? endExclusive,
  }) {
    final end = (endExclusive ?? messages.length).clamp(0, messages.length);
    for (var i = end - 1; i >= 0; i--) {
      final message = messages[i];
      if (message.isNarrator && message.text.trim().isNotEmpty) {
        return message.id;
      }
    }
    return null;
  }

  /// True when [speakerName] already sent a line after [narratorId].
  ///
  /// Skips [excludeMessageIndex] (the bubble currently being written/regenerated).
  bool characterAlreadyRepliedSinceNarrator({
    required List<ChatMessage> messages,
    required String narratorId,
    required String speakerName,
    int? endExclusive,
    int? excludeMessageIndex,
  }) {
    var narratorIndex = -1;
    for (var i = 0; i < messages.length; i++) {
      if (messages[i].id == narratorId) {
        narratorIndex = i;
        break;
      }
    }
    if (narratorIndex < 0) return false;

    final end = (endExclusive ?? messages.length).clamp(0, messages.length);
    for (var i = narratorIndex + 1; i < end; i++) {
      if (excludeMessageIndex != null && i == excludeMessageIndex) {
        final excluded = messages[i];
        if (_messageHasSpeakerContent(excluded, speakerName)) return true;
        continue;
      }
      if (_messageIsFromSpeaker(messages[i], speakerName)) return true;
    }
    return false;
  }

  /// True when the player sent a line after [narratorId] (before [endExclusive]).
  bool userSpokeAfterNarrator({
    required List<ChatMessage> messages,
    required String narratorId,
    int? endExclusive,
  }) {
    var narratorIndex = -1;
    for (var i = 0; i < messages.length; i++) {
      if (messages[i].id == narratorId) {
        narratorIndex = i;
        break;
      }
    }
    if (narratorIndex < 0) return false;

    final end = (endExclusive ?? messages.length).clamp(0, messages.length);
    for (var i = narratorIndex + 1; i < end; i++) {
      final message = messages[i];
      if (message.isUser && message.text.trim().isNotEmpty) return true;
    }
    return false;
  }

  /// Other cast (or the player) already spoke after [narratorId] — the beat
  /// advanced in chat and later speakers must not rewind to the narrator moment.
  NarratorSceneContinuation sceneContinuedAfterNarrator({
    required List<ChatMessage> messages,
    required String narratorId,
    required String speakerName,
    int? endExclusive,
    int? excludeMessageIndex,
  }) {
    var narratorIndex = -1;
    for (var i = 0; i < messages.length; i++) {
      if (messages[i].id == narratorId) {
        narratorIndex = i;
        break;
      }
    }
    if (narratorIndex < 0) {
      return const NarratorSceneContinuation(
        continued: false,
        castWhoSpoke: {},
        userSpoke: false,
      );
    }

    final castWhoSpoke = <String>{};
    var userSpoke = false;
    final end = (endExclusive ?? messages.length).clamp(0, messages.length);
    for (var i = narratorIndex + 1; i < end; i++) {
      if (excludeMessageIndex != null && i == excludeMessageIndex) continue;
      final message = messages[i];
      if (message.isUser) {
        if (message.text.trim().isNotEmpty) userSpoke = true;
        continue;
      }
      if (message.isGroupBeat && message.beatLines != null) {
        for (final line in message.beatLines!) {
          final name = line.speakerName.trim();
          if (name.isEmpty) continue;
          if (!_namesMatch(name, speakerName)) castWhoSpoke.add(name);
        }
        continue;
      }
      if (!message.isAssistant || message.text.trim().isEmpty) continue;
      final named = message.speakerName?.trim();
      if (named == null || named.isEmpty) continue;
      if (!_namesMatch(named, speakerName)) castWhoSpoke.add(named);
    }

    return NarratorSceneContinuation(
      continued: userSpoke || castWhoSpoke.isNotEmpty,
      castWhoSpoke: castWhoSpoke,
      userSpoke: userSpoke,
    );
  }

  bool _messageHasSpeakerContent(ChatMessage message, String speakerName) {
    final named = message.speakerName?.trim();
    final matchesSpeaker = named != null && named.isNotEmpty
        ? _namesMatch(named, speakerName)
        : message.isAssistant;
    if (!matchesSpeaker) return false;
    if (message.text.trim().isNotEmpty) return true;
    return message.swipes.any((swipe) => swipe.trim().isNotEmpty);
  }

  bool _messageIsFromSpeaker(ChatMessage message, String speakerName) {
    if (message.isUser || message.isNarrator || message.isDirector) {
      return false;
    }
    if (message.isGroupBeat && message.beatLines != null) {
      for (final line in message.beatLines!) {
        if (_namesMatch(line.speakerName, speakerName)) return true;
      }
      return false;
    }
    if (!message.isAssistant) return false;
    if (message.text.trim().isEmpty) return false;
    final named = message.speakerName?.trim();
    if (named != null && named.isNotEmpty) {
      return _namesMatch(named, speakerName);
    }
    return true;
  }

  bool _namesMatch(String a, String b) {
    final left = a.trim().toLowerCase();
    final right = b.trim().toLowerCase();
    if (left.isEmpty || right.isEmpty) return false;
    if (left == right) return true;
    final leftFirst = left.split(RegExp(r'\s+')).first;
    final rightFirst = right.split(RegExp(r'\s+')).first;
    return leftFirst.length >= 3 &&
        rightFirst.length >= 3 &&
        leftFirst == rightFirst;
  }

  /// Chronological history block — skips the active narrator (injected later).
  Map<String, String>? historyBlockFor({
    required ChatMessage message,
    required String? activeNarratorId,
    String focusCharacterName = '',
    Iterable<String> castNames = const [],
  }) {
    if (!message.isNarrator) return null;
    if (message.id == activeNarratorId) return null;
    final block = formatHistoricalNote(
      text: message.text,
      focusCharacterName: focusCharacterName,
      castNames: castNames,
    );
    if (block.isEmpty) return null;
    return {'role': 'system', 'content': block};
  }

  /// Active narrator beat — place late in the prompt (before Director if any).
  String? activeSceneLawBlock({
    required List<ChatMessage> messages,
    required String? activeNarratorId,
    required String userName,
    required String charName,
    bool isGroup = false,
    String speakingAsName = '',
    Set<String> physicallyPresent = const {},
    Set<String> departedPresent = const {},
    Set<String> narratorBeatFor = const {},
    bool userSpokeAfterNarratorBeat = false,
    int? endExclusive,
    int? excludeMessageIndex,
    Iterable<String> castNames = const [],
  }) {
    if (activeNarratorId == null) return null;
    for (final message in messages) {
      if (message.id != activeNarratorId || !message.isNarrator) continue;
      final speaker = speakingAsName.trim().isNotEmpty
          ? speakingAsName.trim()
          : charName.trim();
      final alreadyAddressed = characterAlreadyRepliedSinceNarrator(
        messages: messages,
        narratorId: activeNarratorId,
        speakerName: speaker,
        endExclusive: endExclusive,
        excludeMessageIndex: excludeMessageIndex,
      );
      final userSpoke = userSpokeAfterNarrator(
        messages: messages,
        narratorId: activeNarratorId,
        endExclusive: endExclusive,
      );
      final continuation = sceneContinuedAfterNarrator(
        messages: messages,
        narratorId: activeNarratorId,
        speakerName: speaker,
        endExclusive: endExclusive,
        excludeMessageIndex: excludeMessageIndex,
      );
      final String block;
      if (isGroup) {
        final inScene = physicallyPresent.isEmpty
            ? _narratorNamesCharacter(message.text, speaker)
            : speakerInPresentSet(speaker, physicallyPresent);
        block = formatGroupSceneLaw(
          text: message.text,
          userName: userName,
          speakingAsName: speaker,
          physicallyPresent: physicallyPresent,
          inScene: inScene,
          narratorAlreadyAddressed: alreadyAddressed,
          departedPresent: departedPresent,
          narratorBeatFor: narratorBeatFor,
          userSpokeAfterNarratorBeat: userSpoke,
          sceneContinuedInChat: continuation.continued,
          castWhoContinuedScene: continuation.castWhoSpoke,
          castNames: castNames,
        );
      } else {
        block = formatActiveSceneLaw(
          text: message.text,
          userName: userName,
          charName: charName,
          isGroup: isGroup,
          speakingAsName: speaker,
          narratorAlreadyAddressed: alreadyAddressed,
          sceneContinuedInChat: continuation.continued,
          castNames: castNames,
        );
      }
      return block.isEmpty ? null : block;
    }
    return null;
  }

  /// Names that actually appear in recent chat — not the full group cast.
  List<String> inferPresentCast({
    required List<ChatMessage> messages,
    required String userName,
    required String focusCharacterName,
    int lookback = sceneLookback,
  }) {
    final names = <String>{};
    final user = userName.trim();
    if (user.isNotEmpty) names.add(user);
    final focus = focusCharacterName.trim();
    if (focus.isNotEmpty) names.add(focus);

    final nonEmpty =
        messages.where((m) => m.text.trim().isNotEmpty).toList(growable: false);
    final start = nonEmpty.length > lookback
        ? nonEmpty.length - lookback
        : 0;
    for (final message in nonEmpty.sublist(start)) {
      if (message.isUser) continue;
      if (message.isNarrator) continue;
      final speaker = message.speakerName?.trim();
      if (speaker != null && speaker.isNotEmpty) {
        names.add(speaker);
      } else if (focus.isNotEmpty) {
        names.add(focus);
      }
    }

    final ordered = <String>[];
    if (user.isNotEmpty) ordered.add(user);
    for (final name in names) {
      if (name == user) continue;
      ordered.add(name);
    }
    return ordered;
  }

  List<Map<String, String>> buildGenerateMessages({
    required String userName,
    required String characterName,
    required List<ChatMessage> recentMessages,
    String narratorNote = defaultNote,
    String nudge = '',
    String existingDraft = '',
    bool isGroup = false,
    List<String> otherCharacterNames = const [],
  }) {
    final guidance =
        narratorNote.trim().isEmpty ? defaultNote : narratorNote.trim();
    final draft = existingDraft.trim();
    final steer = nudge.trim();

    final present = inferPresentCast(
      messages: recentMessages,
      userName: userName,
      focusCharacterName: characterName,
    );

    // Keep instructions compact — labeled rule blocks get echoed by some models.
    final system = '''
You are the omniscient narrator for private fiction (one reader).

$guidance

Scope: describe ONLY the current moment in the scene transcript below — not the whole story arc. Mention ONLY people listed as present in this scene (or someone the player nudge explicitly adds). Do not import characters from older background lines or cast lists who are not in the current moment.

Style: direct third-person prose — concrete sights, sounds, positions, actions. No euphemisms, no vague roundabout phrasing, no moralizing, no sanitizing. Match the scene's real tone including intense or adult content.

Write ONE narrator passage: 1–3 short paragraphs (usually under 120 words). You may use *actions* and sensory detail. Do not speak as the player ($userName) or deliver character dialogue except a brief in-scene sound if essential.

Output narrator prose only — no titles, lists, rules, labels, fences, or meta commentary.
'''.trim();

    final user = StringBuffer()
      ..writeln('Player: $userName');
    if (characterName.trim().isNotEmpty) {
      user.writeln('Focus character: ${characterName.trim()}');
    }
    if (present.isNotEmpty) {
      user.writeln(
        'Present in this scene (only these — do not mention others): '
        '${present.join(', ')}',
      );
    }
    if (isGroup && otherCharacterNames.isNotEmpty) {
      user.writeln(
        'Group cast not in recent chat (omit unless nudge puts them here): '
        '${otherCharacterNames.join(', ')}',
      );
    }
    user.writeln();
    user.writeln(_formatSceneContext(
      recentMessages,
      userName: userName,
      characterName: characterName,
    ));
    user.writeln();
    if (draft.isNotEmpty) {
      user.writeln('Revise this narrator draft:');
      user.writeln(draft);
      user.writeln();
    }
    if (steer.isNotEmpty) {
      user.writeln('Player nudge: $steer');
      user.writeln();
    }
    if (draft.isEmpty && steer.isEmpty) {
      user.writeln('Write the next narrator line for this moment.');
    } else if (draft.isNotEmpty && steer.isNotEmpty) {
      user.writeln('Follow the nudge; keep what still fits the current scene.');
    } else if (draft.isNotEmpty) {
      user.writeln('Polish the draft; same facts unless the scene demands a fix.');
    } else {
      user.writeln('Write a narrator line that follows the nudge.');
    }

    return [
      {'role': 'system', 'content': system},
      {'role': 'user', 'content': user.toString().trim()},
    ];
  }

  String _formatSceneContext(
    List<ChatMessage> messages, {
    required String userName,
    required String characterName,
  }) {
    final nonEmpty =
        messages.where((m) => m.text.trim().isNotEmpty).toList(growable: false);
    if (nonEmpty.isEmpty) return 'Current scene transcript: (no messages yet)';

    final sceneStart = nonEmpty.length > sceneLookback
        ? nonEmpty.length - sceneLookback
        : 0;
    final backgroundStart = sceneStart > backgroundLookback
        ? sceneStart - backgroundLookback
        : 0;

    final buffer = StringBuffer();
    if (backgroundStart < sceneStart) {
      buffer.writeln('Older background (do not describe — not the current scene):');
      buffer.writeln(
        _formatMessageLines(
          nonEmpty.sublist(backgroundStart, sceneStart),
          userName: userName,
          characterName: characterName,
        ),
      );
      buffer.writeln();
    }
    buffer.writeln('Current scene (describe THIS — newest last):');
    buffer.writeln(
      _formatMessageLines(
        nonEmpty.sublist(sceneStart),
        userName: userName,
        characterName: characterName,
      ),
    );
    return buffer.toString().trim();
  }

  String _formatMessageLines(
    List<ChatMessage> messages, {
    required String userName,
    required String characterName,
  }) {
    final buffer = StringBuffer();
    for (final message in messages) {
      final text = message.text.trim();
      if (text.isEmpty) continue;
      if (message.isNarrator) {
        buffer.writeln('Narrator: $text');
      } else if (message.isUser) {
        buffer.writeln('$userName: $text');
      } else {
        final who = message.speakerName?.trim().isNotEmpty == true
            ? message.speakerName!.trim()
            : characterName;
        buffer.writeln('$who: $text');
      }
      buffer.writeln();
    }
    return buffer.toString().trim();
  }

  static String _cutInstructionLeak(String text) {
    final patterns = <RegExp>[
      RegExp(r'\n\s*Narrator note\b', caseSensitive: false),
      RegExp(r'\n\s*Hard rules\b', caseSensitive: false),
      RegExp(r'\n\s*You write narrator lines\b', caseSensitive: false),
      RegExp(r'\n\s*You are the omniscient narrator\b', caseSensitive: false),
      RegExp(r'\n\s*Output only the narrator\b', caseSensitive: false),
      RegExp(r'\n\s*-\s*Output ONE narrator\b', caseSensitive: false),
      RegExp(r'\n\s*-\s*Do NOT write as\b', caseSensitive: false),
      RegExp(r'\n\s*-\s*Ground the line in recent\b', caseSensitive: false),
      RegExp(r'\n\s*private roleplay chat app\b', caseSensitive: false),
      RegExp(r'\n\s*private fiction\b', caseSensitive: false),
      RegExp(r'\s+You write narrator lines\b', caseSensitive: false),
      RegExp(r'\s+private roleplay chat app\b', caseSensitive: false),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(text);
      if (match != null) {
        text = text.substring(0, match.start).trimRight();
        break;
      }
    }
    return text;
  }

  static String _trimRepetitionLoops(String text) {
    final andLoop = RegExp(
      r'(\S+)(?:\s+and\s+\1){2,}',
      caseSensitive: false,
    );
    final andMatch = andLoop.firstMatch(text);
    if (andMatch != null && andMatch.start > text.length * 0.35) {
      return text.substring(0, andMatch.start).trimRight();
    }

    final wordLoop = RegExp(r'(\b\w{3,}\b)(?:\s+\1){3,}', caseSensitive: false);
    final wordMatch = wordLoop.firstMatch(text);
    if (wordMatch != null && wordMatch.start > text.length * 0.35) {
      return text.substring(0, wordMatch.start).trimRight();
    }

    // Same short phrase repeated back-to-back (degenerate tails).
    final phraseLoop = RegExp(
      r'(.{12,80}?)(?:\s*\1){2,}',
      caseSensitive: false,
    );
    final phraseMatch = phraseLoop.firstMatch(text);
    if (phraseMatch != null && phraseMatch.start > text.length * 0.4) {
      return text.substring(0, phraseMatch.start).trimRight();
    }

    return text;
  }

  static String _trimCharCap(String text, int maxChars) {
    if (text.length <= maxChars) return text;
    final slice = text.substring(0, maxChars);
    final lastEnd = slice.lastIndexOf(RegExp(r'[.!?]\s'));
    if (lastEnd > maxChars ~/ 2) {
      return slice.substring(0, lastEnd + 1).trimRight();
    }
    return slice.trimRight();
  }
}

/// Whether chat moved on after a narrator beat before the next generation.
class NarratorSceneContinuation {
  const NarratorSceneContinuation({
    required this.continued,
    required this.castWhoSpoke,
    required this.userSpoke,
  });

  final bool continued;
  final Set<String> castWhoSpoke;
  final bool userSpoke;
}
