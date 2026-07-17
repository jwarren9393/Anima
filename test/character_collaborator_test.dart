import 'package:flutter_test/flutter_test.dart';

import 'package:anima/services/character_collaborator.dart';
import 'package:anima/services/settings_service.dart';

void main() {
  const collaborator = CharacterCollaborator();

  group('CharacterCollaborator', () {
    test('appendGenerated joins with blank line', () {
      expect(
        collaborator.appendGenerated('Hello', 'World'),
        'Hello\n\nWorld',
      );
      expect(collaborator.appendGenerated('', 'Only'), 'Only');
      expect(collaborator.appendGenerated('Keep', '  '), 'Keep');
    });

    test('buildMessages includes field purpose and guidance', () {
      final messages = collaborator.buildMessages(
        field: CharacterCollaboratorField.personality,
        draft: const CharacterDraftContext(
          name: 'Luna',
          description: 'A quiet barista.',
        ),
        guidanceNote: 'Do not sanitize.',
      );

      expect(messages.length, 2);
      expect(messages[0]['role'], 'system');
      expect(messages[1]['role'], 'user');
      final system = messages[0]['content']!;
      final user = messages[1]['content']!;
      expect(system, contains('Do not sanitize.'));
      expect(system, contains('Personality'));
      expect(system, contains('APPEND'));
      expect(user, contains('Luna'));
      expect(user, contains('A quiet barista.'));
      expect(user, contains('Target field: Personality'));
    });

    test('empty card uses only current field draft', () {
      final messages = collaborator.buildMessages(
        field: CharacterCollaboratorField.description,
        draft: const CharacterDraftContext(
          description: 'fox girl who loves rain',
        ),
      );
      final user = messages[1]['content']!;
      expect(user, contains('No other character fields'));
      expect(user, contains('fox girl who loves rain'));
      expect(
        messages[0]['content'],
        contains(CollaboratorSettings.defaultGuidanceNote.substring(0, 40)),
      );
    });

    test('excludes target field from other-context block', () {
      final messages = collaborator.buildMessages(
        field: CharacterCollaboratorField.description,
        draft: const CharacterDraftContext(
          name: 'Mira',
          description: 'OLD DESC',
          personality: 'shy',
        ),
      );
      final user = messages[1]['content']!;
      expect(user, contains('shy'));
      expect(user, contains('Mira'));
      // Description appears as the draft, not as a separate "other field".
      expect(user, contains('Current draft / hint'));
      expect(user, contains('OLD DESC'));
      expect(user, isNot(contains('Description:\nOLD DESC')));
    });
  });
}
