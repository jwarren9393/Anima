import 'package:flutter_test/flutter_test.dart';

import 'package:anima/models/character.dart';
import 'package:anima/services/character_category_service.dart';

void main() {
  test('Character temporary flag round-trips JSON', () {
    const character = Character(
      id: 'char_temp',
      name: 'Dockhand',
      description: 'Knows the harbor.',
      isTemporary: true,
    );

    final restored = Character.fromJson(character.toJson());
    expect(restored.isTemporary, isTrue);
    expect(restored.name, 'Dockhand');
    expect(restored.description, 'Knows the harbor.');
  });

  test('Character defaults isTemporary to false', () {
    const character = Character(id: 'c1', name: 'Lyra');
    expect(character.isTemporary, isFalse);
    expect(Character.fromJson(character.toJson()).isTemporary, isFalse);
  });

  test('filterFullCardsOnly hides temporary characters', () {
    final service = CharacterCategoryService();
    final characters = [
      const Character(id: '1', name: 'Lyra'),
      const Character(id: '2', name: 'Guard', isTemporary: true),
    ];
    final all = service.filterFullCardsOnly(characters, fullCardsOnly: false);
    final full = service.filterFullCardsOnly(characters, fullCardsOnly: true);
    expect(all.length, 2);
    expect(full.length, 1);
    expect(full.first.name, 'Lyra');
  });
}
