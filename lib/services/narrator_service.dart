import '../models/chat_message.dart';
import 'settings_service.dart';

/// Builds prompts for the universal chat Narrator and formats narrator lines
/// for the roleplay API payload.
class NarratorService {
  const NarratorService();

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
  String formatForPrompt({
    required String text,
    required String userName,
    required String charName,
  }) {
    final body = text.trim();
    if (body.isEmpty) return '';
    final user = userName.trim().isEmpty ? 'User' : userName.trim();
    final char = charName.trim().isEmpty ? 'Character' : charName.trim();
    return '''
Narrator (omniscient scene voice — not $user or $char speaking):
$body

This is established scene truth and direction. Characters and $user react to it.
Do not attribute this line to $user or $char in dialogue. Do not repeat it verbatim.
'''.trim();
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
