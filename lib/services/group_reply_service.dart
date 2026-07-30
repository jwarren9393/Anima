import '../models/chat_message.dart';
import '../models/character.dart';
import 'prompt_builder.dart';
import 'settings_service.dart';

/// One character line parsed from a group-beat generation.
class GroupBeatLine {
  const GroupBeatLine({required this.character, required this.text});

  final Character character;
  final String text;
}

/// Generates one coordinated “beat” where several group members react together.
class GroupReplyService {
  const GroupReplyService();

  static const _promptBuilder = PromptBuilder();

  /// ~120–180 tokens per speaking character keeps reactions snappy.
  static int beatMaxTokens(int speakerCount) {
    final n = speakerCount.clamp(2, 8);
    return (n * 160 + 128).clamp(384, 1400);
  }

  static SamplingSettings beatSampling(SamplingSettings base, int speakerCount) {
    final cap = beatMaxTokens(speakerCount);
    final userMax = base.maxTokens;
    final effective = userMax == null || userMax > cap ? cap : userMax;
    return base.copyWith(
      maxTokens: effective,
      temperature: base.temperature > 0.78 ? 0.78 : base.temperature,
      frequencyPenalty: base.frequencyPenalty < 0.2 ? 0.3 : base.frequencyPenalty,
      presencePenalty: base.presencePenalty < 0.1 ? 0.15 : base.presencePenalty,
      repetitionPenalty: base.repetitionPenalty ?? 1.06,
    );
  }

  List<Map<String, String>> buildBeatMessages({
    required List<Character> speakers,
    required List<Character> allInChat,
    required List<Map<String, String>> historyApiMessages,
    required String userName,
    String userPersona = '',
    String loreBefore = '',
    String loreAfter = '',
    String memoryBlock = '',
    String openingBlock = '',
    String nudge = '',
    String globalSystemPrompt = '',
    String postHistory = '',
  }) {
    final safeUser = userName.trim().isEmpty ? 'User' : userName.trim();
    final ordered = _orderedSpeakers(speakers);
    if (ordered.length < 2) return const [];

    final nameList = ordered.map((c) => c.name.trim()).join(', ');
    final formatExample = ordered
        .map((c) => '${c.name.trim()}: *brief reaction*')
        .join('\n');

    final systemParts = <String>[
      'You write a single coordinated group beat for private fiction.',
      'Several characters react to the SAME moment at the SAME time — quick '
          'reactions, not separate monologues. Do not advance the scene between '
          'lines; do not contradict the tone another character sets.',
      'Characters in this beat (use every one, in this order): $nameList',
      'Format — one line per character, exactly:',
      formatExample,
      'Rules:',
      '- Each line starts with the character name, colon, then their reaction.',
      '- Brief only: usually one short action and/or one spoken line per character.',
      '- Write as that character (their voice) but keep it short.',
      '- Do not speak as $safeUser.',
      '- No numbering, bullets, titles, or commentary outside the lines.',
      '- Do not sanitize or soften intense or adult content — match the scene.',
    ];

    for (final character in ordered) {
      final summary = _promptBuilder.characterSummary(character);
      if (summary.isNotEmpty) {
        systemParts.add('About ${character.name.trim()}:\n$summary');
      }
    }

    final notSpeaking = allInChat
        .where((c) => !ordered.any((s) => s.id == c.id))
        .map((c) => c.name.trim())
        .where((n) => n.isNotEmpty)
        .toList();
    if (notSpeaking.isNotEmpty) {
      systemParts.add(
        'Others in the chat but silent in this beat (do not write for them): '
        '${notSpeaking.join(', ')}',
      );
    }

    if (loreBefore.trim().isNotEmpty) {
      systemParts.add('World info:\n${loreBefore.trim()}');
    }
    if (loreAfter.trim().isNotEmpty) {
      systemParts.add('World info:\n${loreAfter.trim()}');
    }

    if (userPersona.trim().isNotEmpty) {
      systemParts.add('The user is $safeUser.\nPersona:\n${userPersona.trim()}');
    } else {
      systemParts.add('The user is called $safeUser.');
    }

    final global = globalSystemPrompt.trim();
    if (global.isNotEmpty) {
      systemParts.add(
        _promptBuilder.applyMacros(
          global,
          charName: ordered.first.name,
          userName: safeUser,
        ),
      );
    }

    final msgs = <Map<String, String>>[
      {'role': 'system', 'content': systemParts.join('\n\n')},
    ];

    if (openingBlock.trim().isNotEmpty) {
      msgs.add({'role': 'system', 'content': openingBlock.trim()});
    }
    if (memoryBlock.trim().isNotEmpty) {
      msgs.add({'role': 'system', 'content': memoryBlock.trim()});
    }

    msgs.addAll(historyApiMessages);

    final user = StringBuffer()
      ..writeln('Write the group beat now — every listed character, one brief line each.');
    if (nudge.trim().isNotEmpty) {
      user.writeln();
      user.writeln('Player nudge: ${nudge.trim()}');
    }

    msgs.add({'role': 'user', 'content': user.toString().trim()});

    if (postHistory.trim().isNotEmpty) {
      msgs.add({'role': 'system', 'content': postHistory.trim()});
    }

    return msgs;
  }

  /// Parses `Name: reaction` lines into [GroupBeatLine]s (order preserved).
  List<GroupBeatLine> parseBeatReply(String raw, List<Character> speakers) {
    final ordered = _orderedSpeakers(speakers);
    if (ordered.isEmpty) return const [];

    final byName = <String, Character>{};
    for (final c in ordered) {
      final name = c.name.trim();
      if (name.isEmpty) continue;
      byName[name.toLowerCase()] = c;
    }

    final lines = raw.replaceAll('\r\n', '\n').split('\n');
    final out = <GroupBeatLine>[];
    final used = <String>{};

    final linePattern = RegExp(r'^(.+?)\s*[:：\-–]\s*(.+)$');

    for (final line in lines) {
      var trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      // Strip leading list markers the model sometimes adds.
      trimmed = trimmed.replaceFirst(RegExp(r'^\d+[.)]\s+'), '');
      trimmed = trimmed.replaceFirst(RegExp(r'^[-*•]\s+'), '');

      final match = linePattern.firstMatch(trimmed);
      if (match == null) continue;

      var namePart = (match.group(1) ?? '').trim();
      final textPart = (match.group(2) ?? '').trim();
      if (namePart.isEmpty || textPart.isEmpty) continue;

      // Strip markdown bold around names.
      namePart = namePart.replaceAll(RegExp(r'[*_`]+'), '').trim();

      final character = _matchCharacter(namePart, ordered, byName);
      if (character == null || used.contains(character.id)) continue;

      used.add(character.id);
      out.add(GroupBeatLine(character: character, text: textPart));
    }

    return out;
  }

  List<Character> _orderedSpeakers(List<Character> speakers) {
    final seen = <String>{};
    final out = <Character>[];
    for (final c in speakers) {
      if (seen.contains(c.id)) continue;
      seen.add(c.id);
      out.add(c);
    }
    return out;
  }

  Character? _matchCharacter(
    String namePart,
    List<Character> ordered,
    Map<String, Character> byName,
  ) {
    final lower = namePart.toLowerCase();
    final exact = byName[lower];
    if (exact != null) return exact;

    for (final c in ordered) {
      final name = c.name.trim();
      if (name.isEmpty) continue;
      if (lower == name.toLowerCase()) return c;
    }

    // Prefix match — longest name first to avoid "Ann" matching "Anna".
    final sorted = ordered.toList()
      ..sort((a, b) => b.name.length.compareTo(a.name.length));
    for (final c in sorted) {
      final name = c.name.trim();
      if (name.isEmpty) continue;
      if (lower.startsWith(name.toLowerCase())) return c;
    }
    return null;
  }

  String formatRecentTranscript({
    required List<ChatMessage> messages,
    required String userName,
    required List<Character> participants,
    int lookback = 12,
  }) {
    final nonEmpty =
        messages.where((m) => m.text.trim().isNotEmpty).toList(growable: false);
    final start = nonEmpty.length > lookback
        ? nonEmpty.length - lookback
        : 0;
    final buffer = StringBuffer();
    for (final message in nonEmpty.sublist(start)) {
      if (message.isGroupBeat && message.beatLines != null) {
        for (final line in message.beatLines!) {
          final lineText = line.text.trim();
          if (lineText.isEmpty) continue;
          final who = line.speakerName.trim().isNotEmpty
              ? line.speakerName.trim()
              : _fallbackName(participants, line.speakerId);
          buffer.writeln('$who: $lineText');
        }
        buffer.writeln();
        continue;
      }
      final text = message.text.trim();
      if (message.isNarrator) {
        buffer.writeln('Narrator: $text');
      } else if (message.isUser) {
        buffer.writeln('${userName.trim()}: $text');
      } else {
        final who = message.speakerName?.trim().isNotEmpty == true
            ? message.speakerName!.trim()
            : _fallbackName(participants, message.speakerId);
        buffer.writeln('$who: $text');
      }
      buffer.writeln();
    }
    return buffer.toString().trim();
  }

  String _fallbackName(List<Character> participants, String? speakerId) {
    if (speakerId != null) {
      for (final c in participants) {
        if (c.id == speakerId) return c.name.trim();
      }
    }
    return participants.isNotEmpty ? participants.first.name.trim() : 'Character';
  }
}
