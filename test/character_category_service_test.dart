import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:anima/models/character.dart';
import 'package:anima/models/character_category.dart';
import 'package:anima/services/character_category_service.dart';

void main() {
  late Directory tempDir;
  late CharacterCategoryService service;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('anima_categories_');
    service = CharacterCategoryService(
      documentsDirectory: () async => tempDir,
    );
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('missing file loads as empty', () async {
    final state = await service.loadState();
    expect(state.categories, isEmpty);
    expect(state.memberships, isEmpty);
  });

  test('character can belong to multiple categories', () async {
    final fantasy = await service.upsertCategory(
      CharacterCategory(id: 'cat_fantasy', name: 'Fantasy'),
    );
    expect(fantasy.categories, hasLength(1));

    await service.upsertCategory(
      CharacterCategory(id: 'cat_adult', name: 'Adult'),
    );
    var state = await service.setCategoriesForCharacter(
      'char_1',
      const ['cat_fantasy', 'cat_adult'],
    );
    expect(state.categoriesForCharacter('char_1'), ['cat_fantasy', 'cat_adult']);
    expect(state.characterInCategory('char_1', 'cat_fantasy'), isTrue);

    final chars = [
      const Character(id: 'char_1', name: 'A'),
      const Character(id: 'char_2', name: 'B'),
    ];
    final filtered = service.filterCharacters(
      chars,
      state: state,
      categoryId: 'cat_fantasy',
    );
    expect(filtered.map((c) => c.id), ['char_1']);

    final all = service.filterCharacters(
      chars,
      state: state,
      categoryId: CharacterCategoryService.allFilterId,
    );
    expect(all, hasLength(2));
  });

  test('rename keeps memberships; delete category never deletes characters',
      () async {
    await service.upsertCategory(
      CharacterCategory(id: 'cat_a', name: 'World A'),
    );
    await service.setCategoriesForCharacter('char_1', const ['cat_a']);

    var state = await service.upsertCategory(
      CharacterCategory(id: 'cat_a', name: 'Renamed world'),
    );
    expect(state.categories.single.name, 'Renamed world');
    expect(state.categoriesForCharacter('char_1'), ['cat_a']);

    state = await service.deleteCategory('cat_a');
    expect(state.categories, isEmpty);
    expect(state.categoriesForCharacter('char_1'), isEmpty);
  });

  test('removeCharacter and prune drop stale memberships', () async {
    await service.upsertCategory(
      CharacterCategory(id: 'cat_a', name: 'Keep'),
    );
    await service.setCategoriesForCharacter('char_gone', const ['cat_a']);
    await service.setCategoriesForCharacter('char_keep', const ['cat_a']);

    var state = await service.removeCharacter('char_gone');
    expect(state.memberships.containsKey('char_gone'), isFalse);
    expect(state.categoriesForCharacter('char_keep'), ['cat_a']);

    // Simulate a category that vanished from the list while memberships linger.
    await File('${tempDir.path}/anima_character_categories.json').writeAsString(
      '''
{
  "version": 1,
  "categories": [
    {"id": "cat_a", "name": "Keep"}
  ],
  "memberships": {
    "char_keep": ["cat_a", "cat_missing"],
    "char_orphan": ["cat_a"]
  }
}
''',
    );
    state = await service.prune(existingCharacterIds: const ['char_keep']);
    expect(state.categoriesForCharacter('char_keep'), ['cat_a']);
    expect(state.memberships.containsKey('char_orphan'), isFalse);
  });
}
