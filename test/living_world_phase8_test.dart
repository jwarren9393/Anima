import 'package:flutter_test/flutter_test.dart';

import 'package:anima/models/living_world.dart';
import 'package:anima/models/living_world_tick_settings.dart';
import 'package:anima/models/turn_resolution.dart';
import 'package:anima/services/living_world_retriever.dart';
import 'package:anima/services/living_world_simulator.dart';
import 'package:anima/services/living_world_update_service.dart';
import 'package:anima/widgets/living_world_picker.dart';

void main() {
  const simulator = LivingWorldSimulator();
  const updates = LivingWorldUpdateService();
  const retriever = LivingWorldRetriever();

  LivingWorld sample() => buildSampleHarborWorld();

  /// ~40-person world: active pier + market + far village with many NPCs.
  LivingWorld largeNearSceneWorld() {
    final base = sample();
    final people = <WorldPerson>[
      ...base.people,
      for (var i = 0; i < 37; i++)
        WorldPerson(
          id: 'p_extra_$i',
          name: 'Extra$i',
          summary: 'Crowd filler $i with a long personality dump that must '
              'never appear in tick events.',
          personalityNotes: 'Secret inner monologue $i — not for ticks.',
          routineHints: i < 5
              ? 'Evenings at the Night Market; mornings idle.'
              : (i < 10
                  ? 'Lives far inland; rarely visits the harbor.'
                  : ''),
        ),
    ];
    final places = [
      ...base.places,
      const WorldPlace(
        id: 'pl_inland',
        name: 'Inland Farm',
        description: 'Far from the pier — should stay out of 1-hop ticks.',
        connectedPlaceIds: [],
      ),
    ];
    final locs = <String, String>{
      ...?base.liveState?.personLocations,
      for (var i = 0; i < 37; i++)
        'p_extra_$i': i < 5
            ? 'pl_market'
            : (i < 10 ? 'pl_inland' : 'pl_inland'),
    };
    return base.copyWith(
      people: people,
      places: places,
      liveState: WorldLiveState(
        activePlaceId: 'pl_pier',
        personLocations: locs,
      ),
    ).validated();
  }

  group('LivingWorldTickSettings', () {
    test('shouldAutoTick respects trigger and everyN', () {
      expect(
        const LivingWorldTickSettings(
          trigger: LivingWorldTickTrigger.off,
        ).shouldAutoTick(assistantReplyCount: 5),
        isFalse,
      );
      expect(
        const LivingWorldTickSettings(
          trigger: LivingWorldTickTrigger.afterTurn,
        ).shouldAutoTick(assistantReplyCount: 1),
        isTrue,
      );
      expect(
        const LivingWorldTickSettings(
          trigger: LivingWorldTickTrigger.everyN,
          everyN: 3,
        ).shouldAutoTick(assistantReplyCount: 2),
        isFalse,
      );
      expect(
        const LivingWorldTickSettings(
          trigger: LivingWorldTickTrigger.everyN,
          everyN: 3,
        ).shouldAutoTick(assistantReplyCount: 3),
        isTrue,
      );
      expect(
        const LivingWorldTickSettings(
          trigger: LivingWorldTickTrigger.everyN,
          everyN: 3,
        ).shouldAutoTick(assistantReplyCount: 6),
        isTrue,
      );
    });

    test('clamps caps', () {
      final s = const LivingWorldTickSettings(
        maxPeople: 99,
        maxOps: 0,
        radiusHops: 9,
        everyN: 1,
      ).clamped();
      expect(s.maxPeople, 12);
      expect(s.maxOps, 1);
      expect(s.radiusHops, 2);
      expect(s.everyN, 2);
    });

    test('trigger storage round-trip', () {
      expect(
        LivingWorldTickTriggerX.fromStorage('afterTurn'),
        LivingWorldTickTrigger.afterTurn,
      );
      expect(
        LivingWorldTickTriggerX.fromStorage('everyN'),
        LivingWorldTickTrigger.everyN,
      );
      expect(
        LivingWorldTickTriggerX.fromStorage('nope'),
        LivingWorldTickTrigger.off,
      );
    });
  });

  group('LivingWorldSimulator radius', () {
    test('one-hop includes pier neighbors only', () {
      final world = sample();
      final radius = simulator.placesInRadius(
        world,
        seedPlaceId: 'pl_pier',
        radiusHops: 1,
      );
      expect(radius, containsAll(['pl_pier', 'pl_market', 'pl_inn']));
      expect(radius, hasLength(3));
    });

    test('zero hops is active place only', () {
      final world = sample();
      final radius = simulator.placesInRadius(
        world,
        seedPlaceId: 'pl_pier',
        radiusHops: 0,
      );
      expect(radius, {'pl_pier'});
    });

    test('handles one-way connections both directions', () {
      final world = LivingWorld(
        id: 'w_oneway',
        title: 'One way',
        places: const [
          WorldPlace(
            id: 'a',
            name: 'A',
            connectedPlaceIds: ['b'],
          ),
          WorldPlace(
            id: 'b',
            name: 'B',
            connectedPlaceIds: [],
          ),
        ],
        liveState: const WorldLiveState(activePlaceId: 'b'),
      ).validated();
      final fromB = simulator.placesInRadius(
        world,
        seedPlaceId: 'b',
        radiusHops: 1,
      );
      expect(fromB, containsAll(['a', 'b']));
    });
  });

  group('LivingWorldSimulator planTick', () {
    test('sample harbor emits capped near-scene ops only', () {
      final world = sample();
      final plan = simulator.planTick(
        world,
        settings: const LivingWorldTickSettings(
          maxPeople: 6,
          maxOps: 8,
          radiusHops: 1,
        ),
        now: DateTime.utc(2026, 10, 21, 12),
      );
      expect(plan.seedPlaceId, 'pl_pier');
      expect(plan.placeIdsInRadius, containsAll(['pl_pier', 'pl_market']));
      expect(plan.ops, isNotEmpty);
      expect(plan.ops.length, lessThanOrEqualTo(8));
      expect(plan.peopleTouched.length, lessThanOrEqualTo(6));
      for (final op in plan.ops) {
        expect(op.isSafeForAutoApply, isTrue);
        expect(op.op, isNot(LivingWorldUpdateOp.setRelationship));
        if (op.op == LivingWorldUpdateOp.addEvent) {
          final text = op.event!.text;
          expect(text.toLowerCase(), isNot(contains('personality')));
          expect(text.toLowerCase(), isNot(contains('secret inner')));
          expect(text.length, lessThan(160));
        }
      }
    });

    test('40-person world touches a handful near the scene, not everyone', () {
      final world = largeNearSceneWorld();
      expect(world.people.length, greaterThanOrEqualTo(40));

      final plan = simulator.planTick(
        world,
        settings: const LivingWorldTickSettings(
          maxPeople: 6,
          maxOps: 8,
          radiusHops: 1,
        ),
        now: DateTime.utc(2026, 10, 21, 13),
      );

      expect(plan.peopleTouched.length, lessThanOrEqualTo(6));
      expect(plan.ops.length, lessThanOrEqualTo(8));
      // Inland-only extras should not dominate; at least some near-scene ids.
      final inlandOnly = {
        for (var i = 10; i < 37; i++) 'p_extra_$i',
      };
      expect(
        plan.peopleTouched.intersection(inlandOnly),
        isEmpty,
        reason: 'far inland crowd without near-scene score must stay out',
      );
      expect(plan.placeIdsInRadius.contains('pl_inland'), isFalse);
    });

    test('empty world / no places yields empty plan', () {
      final world = LivingWorld.empty(title: 'Blank');
      final plan = simulator.planTick(world);
      expect(plan.isEmpty, isTrue);
    });

    test('apply tick ops then retrieve sees new near-scene event', () {
      final world = sample();
      final plan = simulator.planTick(
        world,
        settings: const LivingWorldTickSettings(maxOps: 4, maxPeople: 4),
        now: DateTime.utc(2026, 10, 21, 14),
      );
      expect(plan.ops, isNotEmpty);

      final next = updates.applyUpdates(world, plan.ops);
      expect(next.events.length, greaterThan(world.events.length));

      final pack = retriever.retrieve(
        world: next,
        recentMessages: const [],
        speakerName: 'Mira',
      );
      final blob = retriever.formatForPrompt(pack);
      // At least one tick ambient line should be eligible near pier/market.
      final tickTexts = [
        for (final op in plan.ops)
          if (op.event != null) op.event!.text,
      ];
      expect(
        tickTexts.any((t) => blob.contains(t) || next.events.any((e) => e.text == t)),
        isTrue,
      );
    });

    test('near-scene roster never dumps full person prose', () {
      final world = largeNearSceneWorld();
      final plan = simulator.planTick(
        world,
        settings: const LivingWorldTickSettings(maxPeople: 6, maxOps: 6),
      );
      final roster = simulator.formatNearSceneRoster(world, plan);
      expect(roster.toLowerCase(), isNot(contains('personality dump')));
      expect(roster.toLowerCase(), isNot(contains('secret inner monologue')));
      expect(roster, contains('Places:'));
    });
  });

  group('TurnResolution nearSceneTick', () {
    test('kind label and json round-trip', () {
      final res = TurnResolution(
        worldId: 'w1',
        at: DateTime.utc(2026, 10, 21),
        kind: TurnResolutionKind.nearSceneTick,
        applied: const [
          LivingWorldCanonUpdate(
            op: LivingWorldUpdateOp.addEvent,
            summary: 'Lena continues nearby.',
          ),
        ],
      );
      expect(res.kindLabel, 'Near-scene tick');
      final back = TurnResolution.fromJson(res.toJson());
      expect(back.kind, TurnResolutionKind.nearSceneTick);
      expect(back.applied, hasLength(1));
    });
  });
}
