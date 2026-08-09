import '../models/character.dart';
import '../models/chat_session.dart';
import '../models/lorebook.dart';
import '../models/persona.dart';

/// Resolves library characters/personas/lore with per-chat overrides on [ChatSession].
class ChatSessionResolver {
  const ChatSessionResolver();

  Character resolveCharacter(Character library, ChatSession session) {
    return session.characterOverrides[library.id] ?? library;
  }

  List<Character> resolveParticipants({
    required List<Character> library,
    required ChatSession session,
  }) {
    return [
      for (final character in library)
        resolveCharacter(character, session),
    ];
  }

  Persona? resolvePersona(Persona? library, ChatSession session) {
    return session.personaOverride ?? library;
  }

  List<Lorebook> chatLorebooks(ChatSession session) {
    final book = session.chatLorebook;
    if (book == null || book.isEmpty) return const [];
    return [book];
  }

  bool hasChatOverrides(ChatSession session) {
    return session.characterOverrides.isNotEmpty ||
        session.personaOverride != null ||
        (session.chatLorebook != null && !session.chatLorebook!.isEmpty);
  }
}
