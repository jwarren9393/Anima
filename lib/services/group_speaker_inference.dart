import '../models/chat_message.dart';
import '../models/character.dart';

/// Picks who should speak next in a manual group chat (no round-robin).
class GroupSpeakerInference {
  const GroupSpeakerInference();

  /// Who should reply on Continue / manual generation.
  Character resolve({
    required List<Character> participants,
    required List<ChatMessage> messages,
    Character? primaryCharacter,
  }) {
    if (participants.isEmpty) {
      return primaryCharacter ??
          Character(id: 'unknown', name: 'Character');
    }
    if (messages.isEmpty) {
      return primaryCharacter ?? participants.first;
    }

    final last = messages.last;

    if (last.isAssistant) {
      final fromMessage = _fromMessageSpeaker(last, participants);
      if (fromMessage != null) return fromMessage;
    }

    if (last.isUser) {
      final mentioned = _mentionedInText(last.text, participants);
      if (mentioned != null) return mentioned;

      for (var i = messages.length - 2; i >= 0; i--) {
        final m = messages[i];
        if (m.isAssistant) {
          final fromMessage = _fromMessageSpeaker(m, participants);
          if (fromMessage != null) return fromMessage;
        }
        if (m.isGroupBeat) break;
      }
    }

    if (last.isGroupBeat && last.beatLines != null && last.beatLines!.isNotEmpty) {
      final lastLine = last.beatLines!.last;
      final fromLine = _fromMessageSpeaker(
        ChatMessage(
          id: 'infer',
          role: ChatRole.assistant,
          text: lastLine.text,
          speakerId: lastLine.speakerId,
          speakerName: lastLine.speakerName,
        ),
        participants,
      );
      if (fromLine != null) return fromLine;
    }

    if (primaryCharacter != null &&
        participants.any((c) => c.id == primaryCharacter.id)) {
      return primaryCharacter;
    }
    return participants.first;
  }

  Character? _fromMessageSpeaker(
    ChatMessage message,
    List<Character> participants,
  ) {
    final id = message.speakerId?.trim() ?? '';
    if (id.isNotEmpty) {
      for (final c in participants) {
        if (c.id == id) return c;
      }
    }
    final name = message.speakerName?.trim() ?? '';
    if (name.isNotEmpty) {
      final lower = name.toLowerCase();
      for (final c in participants) {
        if (c.name.trim().toLowerCase() == lower) return c;
      }
    }
    return null;
  }

  Character? _mentionedInText(String text, List<Character> participants) {
    final lower = text.toLowerCase();
    Character? best;
    var bestLen = 0;
    for (final c in participants) {
      final name = c.name.trim();
      if (name.isEmpty) continue;
      final nLower = name.toLowerCase();
      if (lower.contains(nLower) && nLower.length > bestLen) {
        best = c;
        bestLen = nLower.length;
      }
    }
    return best;
  }

  /// Late user nudge when the last visible line was another cast member — keeps
  /// the model from mimicking whoever just spoke in group chats.
  Map<String, String>? buildHandoffNudge({
    required List<ChatMessage> messages,
    required int endExclusive,
    required Character target,
  }) {
    if (endExclusive <= 0 || endExclusive > messages.length) return null;
    final last = messages[endExclusive - 1];
    final targetName =
        target.name.trim().isEmpty ? 'Character' : target.name.trim();

    if (last.isUser) return null;

    if (last.isAssistant) {
      final id = last.speakerId?.trim() ?? '';
      if (id.isNotEmpty && id == target.id) return null;
      final name = last.speakerName?.trim() ?? '';
      if (name.isNotEmpty &&
          name.toLowerCase() == targetName.toLowerCase()) {
        return null;
      }
      final prev = name.isNotEmpty ? name : 'Another character';
      return {
        'role': 'user',
        'content':
            '($prev just spoke. Write ONLY $targetName\'s next reply now — '
            'in $targetName\'s voice and perspective. Do not continue as $prev '
            'or any other cast member. Do not speak for the user. Do not '
            'prefix your reply with "$targetName:" — the app labels the speaker.)',
      };
    }

    if (last.isGroupBeat &&
        last.beatLines != null &&
        last.beatLines!.isNotEmpty) {
      return {
        'role': 'user',
        'content':
            '(A group moment just happened. Write ONLY $targetName\'s next '
            'single reply — in their voice. Do not write for other cast '
            'members. Do not prefix with "$targetName:".)',
      };
    }

    return null;
  }
}
