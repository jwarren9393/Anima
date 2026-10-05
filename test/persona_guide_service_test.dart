import 'package:anima/services/persona_guide_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const service = PersonaGuideService();

  test('formatPlayerDirection makes the note direction for MY line', () {
    final block = service.formatPlayerDirection(
      instruction: 'I lose my temper and walk out',
      userName: 'Jay',
      characterName: 'Mira',
    );

    expect(block, contains('PLAYER GUIDE'));
    expect(block, contains("Jay'S NEXT MESSAGE"));
    expect(block, contains('I lose my temper and walk out'));
    // It must be clear this is the player's own line, not the character's.
    expect(block, contains("Write ONLY Jay's message"));
    expect(block, contains('FIRST PERSON'));
    expect(block, contains('I/my/me'));
    expect(block, contains("Do not write Mira's lines"));
    expect(block, contains('NOT dialogue from Mira'));
  });

  test('formatPlayerDirection rejects an empty note', () {
    expect(
      () => service.formatPlayerDirection(
        instruction: '   ',
        userName: 'Jay',
        characterName: 'Mira',
      ),
      throwsArgumentError,
    );
  });

  test('defaultInstruction works as a player note', () {
    final block = service.formatPlayerDirection(
      instruction: PersonaGuideService.defaultInstruction,
      userName: 'Jay',
      characterName: 'Mira',
    );
    expect(block, contains('PLAYER GUIDE'));
    expect(block, contains('react to what just happened'));
  });

  test('formatPlayerDirection falls back to generic names', () {
    final block = service.formatPlayerDirection(
      instruction: 'wave at them',
      userName: '  ',
      characterName: '',
    );
    expect(block, contains("User'S NEXT MESSAGE"));
    expect(block, contains("Do not write Character's lines"));
  });
}
