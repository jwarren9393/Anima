import 'package:anima/models/lorebook.dart';
import 'package:anima/services/lore_collaborator.dart';
import 'package:anima/services/world_workshop_builder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const collaborator = LoreCollaborator();
  final builder = WorldWorkshopBuilder();

  test('entry compact messages include content', () {
    final messages = collaborator.buildEntryCompactMessages(
      draft: const LoreEntryDraftContext(
        bookName: 'Empire',
        name: 'Paradise',
        keys: 'Paradise, city',
        content: 'A sprawling neon city with many districts.',
      ),
    );
    expect(messages[0]['content'], contains('compact'));
    expect(messages[1]['content'], contains('Paradise'));
    expect(messages[1]['content'], contains('neon city'));
  });

  test('book compact messages include entries', () {
    final messages = collaborator.buildBookCompactMessages(
      book: Lorebook(
        name: 'Empire',
        entries: [
          const LorebookEntry(
            keys: ['city'],
            content: 'Long lore about the city.',
          ),
        ],
      ),
    );
    expect(messages[0]['content'], contains('lorebook'));
    expect(messages[1]['content'], contains('Long lore'));
  });

  test('parseLorebookEntryCompactJson merges into original', () {
    const original = LorebookEntry(
      id: 7,
      name: 'Paradise',
      keys: ['Paradise', 'city'],
      content: 'Very long original lore text here.',
      insertionOrder: 102,
      priority: 10,
    );
    final raw = '''
{
  "name": "Paradise (City)",
  "keys": ["Paradise"],
  "content": "Short city lore."
}
''';
    final compacted = builder.parseLorebookEntryCompactJson(
      raw,
      original: original,
    );
    expect(compacted.id, 7);
    expect(compacted.insertionOrder, 102);
    expect(compacted.priority, 10);
    expect(compacted.name, 'Paradise (City)');
    expect(compacted.keys, ['Paradise']);
    expect(compacted.content, 'Short city lore.');
  });
}
