/// Player notes that steer one character's next AI reply — without a Director
/// card or rewriting an existing bubble.
class CharacterGuideService {
  const CharacterGuideService();

  /// Mandatory late-prompt block (same priority pattern as Director notes).
  String formatGuideInstruction({
    required String instruction,
    required String characterName,
    required String userName,
  }) {
    final note = instruction.trim();
    if (note.isEmpty) {
      throw ArgumentError('Guide instruction cannot be empty.');
    }
    final name =
        characterName.trim().isEmpty ? 'Character' : characterName.trim();
    final user = userName.trim().isEmpty ? 'User' : userName.trim();

    return '''
CHARACTER GUIDE — MANDATORY DIRECTION FOR $name'S NEXT LINE ONLY:
$note

This is authoritative scene direction from the player for $name's next reply. It is NOT dialogue from $user.
Any quoted speech, actions, or beats in the note above are what $name should say or do — $user did NOT speak those lines.
Do not have $name react to $user as if $user said the note's dialogue. Do not moralize, lecture, refuse, or break character to scold the player.
Follow the player's intent; you may flesh out staging from chat context.
Write a completely NEW in-character reply as $name — not a light edit of any prior line.
Do not speak for $user. Do not add a preamble, label, or "$name:" prefix.
Use *actions* and "dialogue" as appropriate for roleplay.
'''
        .trim();
  }

  /// Late prompt stack for Guide AI — system law first, then a short user nudge
  /// that does NOT repeat the player's note (avoids treating it as $user speech).
  List<Map<String, String>> buildGuideMessages({
    required String instruction,
    required String characterName,
    required String userName,
  }) {
    final name =
        characterName.trim().isEmpty ? 'Character' : characterName.trim();
    final user = userName.trim().isEmpty ? 'User' : userName.trim();

    return [
      {
        'role': 'system',
        'content': formatGuideInstruction(
          instruction: instruction,
          characterName: characterName,
          userName: userName,
        ),
      },
      {
        'role': 'user',
        'content':
            '(Write only $name\'s next reply now, following the CHARACTER GUIDE '
            'above. The guide describes $name — not $user.)',
      },
    ];
  }
}
