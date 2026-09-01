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

    test('compact asks for shorter JSON persona', () {
      final messages = collaborator.buildCompactMessages(
        draft: PersonaDraftContext(
          name: 'Val',
          description: 'A' * 100,
          personality: 'Calm and watchful.',
        ),
      );
      expect(messages[0]['content'], contains('compact'));
      expect(messages[0]['content'], contains('30–50%'));
      expect(messages[0]['content'], contains('JSON'));
      expect(messages[1]['content'], contains('Val'));
    });

    test('expand asks for richer JSON persona while keeping identity', () {
      final messages = collaborator.buildExpandMessages(
        draft: PersonaDraftContext(
          name: 'Val',
          description: 'Heir of House Blackwood.',
          personality: 'Calm and watchful.',
        ),
      );
      final system = messages[0]['content']!;
      final user = messages[1]['content']!;
      expect(system, contains('expand'));
      expect(system, contains('Invent interesting ideas'));
      expect(system, contains('Keep the same player identity'));
      expect(user, contains('CURRENT PERSONA (expand this'));
      expect(user, contains('Val'));
      expect(user, contains('Heir of House Blackwood.'));
    });

    test('cross-reference grounds persona in source world', () {
      final messages = collaborator.buildCrossReferenceMessages(
        draft: const PersonaDraftContext(
          name: 'Val',
          description: 'Heir of House Blackwood.',
        ),
        sourceLabel: 'Character: Mira',
        sourceBlock: 'Name:\nMira\n\nPersonality:\nBold guild captain.',
        notes: 'Childhood friend of Mira.',
      );
      final system = messages[0]['content']!;
      final user = messages[1]['content']!;

      expect(messages.length, 2);
      expect(system, contains('CROSS-REFERENCE'));
      expect(system, contains('The TARGET comes first'));
      expect(system, contains('{{user}}'));
      expect(user, contains('SOURCE CARD (reference material — Character: Mira)'));
      expect(user, contains('Bold guild captain.'));
      expect(user, contains('TARGET PERSONA'));
      expect(user, contains('Val'));
      expect(user, contains('Heir of House Blackwood.'));
      expect(user, contains('Childhood friend of Mira.'));
    });
  });
}
