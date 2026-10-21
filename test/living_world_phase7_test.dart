import 'package:flutter_test/flutter_test.dart';

import 'package:anima/models/living_world.dart';
import 'package:anima/services/living_world_retriever.dart';
import 'package:anima/services/living_world_systems_service.dart';
import 'package:anima/services/living_world_update_service.dart';
import 'package:anima/widgets/living_world_picker.dart';

void main() {
  const systems = LivingWorldSystemsService();
  const updates = LivingWorldUpdateService();

  LivingWorld sample() => buildSampleHarborWorld();

  group('relationship drift', () {
    test('aid event nudges scores both ways and clamps', () {
      final world = sample();
      final miraEdric = world.relationships.firstWhere(
        (r) => r.fromId == 'p_mira' && r.toId == 'p_edric',
      );
      expect(miraEdric.score, 40);

      final event = WorldEvent(
        id: 'e_aid',
        text: 'Mira helped Edric seal the crate at dawn.',
        placeId: 'pl_pier',
        personIds: const ['p_mira', 'p_edric'],
      );
      final next = updates.applyUpdates(world, [
        LivingWorldCanonUpdate(
          op: LivingWorldUpdateOp.addEvent,
          summary: event.text,
          event: event,
        ),
      ]);

      final after = next.relationships.firstWhere(
        (r) => r.fromId == 'p_mira' && r.toId == 'p_edric',
      );
      expect(after.score, 48); // +8 aid
      expect(after.labels, contains('aid'));

      final reverse = next.relationships.firstWhere(
        (r) => r.fromId == 'p_edric' && r.toId == 'p_mira',
      );
      expect(reverse.score, 43); // was 35 + 8
      expect(reverse.labels, contains('aid'));
    });

    test('betrayal clamps at -100', () {
      final world = sample().copyWith(
        relationships: const [
          WorldRelationship(
            fromId: 'p_mira',
            toId: 'p_edric',
            score: -95,
            labels: ['tense'],
          ),
        ],
      );
      final event = WorldEvent(
        id: 'e_betray',
        text: 'Mira betrayed Edric by selling the pier ledger.',
        personIds: const ['p_mira', 'p_edric'],
      );
      final next = updates.applyUpdates(world, [
        LivingWorldCanonUpdate(
          op: LivingWorldUpdateOp.addEvent,
          summary: event.text,
          event: event,
        ),
      ]);
      final after = next.relationships.firstWhere(
        (r) => r.fromId == 'p_mira' && r.toId == 'p_edric',
      );
      expect(after.score, -100);
      expect(after.labels, contains('betrayal'));
    });

    test('explicit setRelationship in same batch skips drift for that pair', () {
      final world = sample();
      final event = WorldEvent(
        id: 'e_aid2',
        text: 'Mira helped Edric again.',
        personIds: const ['p_mira', 'p_edric'],
      );
      final next = updates.applyUpdates(world, [
        LivingWorldCanonUpdate(
          op: LivingWorldUpdateOp.addEvent,
          summary: event.text,
          event: event,
        ),
        const LivingWorldCanonUpdate(
          op: LivingWorldUpdateOp.setRelationship,
          summary: 'forced',
          relationship: WorldRelationship(
            fromId: 'p_mira',
            toId: 'p_edric',
            score: 70,
            labels: ['allies'],
          ),
        ),
      ]);
      final after = next.relationships.firstWhere(
        (r) => r.fromId == 'p_mira' && r.toId == 'p_edric',
      );
      // Explicit score wins for this directed pair (no +8 on top).
      expect(after.score, 70);
      expect(after.labels, ['allies']);
    });

    test('unknown person ids never create relationships', () {
      final world = sample();
      final event = WorldEvent(
        id: 'e_ghost',
        text: 'Mira helped Ghost with the crate.',
        personIds: const ['p_mira', 'p_ghost'],
      );
      // validated() strips unknown person ids from events before enrich…
      // apply path keeps only known ids on the event object we pass in,
      // but enrich filters again — ghost id is not in world.people.
      final next = updates.applyUpdates(world, [
        LivingWorldCanonUpdate(
          op: LivingWorldUpdateOp.addEvent,
          summary: event.text,
          event: event,
        ),
      ]);
      // Event kept but ghost id stripped by validated(); only 1 person → no drift.
      final cleaned = next.events.last;
      expect(cleaned.personIds, ['p_mira']);
      final miraEdric = next.relationships.firstWhere(
        (r) => r.fromId == 'p_mira' && r.toId == 'p_edric',
      );
      expect(miraEdric.score, 40); // unchanged
    });
  });

  group('flag recipes', () {
    test('knows recipe sets stable key from primary person', () {
      final world = sample();
      final event = WorldEvent(
        id: 'e_know',
        text: 'Mira discovered the sealed letter under the pier.',
        placeId: 'pl_pier',
        personIds: const ['p_mira'],
      );
      final next = updates.applyUpdates(world, [
        LivingWorldCanonUpdate(
          op: LivingWorldUpdateOp.addEvent,
          summary: event.text,
          event: event,
        ),
      ]);
      expect(
        next.flags.any((f) => f.key == 'knows_mira' && f.value == true),
        isTrue,
      );
    });

    test('banished recipe needs person + place', () {
      final world = sample();
      final event = WorldEvent(
        id: 'e_ban',
        text: 'Edric was banished from the Harbor Inn after the fight.',
        placeId: 'pl_inn',
        personIds: const ['p_edric'],
      );
      final next = updates.applyUpdates(world, [
        LivingWorldCanonUpdate(
          op: LivingWorldUpdateOp.addEvent,
          summary: event.text,
          event: event,
        ),
      ]);
      expect(
        next.flags.any((f) => f.key == 'banished_from_harbor_inn'),
        isTrue,
      );
    });
  });

  group('presence sync', () {
    test('arrivals write personLocations at active place', () {
      final world = sample();
      final ops = systems.presenceOpsFromNarrator(
        world: world,
        presentNames: const {'Mira'},
        arrivingNames: const {'Lena'},
      );
      expect(ops, isNotEmpty);
      final next = updates.applyUpdates(world, ops, runSystems: false);
      expect(next.liveState?.personLocations['p_lena'], 'pl_pier');
      expect(next.liveState?.personLocations['p_mira'], 'pl_pier');
    });

    test('departures clear locations; retrieve sees the move', () {
      final world = sample();
      expect(world.liveState?.personLocations['p_edric'], 'pl_pier');

      final departed = systems.resolveDepartedPersonIds(
        world: world,
        departedNames: const {'Edric'},
      );
      expect(departed, {'p_edric'});

      final next = systems.clearDeparted(
        world: world,
        departedPersonIds: departed,
      );
      expect(next.liveState?.personLocations.containsKey('p_edric'), isFalse);

      // Move Mira to inn via op — retrieve shows it without hand-editing JSON.
      final moved = updates.applyUpdates(
        next,
        const [
          LivingWorldCanonUpdate(
            op: LivingWorldUpdateOp.setPersonLocation,
            summary: 'Mira @ inn',
            personId: 'p_mira',
            placeId: 'pl_inn',
          ),
        ],
        runSystems: false,
      );
      expect(moved.liveState?.personLocations['p_mira'], 'pl_inn');

      const retriever = LivingWorldRetriever();
      final pack = retriever.retrieve(
        world: moved,
        recentMessages: const [],
        speakerName: 'Mira',
        userName: 'Jay',
      );
      final body = pack.renderBody();
      expect(body, contains('Mira @ Harbor Inn'));
    });

    test('unknown departure names are ignored', () {
      final world = sample();
      final ids = systems.resolveDepartedPersonIds(
        world: world,
        departedNames: const {'Nobody'},
      );
      expect(ids, isEmpty);
    });
  });

  group('routineHints', () {
    test('round-trips on WorldPerson and shows in retrieve', () {
      final person = const WorldPerson(
        id: 'p_x',
        name: 'X',
        routineHints: 'Nights at the market',
      );
      final json = person.toJson();
      final back = WorldPerson.fromJson(json);
      expect(back.routineHints, 'Nights at the market');

      final world = sample();
      expect(world.people.first.routineHints, contains('pier'));

      const retriever = LivingWorldRetriever();
      final pack = retriever.retrieve(
        world: world,
        recentMessages: const [],
        speakerName: 'Mira',
        userName: 'Jay',
      );
      expect(pack.renderBody(), contains('routine:'));
    });
  });
}
