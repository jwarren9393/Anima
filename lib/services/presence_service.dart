import '../models/character.dart';
import '../models/chat_message.dart';
import 'narrator_service.dart';

/// Automatic presence / knowledge filtering for live chat prompts.
///
/// Always on — no settings. Characters only receive history, memory, lore
/// scans, and narrator context from scenes they personally witnessed.
class PresenceService {
  const PresenceService({
    this.narrator = const NarratorService(),
    this.sceneLookback = 12,
  });

  final NarratorService narrator;
  final int sceneLookback;

  static const knowledgeBoundaryPrompt = '''
Knowledge boundaries (absolute — never break these):
- You are {{char}}. You ONLY know what {{char}} personally witnessed in-scene or was told directly while present.
- Chat history, memory, and narrator lines below are already filtered to {{char}}'s knowledge. If something is missing, {{char}} does NOT know it — do not guess, infer, or "sense" off-screen events.
- Do NOT reference private conversations, moods, actions, or thoughts from scenes where {{char}} was not present — not even vaguely, not even "I heard", not even unless {{user}} told you in-scene.
- Other character summaries in the system prompt are identity reference only — not shared knowledge.
- If uncertain, stay neutral or ask — never invent awareness.
- {{user}}'s agency stays intact; do not speak for {{user}}.
''';

  /// Hard-coded system addendum with macros applied.
  String formatKnowledgeBoundary({
    required String charName,
    required String userName,
  }) {
    final char = charName.trim().isEmpty ? 'Character' : charName.trim();
    final user = userName.trim().isEmpty ? 'User' : userName.trim();
    return knowledgeBoundaryPrompt
        .replaceAll('{{char}}', char)
        .replaceAll('{{user}}', user)
        .trim();
  }

  /// Filter recent history for one speaking character.
  List<ChatMessage> filterHistoryForCharacter({
    required List<ChatMessage> history,
    required List<ChatMessage> allMessages,
    required Character focusCharacter,
    required List<Character> participants,
    required String userName,
  }) {
    if (history.isEmpty) return history;
    final focus = focusCharacter.name.trim();
    if (focus.isEmpty) return history;

    final castNames = _castNames(participants, userName);
    final isSolo = participants.length <= 1;

    return history.where((message) {
      final index = _indexOfMessage(allMessages, message);
      if (index < 0) return true;
      return isMessageVisibleToCharacter(
        message: message,
        messageIndex: index,
        allMessages: allMessages,
        focusCharacterName: focus,
        userName: userName,
        castNames: castNames,
        participants: participants,
        soloChat: isSolo,
      );
    }).toList(growable: false);
  }

  /// Union filter for group beats — visible if any beat speaker could witness it.
  List<ChatMessage> filterHistoryForSpeakers({
    required List<ChatMessage> history,
    required List<ChatMessage> allMessages,
    required List<Character> speakers,
    required List<Character> participants,
    required String userName,
  }) {
    if (speakers.isEmpty) return history;
    if (speakers.length == 1) {
      return filterHistoryForCharacter(
        history: history,
        allMessages: allMessages,
        focusCharacter: speakers.first,
        participants: participants,
        userName: userName,
      );
    }

    return history.where((message) {
      for (final speaker in speakers) {
        final index = _indexOfMessage(allMessages, message);
        if (index < 0) return true;
        if (isMessageVisibleToCharacter(
          message: message,
          messageIndex: index,
          allMessages: allMessages,
          focusCharacterName: speaker.name,
          userName: userName,
          castNames: _castNames(participants, userName),
          participants: participants,
          soloChat: false,
        )) {
          return true;
        }
      }
      return false;
    }).toList(growable: false);
  }

  bool isMessageVisibleToCharacter({
    required ChatMessage message,
    required int messageIndex,
    required List<ChatMessage> allMessages,
    required String focusCharacterName,
    required String userName,
    required Set<String> castNames,
    List<Character> participants = const [],
    bool soloChat = false,
  }) {
    final focus = _normName(focusCharacterName);
    if (focus.isEmpty) return true;

    if (message.isDirector) {
      return false;
    }

    if (message.isNarrator) {
      final scenePresent = _presentFromNarrator(
        message.text,
        castNames,
        _normName(userName),
      );
      return scenePresent.contains(focus);
    }

    if (message.isUser) {
      if (soloChat) return true;
      final mentioned = _mentionedCastFromText(message.text, castNames);
      if (mentioned.isNotEmpty) {
        return mentioned.contains(focus);
      }
      final present = inferPresentAt(
        messages: allMessages,
        upToIndex: messageIndex,
        userName: userName,
        castNames: castNames,
        participants: participants,
      );
      return present.contains(focus);
    }

    final speaker = _messageSpeakerName(message, focusCharacterName);
    if (speaker != null && _normName(speaker) == focus) {
      return true;
    }

    if (message.isGroupBeat && message.beatLines != null) {
      for (final line in message.beatLines!) {
        if (_normName(line.speakerName) == focus) return true;
      }
    }

    final present = inferPresentAt(
      messages: allMessages,
      upToIndex: messageIndex,
      userName: userName,
      castNames: castNames,
      participants: participants,
    );

    if (soloChat) {
      return present.contains(focus);
    }

    return present.contains(focus);
  }

  /// Who is in the scene at [upToIndex] (inclusive).
  Set<String> inferPresentAt({
    required List<ChatMessage> messages,
    required int upToIndex,
    required String userName,
    required Set<String> castNames,
    List<Character> participants = const [],
  }) {
    final user = _normName(userName);
    final soloChat = participants.length <= 1;
    final present = _seedPresent(
      castNames: castNames,
      user: user,
      participants: participants,
      soloChat: soloChat,
      messages: messages,
    );

    if (messages.isEmpty) return present;

    final end = upToIndex.clamp(0, messages.length - 1);
    var sceneStart = 0;
    for (var i = end; i >= 0; i--) {
      if (messages[i].isNarrator) {
        sceneStart = i;
        break;
      }
    }

    final windowStart = (end - sceneLookback + 1).clamp(0, end);
    final start = sceneStart < windowStart ? sceneStart : windowStart;

    for (var i = start; i <= end; i++) {
      final message = messages[i];
      if (message.isNarrator) {
        present
          ..clear()
          ..addAll(_presentFromNarrator(message.text, castNames, user));
        continue;
      }

      final speaker = _messageSpeakerName(message, '');
      if (speaker != null && speaker.trim().isNotEmpty) {
        present.add(_normName(speaker));
      }
      if (message.isUser) {
        if (user.isNotEmpty) present.add(user);
        present.addAll(_mentionedCastFromText(message.text, castNames));
      }
      if (message.isGroupBeat && message.beatLines != null) {
        for (final line in message.beatLines!) {
          final name = line.speakerName.trim();
          if (name.isNotEmpty) present.add(_normName(name));
        }
      }
    }

    if (present.isEmpty && user.isNotEmpty) {
      present.add(user);
    }
    return present;
  }

  /// Memory bullets filtered to what [characterName] could know.
  String filterMemoryForCharacter({
    required String memory,
    required String characterName,
    required String userName,
    required Iterable<String> castNames,
  }) {
    final body = memory.trim();
    if (body.isEmpty) return '';

    final focus = _normName(characterName);
    final cast = castNames.map(_normName).where((n) => n.isNotEmpty).toSet();

    final kept = <String>[];
    for (final rawLine in body.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      if (_memoryLineVisibleTo(line, focus: focus, cast: cast)) {
        kept.add(line);
      }
    }
    return kept.join('\n');
  }

  /// Union memory filter for coordinated group beats.
  String filterMemoryForSpeakers({
    required String memory,
    required List<Character> speakers,
    required String userName,
    required Iterable<String> castNames,
  }) {
    final body = memory.trim();
    if (body.isEmpty || speakers.isEmpty) return '';

    final kept = <String>{};
    for (final speaker in speakers) {
      final slice = filterMemoryForCharacter(
        memory: body,
        characterName: speaker.name,
        userName: userName,
        castNames: castNames,
      );
      for (final line in slice.split('\n')) {
        final trimmed = line.trim();
        if (trimmed.isNotEmpty) kept.add(trimmed);
      }
    }
    return kept.join('\n');
  }

  String formatFilteredMemoryForPrompt({
    required String filteredMemory,
    required String charName,
  }) {
    final body = filteredMemory.trim();
    if (body.isEmpty) return '';
    final char = charName.trim().isEmpty ? 'Character' : charName.trim();
    return '''
Memory summary (facts $char personally knows — reference only):
$body

These are the ONLY story facts $char may treat as known. Do NOT mimic this summary's tone.
Do NOT use facts from scenes $char did not witness. If a fact is not listed, $char does not know it.
'''
        .trim();
  }

  Set<String> _seedPresent({
    required Set<String> castNames,
    required String user,
    required List<Character> participants,
    required bool soloChat,
    required List<ChatMessage> messages,
  }) {
    final present = <String>{};
    if (user.isNotEmpty) present.add(user);

    if (soloChat && participants.length == 1) {
      present.add(_normName(participants.first.name));
      return present;
    }

    for (final message in messages) {
      if (message.isAssistant) {
        final speaker = message.speakerName?.trim();
        if (speaker != null && speaker.isNotEmpty) {
          present.add(_normName(speaker));
        }
        break;
      }
      if (message.isGroupBeat && message.beatLines != null) {
        for (final line in message.beatLines!) {
          final name = line.speakerName.trim();
          if (name.isNotEmpty) present.add(_normName(name));
        }
        break;
      }
    }
    return present;
  }

  bool _memoryLineVisibleTo(
    String line, {
    required String focus,
    required Set<String> cast,
  }) {
    final lower = line.toLowerCase();
    final label = _memoryLabelBody(lower);

    final knownBy = _parseNameListAfter(
      lower,
      RegExp(r'\(known by\s*([^)]+)\)', caseSensitive: false),
    );
    if (knownBy.isNotEmpty) {
      return knownBy.contains(focus);
    }

    final witnesses = _parseNameListAfter(
      lower,
      RegExp(r'\(witnesses?\s*:\s*([^)]+)\)', caseSensitive: false),
    );
    if (witnesses.isNotEmpty) {
      return witnesses.contains(focus);
    }

    final onlyMatch = RegExp(
      r'\(([^)]+)\s+only\)',
      caseSensitive: false,
    ).firstMatch(lower);
    if (onlyMatch != null) {
      final onlyNames = _splitNames(onlyMatch.group(1) ?? '');
      if (onlyNames.isNotEmpty) {
        return onlyNames.contains(focus);
      }
    }

    if (_isPublicMemoryLabel(label)) {
      return true;
    }

    const privatePrefixes = [
      'secret:',
      'event:',
      'relationship:',
      'injury:',
      'promise:',
      'change:',
      'thread:',
      'goal:',
    ];
    for (final prefix in privatePrefixes) {
      if (label.startsWith(prefix)) {
        final mentioned =
            cast.where((name) => _textContainsCastName(lower, name)).toSet();
        if (mentioned.isEmpty) return false;
        return mentioned.contains(focus);
      }
    }

    final mentioned =
        cast.where((name) => _textContainsCastName(lower, name)).toSet();
    if (mentioned.isEmpty) return false;
    return mentioned.contains(focus);
  }

  String _memoryLabelBody(String lower) {
    var body = lower.trim();
    while (body.startsWith('- ') ||
        body.startsWith('* ') ||
        body.startsWith('• ')) {
      body = body.substring(2).trim();
    }
    return body;
  }

  Set<String> _presentFromNarrator(
    String narratorText,
    Set<String> castNames,
    String user,
  ) {
    final lower = narratorText.toLowerCase();

    for (final name in castNames) {
      if (name.isEmpty || name == user) continue;
      final alonePattern = RegExp(
        r'(?:alone|privately|just)\s+(?:with\s+)?[^.;\n]*\b' +
            RegExp.escape(name) +
            r'\b',
        caseSensitive: false,
      );
      if (alonePattern.hasMatch(lower)) {
        return {user, name};
      }
    }

    final present = <String>{};
    if (user.isNotEmpty) present.add(user);
    _addMentionedCast(narratorText, castNames, present);

    for (final name in castNames) {
      if (name.isEmpty || name == user) continue;
      if (_narratorExcludesCast(lower, name)) {
        present.remove(name);
      }
    }
    return present;
  }

  bool _narratorExcludesCast(String lower, String name) {
    final patterns = <String>[
      'without $name',
      'leaving $name',
      '$name waits',
      '$name wait',
      '$name stay',
      '$name stays',
      '$name remain',
      '$name remains',
      '$name left behind',
      '$name stayed behind',
    ];
    return patterns.any(lower.contains);
  }

  bool _isPublicMemoryLabel(String lower) {
    const publicPrefixes = [
      'location:',
      'world:',
      'item:',
      'faction:',
      'rule:',
      'lore:',
      'setting:',
    ];
    for (final prefix in publicPrefixes) {
      if (lower.startsWith(prefix)) return true;
    }
    return false;
  }

  Set<String> _parseNameListAfter(String lower, RegExp pattern) {
    final match = pattern.firstMatch(lower);
    if (match == null) return const {};
    return _splitNames(match.group(1) ?? '');
  }

  Set<String> _splitNames(String raw) {
    return raw
        .split(RegExp(r'[,;/]|\band\b', caseSensitive: false))
        .map((part) => _normName(part))
        .where((name) => name.isNotEmpty)
        .toSet();
  }

  bool _textContainsCastName(String lower, String name) {
    if (name.isEmpty) return false;
    return RegExp(
      '\\b${RegExp.escape(name)}\\b',
      caseSensitive: false,
    ).hasMatch(lower);
  }

  Set<String> _mentionedCastFromText(String text, Set<String> castNames) {
    final lower = text.toLowerCase();
    final mentioned = <String>{};
    for (final name in castNames) {
      if (name.isEmpty) continue;
      if (_textContainsCastName(lower, name)) mentioned.add(name);
    }
    return mentioned;
  }

  void _addMentionedCast(String text, Set<String> castNames, Set<String> present) {
    present.addAll(_mentionedCastFromText(text, castNames));
  }

  String? _messageSpeakerName(ChatMessage message, String fallbackChar) {
    if (message.isUser) return null;
    final named = message.speakerName?.trim();
    if (named != null && named.isNotEmpty) return named;
    if (message.isAssistant) return fallbackChar.trim();
    return null;
  }

  Set<String> _castNames(List<Character> participants, String userName) {
    final names = <String>{
      for (final c in participants)
        if (c.name.trim().isNotEmpty) _normName(c.name),
    };
    final user = _normName(userName);
    if (user.isNotEmpty) names.add(user);
    return names;
  }

  int _indexOfMessage(List<ChatMessage> allMessages, ChatMessage target) {
    for (var i = 0; i < allMessages.length; i++) {
      if (allMessages[i].id == target.id) return i;
    }
    return -1;
  }

  String _normName(String value) => value.trim().toLowerCase();
}
