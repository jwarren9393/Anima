import 'package:anima/services/chat_style_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const rules = ChatStyleRules();

  test('first-person rule names the speaker and bans third person', () {
    final block = rules.formatFirstPersonPerspectiveRule(speakerName: 'Mira');
    expect(block, contains('Write ONLY as Mira'));
    expect(block, contains('I/my/me'));
    expect(block, contains('*I smile'));
    expect(block, contains('Wrong:'));
    expect(block, contains('Mira'));
  });

  test('first-person rule falls back when name is blank', () {
    final block = rules.formatFirstPersonPerspectiveRule(speakerName: '  ');
    expect(block, contains('the speaker'));
  });
}
