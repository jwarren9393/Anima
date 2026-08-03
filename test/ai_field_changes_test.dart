import 'package:flutter_test/flutter_test.dart';

import 'package:anima/models/character.dart';
import 'package:anima/models/lorebook.dart';
import 'package:anima/services/ai_field_changes.dart';

void main() {
  group('compareCharacterFields', () {
    test('detects changed text fields only', () {
      final before = Character(
        id: 'a',
        name: 'Luna',
        description: 'Tall scout.',
        personality: 'Quiet.',
        scenario: 'Forest camp.',
      );
      final after = before.copyWith(
        description: 'Tall elven scout.',
        personality: 'Quiet.',
      );

      final changes = compareCharacterFields(before, after);
      expect(changes.length, 1);
      expect(changes.first.label, 'Description');
      expect(changes.first.before, 'Tall scout.');
      expect(changes.first.after, 'Tall elven scout.');
    });
  });

  group('compareLorebooks', () {
    test('detects entry content changes', () {
      final before = Lorebook(
        name: 'Kingdom',
        entries: [
          LorebookEntry(id: 1, name: 'Capital', keys: ['capital'], content: 'Old fact.'),
        ],
      );
      final after = before.copyWith(
        entries: [
          LorebookEntry(id: 1, name: 'Capital', keys: ['capital'], content: 'New fact.'),
        ],
      );

      final changes = compareLorebooks(before, after);
      expect(changes.any((c) => c.label.contains('Capital')), isTrue);
      expect(changes.any((c) => c.before.contains('Old fact')), isTrue);
      expect(changes.any((c) => c.after.contains('New fact')), isTrue);
    });
  });
}
