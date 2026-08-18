import 'package:anima/models/lorebook.dart';
import 'package:anima/models/persona.dart';
import 'package:anima/services/lorebook_token_service.dart';
import 'package:anima/services/persona_token_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const personaService = PersonaTokenService();
  const loreService = LorebookTokenService();

  test('persona breakdown uses promptText', () {
    final persona = Persona(
      id: 'p1',
      name: 'Jay',
      description: 'A' * 200,
      appearance: 'Tall.',
    );
    final breakdown = personaService.breakdown(persona);
    expect(breakdown.promptTokens, greaterThan(40));
    expect(personaService.badgeTokens(persona), breakdown.promptTokens);
  });

  test('anonymous persona has zero tokens', () {
    expect(personaService.badgeTokens(Persona.anonymous()), 0);
  });

  test('lorebook breakdown sums enabled entry content only for badge', () {
    final book = Lorebook(
      entries: [
        const LorebookEntry(
          keys: ['city'],
          content: 'A neon metropolis.',
          enabled: true,
        ),
        const LorebookEntry(
          keys: ['hidden'],
          content: 'Disabled lore.',
          enabled: false,
        ),
      ],
    );
    final breakdown = loreService.breakdown(book);
    expect(breakdown.enabledCount, 1);
    expect(breakdown.totalCount, 2);
    expect(breakdown.enabledTokens, greaterThan(0));
    expect(breakdown.totalTokens, greaterThan(breakdown.enabledTokens));
    expect(loreService.badgeTokens(book), breakdown.enabledTokens);
  });

  test('entry tokens ignore empty content', () {
    expect(
      loreService.entryTokens(const LorebookEntry(keys: ['x'], content: '')),
      0,
    );
  });
}
