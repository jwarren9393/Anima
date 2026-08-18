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
}
