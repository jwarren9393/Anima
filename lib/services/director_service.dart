import '../models/chat_message.dart';
import '../models/chat_session.dart';

/// Player "Director" notes — authoritative scene control for the next reply.
///
/// Not in-character speech. Injected as a mandatory system override while active.
class DirectorService {
  const DirectorService();

  /// Text of the director note that still commands the next generation, if any.
  String? pendingText(ChatSession session) {
    final id = session.pendingDirectorMessageId;
    if (id == null || id.trim().isEmpty) return null;
    for (final message in session.messages) {
      if (message.id == id && message.isDirector) {
        final text = message.text.trim();
        return text.isEmpty ? null : text;
      }
    }
    return null;
  }

  /// After messages are deleted or rewound, keep pending only if that note still exists.
  String? reconcilePendingId(
    List<ChatMessage> messages,
    String? currentPendingId,
  ) {
    if (currentPendingId == null || currentPendingId.trim().isEmpty) {
      return null;
    }
    for (final message in messages) {
      if (message.id == currentPendingId && message.isDirector) {
        return currentPendingId;
      }
    }
    return null;
  }

  /// Mandatory override — placed last in the prompt stack (highest priority).
  String formatActiveInstruction({
    required String text,
    required String charName,
    required String userName,
    bool isGroup = false,
    bool groupBeat = false,
  }) {
    final body = text.trim();
    if (body.isEmpty) return '';
    final char = charName.trim().isEmpty ? 'Character' : charName.trim();
    final user = userName.trim().isEmpty ? 'User' : userName.trim();
    final target = groupBeat
        ? 'Every character line in this group beat'
        : char;

    return '''
PLAYER DIRECTOR INSTRUCTION — MANDATORY FOR THIS REPLY ONLY:
$body

This is authoritative scene direction from the player. It is NOT dialogue from $user and NOT a suggestion.
$target MUST follow this direction exactly for this one generation — actions, emotions, tone, intent, beats, and how they respond are law.
Do not ignore, soften, reinterpret, or contradict this instruction.
Do not default to unrelated habits or props from your character card if they contradict this direction.
${isGroup && !groupBeat ? 'Only $char is speaking in this reply — obey the direction for $char.' : ''}
Do not speak for $user.
Stay in character while obeying the direction.
'''
        .trim();
  }

  /// Older director notes already played out — weak context only.
  String formatHistoricalNote({required String text}) {
    final body = text.trim();
    if (body.isEmpty) return '';
    return '''
Earlier player director note (already addressed — do not re-enact unless still true in chat):
$body
'''
        .trim();
  }

  /// How to fold a director line into chat history for API calls.
  Map<String, String>? historyBlockFor({
    required ChatMessage message,
    required String? pendingDirectorId,
  }) {
    if (!message.isDirector) return null;
    if (message.id == pendingDirectorId) return null;
    final block = formatHistoricalNote(text: message.text);
    if (block.isEmpty) return null;
    return {'role': 'system', 'content': block};
  }
}
