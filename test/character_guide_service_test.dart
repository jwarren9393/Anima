import 'package:anima/services/character_guide_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const service = CharacterGuideService();

  test('buildGuideMessages scopes instruction to the active character', () {
    final messages = service.buildGuideMessages(
      instruction: 'gets nervous and backs toward the door',
      characterName: 'Mira',
      userName: 'Jay',
    );

    expect(messages.length, 2);
    final user = messages.last['content'] ?? '';
    expect(user, contains('Mira'));
    expect(user, contains('gets nervous'));
    expect(user, contains('completely NEW reply'));
    expect(user, isNot(contains('rewrite')));
  });

  test('buildGuideMessages rejects empty instruction', () {
    expect(
      () => service.buildGuideMessages(
        instruction: '   ',
        characterName: 'Mira',
        userName: 'Jay',
      ),
      throwsArgumentError,
    );
  });
}
