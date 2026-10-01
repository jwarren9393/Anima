/// Player notes that steer the *player's own* next message — the {{user}}
/// persona, not an AI character.
///
/// Used by "My line…": the guided version of Impersonate. The note is injected
/// as late mandatory direction, so the model writes your line the way you asked
/// without ever mistaking the note for something the character said.
class PersonaGuideService {
  const PersonaGuideService();

  /// Used when the player asks for their line but gives no direction, so the
  /// direction block never has to be empty.
  static const defaultInstruction =
      'Continue naturally as the player — react to what just happened.';

  String formatPlayerDirection({
    required String instruction,
    required String userName,
    required String characterName,
  }) {
    final note = instruction.trim();
    if (note.isEmpty) {
      throw ArgumentError('Player direction cannot be empty.');
    }
    final user = userName.trim().isEmpty ? 'User' : userName.trim();
    final name =
        characterName.trim().isEmpty ? 'Character' : characterName.trim();

    return '''
PLAYER GUIDE — MANDATORY DIRECTION FOR $user'S NEXT MESSAGE ONLY:
$note

You are writing $user's next message. The direction above is what $user says, does, or feels — it is NOT dialogue from $name.
Follow that intent, and flesh it out naturally from the chat context.
Write ONLY $user's message: use *actions* and "dialogue" as fits the scene.
Do not write $name's lines, do not reply as $name, and do not mention or quote this guide.
Do not start with "$user:" — the app already labels who is speaking.
'''
        .trim();
  }
}
