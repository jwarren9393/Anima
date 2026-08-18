import 'character.dart';
import 'persona.dart';

/// Character + persona chosen together when starting a solo chat.
class NewChatPick {
  const NewChatPick({
    required this.character,
    required this.persona,
  });

  final Character character;
  final Persona persona;
}
