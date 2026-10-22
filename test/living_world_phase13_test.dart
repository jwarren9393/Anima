import 'package:flutter_test/flutter_test.dart';

import 'package:anima/models/chat_message.dart';
import 'package:anima/models/chat_session.dart';
import 'package:anima/models/living_world.dart';
import 'package:anima/services/living_world_card_bridge.dart';

void main() {
  const bridge = LivingWorldCardBridge();

  LivingWorld sampleWorld() {
    return LivingWorld(
      id: 'w_harbor',
      title: 'Harbor Town',
      genreNote: 'Quiet coastal slice-of-life',
      people: const [
        WorldPerson(
          id: 'p_mira',
          name: 'Mira',
          summary: 'Dock clerk who keeps the pier ledger.',
          personalityNotes: 'Dry humor; loyal to the crew.',
          routineHints: 'Mornings at the pier; evenings at the inn',
          inventory: ['ledger', 'ink stick'],
        ),
        WorldPerson(
          id: 'p_jon',
          name: 'Jon',
          summary: 'Retired sailor.',
        ),
      ],
      places: const [
        WorldPlace(
          id: 'pl_pier',
          name: 'Pier',
          description: 'Salt air and creaking boards.',
        ),
      ],
      relationships: const [
        WorldRelationship(
          fromId: 'p_mira',
          toId: 'p_jon',
          score: 40,
          labels: ['trusts'],
        ),
      ],
      liveState: const WorldLiveState(
        activePlaceId: 'pl_pier',
        personLocations: {'p_mira': 'pl_pier'},
      ),
    );
  }

  group('Phase 13 draft mapping', () {
    test('buildPersonBrief includes summary, place, and relationships', () {
      final world = sampleWorld();
      final person = world.people.first;
      final brief = bridge.buildPersonBrief(world: world, person: person);

      expect(brief, contains('Harbor Town'));
      expect(brief, contains('Mira'));
      expect(brief, contains('Dock clerk'));
      expect(brief, contains('Dry humor'));
      expect(brief, contains('Pier'));
      expect(brief, contains('trusts'));
      expect(brief, contains('Jon'));
      expect(brief, contains('ledger'));
    });

    test('seedCharacterFromPerson maps notebook fields', () {
      final person = sampleWorld().people.first;
      final card = bridge.seedCharacterFromPerson(person, id: 'char_mira');

      expect(card.id, 'char_mira');
      expect(card.name, 'Mira');
      expect(card.description, contains('Dock clerk'));
      expect(card.description, contains('Routine:'));
      expect(card.description, contains('ledger'));
      expect(card.personality, contains('Dry humor'));
      expect(card.firstMes.trim(), isNotEmpty);
      expect(card.creator, 'Anima Living World');
    });

    test('seedPersonaFromPerson maps notebook fields', () {
      final person = sampleWorld().people.first;
      final persona = bridge.seedPersonaFromPerson(person, id: 'persona_mira');

      expect(persona.id, 'persona_mira');
      expect(persona.name, 'Mira');
      expect(persona.description, contains('Dock clerk'));
      expect(persona.personality, contains('Dry humor'));
      expect(persona.background, contains('Routine:'));
    });
  });

  group('Phase 13 link-on-accept', () {
    test('linkPersonToCharacter sets characterCardId', () {
      final world = sampleWorld();
      final linked = bridge.linkPersonToCharacter(
        world,
        personId: 'p_mira',
        characterId: 'char_mira',
      );

      final mira = linked.people.firstWhere((p) => p.id == 'p_mira');
      expect(mira.characterCardId, 'char_mira');
      expect(
        linked.people.firstWhere((p) => p.id == 'p_jon').characterCardId,
        isNull,
      );
    });

    test('linkPersonToCharacter no-ops on unknown person', () {
      final world = sampleWorld();
      final linked = bridge.linkPersonToCharacter(
        world,
        personId: 'p_missing',
        characterId: 'char_x',
      );
      expect(identical(linked, world), isTrue);
      expect(
        linked.people.every((p) => (p.characterCardId ?? '').isEmpty),
        isTrue,
      );
    });
  });

  group('Phase 13 chat bind helper', () {
    test('bindSessionToWorld sets worldId', () {
      final session = ChatSession(
        id: 'chat_1',
        characterId: 'char_mira',
        title: 'Mira',
        updatedAt: DateTime.utc(2026, 10, 21),
        messages: [
          ChatMessage(
            id: 'm1',
            role: ChatRole.assistant,
            text: 'Hello',
          ),
        ],
      );

      final bound = bridge.bindSessionToWorld(session, 'w_harbor');
      expect(bound.worldId, 'w_harbor');
      expect(bound.hasLivingWorld, isTrue);

      final empty = bridge.bindSessionToWorld(session, '  ');
      expect(empty.worldId, isNull);
    });
  });
}
