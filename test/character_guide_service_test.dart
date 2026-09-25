import 'package:anima/services/character_guide_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const service = CharacterGuideService();

  test('buildGuideMessages puts player note in system law, not user speech', () {
    final messages = service.buildGuideMessages(
      instruction: '"You\'re disgusting" — she spits and backs away',
      characterName: 'Mira',
      userName: 'Jay',
    );

    expect(messages.length, 2);
    expect(messages.first['role'], 'system');
    final system = messages.first['content'] ?? '';
    expect(system, contains('CHARACTER GUIDE'));
    expect(system, contains('You\'re disgusting'));
    expect(system, contains('Jay did NOT speak'));
    expect(system, contains('Do not moralize'));

    final user = messages.last['content'] ?? '';
    expect(user, isNot(contains('You\'re disgusting')));
    expect(user, contains('Mira'));
    expect(user, contains('not Jay'));
  });

  test('formatGuideInstruction rejects empty instruction', () {
    expect(
      () => service.formatGuideInstruction(
        instruction: '   ',
        characterName: 'Mira',
        userName: 'Jay',
      ),
      throwsArgumentError,
    );
  });
}
