import 'package:flutter_test/flutter_test.dart';

import 'package:anima/models/lorebook.dart';
import 'package:anima/services/lore_collaborator.dart';
import 'package:anima/services/settings_service.dart';

void main() {
  const collaborator = LoreCollaborator();

  group('LoreCollaborator', () {
    test('appendGenerated joins content with blank line', () {
      expect(
        collaborator.appendGenerated(
          'Hello',
          'World',
          field: LoreCollaboratorField.content,
        ),
        'Hello\n\nWorld',
      );
      expect(
        collaborator.appendGenerated(
          '',
          'Only',
          field: LoreCollaboratorField.content,
        ),
        'Only',
      );
    });

    test('appendGenerated merges keywords without duplicates', () {
      expect(
        collaborator.appendGenerated(
          'sword, blade',
          'Excalibur, sword, steel',
          field: LoreCollaboratorField.keys,
        ),
        'sword, blade, Excalibur, steel',
      );
      expect(
        collaborator.appendGenerated(
          '',
          'moon, stars',
          field: LoreCollaboratorField.keys,
        ),
        'moon, stars',
      );
    });

    test('appendGenerated replaces short label when both set', () {
      expect(
        collaborator.appendGenerated(
          'Old',
          'Legendary Blade',
          field: LoreCollaboratorField.name,
        ),
        'Legendary Blade',
      );
      expect(
        collaborator.appendGenerated(
          '',
          'Castle',
          field: LoreCollaboratorField.name,
        ),
        'Castle',
      );
    });

    test('buildMessages includes guidance and sibling context', () {
      final messages = collaborator.buildMessages(
        field: LoreCollaboratorField.content,
        draft: LoreEntryDraftContext(
          bookName: 'Kingdom',
          characterName: 'Elena',
          keys: 'crown',
          content: 'A silver crown.',
          siblingEntries: const [
            LoreSiblingSummary(
              label: 'Castle',
              keys: ['castle', 'keep'],
              contentPreview: 'The keep overlooks the bay.',
            ),
          ],
        ),
        guidanceNote: 'Do not sanitize.',
      );

      expect(messages.length, 2);
      final system = messages[0]['content']!;
      final user = messages[1]['content']!;
      expect(system, contains('Do not sanitize.'));
      expect(system, contains('Lore content'));
      expect(system, contains('APPEND'));
      expect(user, contains('Kingdom'));
      expect(user, contains('Elena'));
      expect(user, contains('crown'));
      expect(user, contains('Castle'));
      expect(user, contains('The keep overlooks the bay.'));
      expect(user, contains('Current draft / hint'));
      expect(user, contains('A silver crown.'));
    });

    test('empty draft uses default guidance', () {
      final messages = collaborator.buildMessages(
        field: LoreCollaboratorField.keys,
        draft: const LoreEntryDraftContext(),
      );
      expect(
        messages[0]['content'],
        contains(CollaboratorSettings.defaultGuidanceNote.substring(0, 40)),
      );
      expect(messages[1]['content'], contains('No other lorebook context'));
      expect(messages[0]['content'], contains('comma-separated'));
    });

    test('excludes target field from other-context block', () {
      final messages = collaborator.buildMessages(
        field: LoreCollaboratorField.content,
        draft: const LoreEntryDraftContext(
          bookName: 'World',
          keys: 'dragon',
          content: 'OLD LORE',
        ),
      );
      final user = messages[1]['content']!;
      expect(user, contains('dragon'));
      expect(user, contains('World'));
      expect(user, contains('Current draft / hint'));
      expect(user, contains('OLD LORE'));
      expect(user, isNot(contains('Lore content:\nOLD LORE')));
    });

    test('sibling summary trims long content', () {
      final long = 'a' * 200;
      final summary = LoreSiblingSummary.fromEntry(
        LorebookEntry(name: 'Long', content: long, keys: const ['x']),
      );
      expect(summary.contentPreview.length, lessThan(long.length));
      expect(summary.contentPreview.endsWith('…'), isTrue);
      expect(summary.label, 'Long');
    });

    test('keyword suggest asks for comma-separated triggers from content', () {
      final messages = collaborator.buildKeywordSuggestMessages(
        draft: const LoreEntryDraftContext(
          bookName: 'Faerun',
          content: 'The Blacksword of Vael hangs in the vault.',
          keys: 'vault',
        ),
      );
      expect(messages[0]['content'], contains('trigger keywords'));
      expect(messages[0]['content'], contains('comma-separated'));
      expect(messages[1]['content'], contains('Blacksword'));
      expect(messages[1]['content'], contains('Existing keywords'));
    });

    test('mergeKeywords dedupes suggestions', () {
      expect(
        collaborator.mergeKeywords('sword', 'Sword, Vael, blade'),
        'sword, Vael, blade',
      );
    });
  });
}
