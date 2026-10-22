import 'package:flutter_test/flutter_test.dart';

import 'package:anima/models/chat_message.dart';
import 'package:anima/models/living_world.dart';
import 'package:anima/services/living_world_factory_service.dart';
import 'package:anima/services/living_world_retriever.dart';

void main() {
  const retriever = LivingWorldRetriever();

  group('Phase 10 linked speaker hard-pin', () {
    test('linked card is first even with no name mention or place', () {
      final world = LivingWorld(
        id: 'w_pin',
        title: 'Pin',
        people: const [
          WorldPerson(
            id: 'p_other',
            name: 'Other',
            summary: 'Bystander at market',
          ),
          WorldPerson(
            id: 'p_linked',
            name: 'Quiet Clerk',
            summary: 'Keeps to themselves',
            characterCardId: 'card_quiet',
          ),
        ],
        places: const [WorldPlace(id: 'pl_market', name: 'Market')],
        liveState: const WorldLiveState(
          activePlaceId: 'pl_market',
          personLocations: {'p_other': 'pl_market'},
        ),
        threads: const [
          WorldThread(
            id: 'th_speaker',
            title: 'Quiet clerk debt',
            summary: 'Owes the dockmaster.',
            personIds: ['p_linked'],
            status: WorldContinuityStatus.open,
          ),
          WorldThread(
            id: 'th_other',
            title: 'Market gossip',
            summary: 'Rumors about the crate.',
            personIds: ['p_other'],
            status: WorldContinuityStatus.open,
          ),
        ],
      );

      final pack = retriever.retrieve(
        world: world,
        recentMessages: const [],
        speakerName: 'Totally Different Name',
        speakerCharacterId: 'card_quiet',
        userName: 'Jay',
        tokenBudget: 400,
      );

      expect(pack.speakingPersonId, 'p_linked');
      expect(pack.people, isNotEmpty);
      expect(pack.people.first.id, 'p_linked');
      expect(pack.threads.map((t) => t.id), contains('th_speaker'));
      // Speaker thread stays ahead of unrelated continuity under a tight budget.
      expect(pack.threads.first.id, 'th_speaker');
    });

    test('fitBudget never drops the sole linked speaker', () {
      final world = LivingWorld(
        id: 'w_budget',
        title: 'Budget',
        genreNote: 'Long setting note. ' * 40,
        people: [
          WorldPerson(
            id: 'p1',
            name: 'Mira',
            summary: 'Detailed summary. ' * 30,
            characterCardId: 'card_mira',
            personalityNotes: 'Notes. ' * 30,
          ),
          const WorldPerson(
            id: 'p2',
            name: 'Extra',
            summary: 'Padding person for trim',
          ),
        ],
        places: const [
          WorldPlace(id: 'pl1', name: 'Pier', description: 'Working docks'),
        ],
        threads: const [
          WorldThread(
            id: 'th1',
            title: 'Mira letter',
            summary: 'Open loop for Mira',
            personIds: ['p1'],
          ),
        ],
        liveState: const WorldLiveState(activePlaceId: 'pl1'),
      );

      final pack = retriever.retrieve(
        world: world,
        recentMessages: [
          ChatMessage(
            id: 'm1',
            role: ChatRole.user,
            text: 'Mira, tell me everything about the pier.',
          ),
        ],
        speakerName: 'Mira',
        speakerCharacterId: 'card_mira',
        userName: 'Jay',
        tokenBudget: 120,
      );

      expect(pack.people, isNotEmpty);
      expect(pack.people.first.id, 'p1');
      expect(pack.speakingPersonId, 'p1');
    });
  });

  group('Phase 10 factory workshop seed', () {
    test('brainstormFromWorkshop builds one-way pitch', () {
      final pitch = LivingWorldFactoryRequest.brainstormFromWorkshop(
        title: 'Harbor Workshop',
        worldSummary: 'Rainy docks and a missing crate.',
        characterLines: const [
          'Mira — Pier clerk who keeps a ledger.',
          'Edric — Dockworker.',
        ],
        personaLine: 'Jay — Curious traveler.',
      );
      expect(pitch, contains('Harbor Workshop'));
      expect(pitch, contains('missing crate'));
      expect(pitch, contains('Mira'));
      expect(pitch, contains('Linked character cards'));
      expect(pitch, contains('Linked player persona'));
      expect(pitch, contains('Jay'));
    });

    test('empty workshop yields empty brainstorm', () {
      expect(
        LivingWorldFactoryRequest.brainstormFromWorkshop(title: '  '),
        isEmpty,
      );
    });
  });
}
