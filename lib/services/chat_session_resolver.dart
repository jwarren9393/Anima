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

  /// Thread-only Chat lore was removed from the product; keep returning empty
  /// so old `chatLorebook` JSON in backups does not inject.
  List<Lorebook> chatLorebooks(ChatSession session) => const [];

  bool hasChatOverrides(ChatSession session) {
    return session.characterOverrides.isNotEmpty ||
        session.personaOverride != null;
  }
}
