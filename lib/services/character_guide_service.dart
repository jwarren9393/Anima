/// Player notes that steer one character's next AI reply — without a Director
/// card or rewriting an existing bubble.
class CharacterGuideService {
  const CharacterGuideService();

  /// Extra messages appended before generation. Writes a brand-new reply as
  /// [characterName] from the player's loose instruction (no draft to edit).
  List<Map<String, String>> buildGuideMessages({
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

    return [
      {
        'role': 'system',
        'content':
            'You write one fresh roleplay reply in a private chat app. '
            'The player gave scene direction for $name\'s NEXT line only. '
            'This is not dialogue from $user. Do not write for $user.',
      },
      {
        'role': 'user',
        'content': '''
Player direction for $name's next reply (interpret for the current scene):
$note

Write a completely NEW reply as $name from scratch — not a light edit of any prior line.
Follow the player's intent and beats; you may infer staging from chat context.
The player may describe actions vaguely ("she backs away") — apply that to $name here and now.
Do not add a preamble, label, or name prefix.
Use *actions* and "dialogue" as appropriate for roleplay.
Stay in character as $name.
'''
            .trim(),
      },
    ];
  }
}
