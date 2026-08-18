import 'package:anima/models/character.dart';
import 'package:anima/services/character_token_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const service = CharacterTokenService();

  test('breakdown counts prompt fields', () {
    final character = Character(
      id: 'c1',
      name: 'Mira',
      description: 'A' * 400,
      personality: 'Calm and sharp.',
      systemPrompt: 'You are Mira.',
    );
    final breakdown = service.breakdown(character);
    expect(breakdown.promptTokens, greaterThan(50));
    expect(breakdown.groupSummaryTokens, lessThan(breakdown.promptTokens));
  });

  test('embedded lore sums enabled entry bodies', () {
    const character = Character(
      id: 'c2',
      name: 'Rey',
      characterBook: {
        'entries': [
          {'keys': ['rey'], 'content': 'Street muscle.', 'enabled': true},
          {'keys': ['off'], 'content': 'Hidden.', 'enabled': false},
        ],
      },
    );
    final breakdown = service.breakdown(character);
    expect(breakdown.embeddedLoreTokens, greaterThan(0));
  });
}
