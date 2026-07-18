import 'package:flutter_test/flutter_test.dart';

import 'package:anima/services/persona_collaborator.dart';
import 'package:anima/services/settings_service.dart';

void main() {
  const collaborator = PersonaCollaborator();

  group('PersonaCollaborator', () {
    test('appendGenerated joins with blank line', () {
      expect(collaborator.appendGenerated('Hello', 'World'), 'Hello\n\nWorld');
      expect(collaborator.appendGenerated('', 'Only'), 'Only');
      expect(collaborator.appendGenerated('Keep', '  '), 'Keep');
    });

    test('buildMessages includes field purpose and guidance', () {
      final messages = collaborator.buildMessages(
        field: PersonaCollaboratorField.personality,
        draft: const PersonaDraftContext(
          name: 'Valerius',
          description: 'Heir of House Blackwood.',
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
      expect(system, contains('player identity'));
      expect(user, contains('Valerius'));
      expect(user, contains('Heir of House Blackwood.'));
      expect(user, contains('Target field: Personality'));
    });

    test('empty persona uses only current field draft', () {
      final messages = collaborator.buildMessages(
        field: PersonaCollaboratorField.description,
        draft: const PersonaDraftContext(
          description: 'dock smuggler tied to the Tide Guild',
        ),
      );
      final user = messages[1]['content']!;
      expect(user, contains('No other persona fields'));
      expect(user, contains('dock smuggler'));
      expect(
        messages[0]['content'],
        contains(CollaboratorSettings.defaultGuidanceNote.substring(0, 40)),
      );
    });

    test('excludes target field from other-context block', () {
      final messages = collaborator.buildMessages(
        field: PersonaCollaboratorField.description,
        draft: const PersonaDraftContext(
          name: 'Mira',
          description: 'OLD ROLE',
          personality: 'wry',
        ),
      );
      final user = messages[1]['content']!;
      expect(user, contains('wry'));
      expect(user, contains('Mira'));
      expect(user, contains('Current draft / hint'));
      expect(user, contains('OLD ROLE'));
      expect(user, isNot(contains('Identity and role:\nOLD ROLE')));
    });
  });
}
