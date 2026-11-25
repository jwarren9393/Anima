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

    test('consistency check is read-only and includes full card', () {
      final messages = collaborator.buildConsistencyCheckMessages(
        draft: const CharacterDraftContext(
          name: 'Rin',
          description: 'Tall scout.',
          personality: 'Quiet.',
          firstMes: '*waves* "Hi."',
        ),
      );
      expect(messages[0]['content'], contains('READ-ONLY'));
      expect(messages[0]['content'], contains('complete the report'));
      expect(messages[1]['content'], contains('Tall scout'));
      expect(messages[1]['content'], contains('Quiet'));
      expect(messages[1]['content'], contains('waves'));
    });

    test('consistency fix asks for JSON and includes report', () {
      final messages = collaborator.buildConsistencyFixMessages(
        draft: const CharacterDraftContext(
          name: 'Rin',
          description: 'Tall scout.',
          personality: 'Quiet.',
        ),
        consistencyReport: '- Age contradicts description.',
      );
      expect(messages[0]['content'], contains('JSON'));
      expect(messages[0]['content'], contains('personality = temperament'));
      expect(messages[1]['content'], contains('Age contradicts'));
      expect(messages[1]['content'], contains('Tall scout'));
    });

    test('compact asks for shorter JSON card', () {
      final messages = collaborator.buildCompactMessages(
        draft: CharacterDraftContext(
          name: 'Rin',
          description: 'A' * 120,
          personality: 'Quiet and watchful.',
        ),
      );
      expect(messages[0]['content'], contains('compact'));
      expect(messages[0]['content'], contains('30–50%'));
      expect(messages[0]['content'], contains('JSON'));
      expect(messages[1]['content'], contains('Rin'));
    });

    test('expand asks for richer JSON card while keeping identity', () {
      final messages = collaborator.buildExpandMessages(
        draft: CharacterDraftContext(
          name: 'Rin',
          description: 'Tall scout.',
          personality: 'Quiet and watchful.',
        ),
      );
      final system = messages[0]['content']!;
      final user = messages[1]['content']!;
      expect(system, contains('expand'));
      expect(system, contains('Invent interesting ideas'));
      expect(system, contains('Keep the same character identity'));
      expect(system, contains('chara_card_v2'));
      expect(user, contains('CURRENT CHARACTER CARD (expand this'));
      expect(user, contains('Rin'));
      expect(user, contains('Tall scout.'));
    });

    test('cross-reference grounds target in source world', () {
      final messages = collaborator.buildCrossReferenceMessages(
        draft: const CharacterDraftContext(
          name: 'Rin',
          description: 'Tall scout.',
        ),
        sourceLabel: 'Character: Mira',
        sourceBlock: 'Name:\nMira\n\nPersonality:\nBold guild captain.',
        notes: 'Old rivals from the Guild.',
      );
      final system = messages[0]['content']!;
      final user = messages[1]['content']!;

      expect(messages.length, 2);
      expect(system, contains('CROSS-REFERENCE'));
      expect(system, contains('The TARGET comes first'));
      expect(system, contains('do NOT copy the source bio wholesale'));
      expect(system, contains('chara_card_v2'));
      expect(user, contains('SOURCE CARD (reference material — Character: Mira)'));
      expect(user, contains('Bold guild captain.'));
      expect(user, contains('TARGET CHARACTER CARD'));
      expect(user, contains('Rin'));
      expect(user, contains('Tall scout.'));
      expect(user, contains('Old rivals from the Guild.'));
    });

    test('cross-reference omits connection notes when empty', () {
      final messages = collaborator.buildCrossReferenceMessages(
        draft: const CharacterDraftContext(name: 'Rin'),
        sourceLabel: 'Persona: Ash',
        sourceBlock: 'Name:\nAsh',
      );
      expect(messages[1]['content'], isNot(contains('HOW THEY CONNECT')));
      expect(
        messages[1]['content'],
        contains('SOURCE CARD (reference material — Persona: Ash)'),
      );
    });
  });
}
