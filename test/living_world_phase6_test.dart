import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:anima/models/living_world_update_policy.dart';
import 'package:anima/models/turn_resolution.dart';
import 'package:anima/services/living_world_log_service.dart';
import 'package:anima/services/living_world_retriever.dart';
import 'package:anima/services/living_world_service.dart';
import 'package:anima/services/living_world_turn_resolver.dart';
import 'package:anima/services/living_world_update_service.dart';
import 'package:anima/widgets/living_world_picker.dart';

void main() {
  group('TurnResolution', () {
    test('formatAsOfTurnBlock lists applied facts', () {
      final block = TurnResolution.formatAsOfTurnBlock([
        const LivingWorldCanonUpdate(
          op: LivingWorldUpdateOp.setActivePlace,
          summary: 'Active place → Pier',
          activePlaceId: 'pl_pier',
        ),
        const LivingWorldCanonUpdate(
          op: LivingWorldUpdateOp.addEvent,
          summary: 'Mira decided to stay the night.',
        ),
      ]);
      expect(block, contains('as of this turn'));
      expect(block, contains('Active place → Pier'));
      expect(block, contains('Mira decided to stay the night.'));
      expect(block, contains('already true'));
    });

    test('formatAsOfTurnBlock empty when nothing applied', () {
      expect(TurnResolution.formatAsOfTurnBlock(const []), isEmpty);
    });

    test('toJson / fromJson round-trip', () {
      final original = TurnResolution(
        worldId: 'w1',
        at: DateTime.utc(2026, 10, 20, 12, 0),
        kind: TurnResolutionKind.resolveBeforeNarrate,
        applied: const [
          LivingWorldCanonUpdate(
            op: LivingWorldUpdateOp.setFlag,
            summary: 'doors_locked = true',
          ),
        ],
        deferred: const [
          LivingWorldCanonUpdate(
            op: LivingWorldUpdateOp.setRelationship,
            summary: 'A → B: 40',
          ),
        ],
        chatId: 'c1',
      );
      final restored = TurnResolution.fromJson(original.toJson());
      expect(restored.worldId, 'w1');
      expect(restored.kind, TurnResolutionKind.resolveBeforeNarrate);
      expect(restored.applied, hasLength(1));
      expect(restored.applied.single.summary, 'doors_locked = true');
      expect(restored.deferred, hasLength(1));
      expect(restored.chatId, 'c1');
    });
  });

  group('LivingWorldTurnResolver', () {
    const resolver = LivingWorldTurnResolver();

    test('manual policy applies nothing immediately', () {
      final proposed = [
        const LivingWorldCanonUpdate(
          op: LivingWorldUpdateOp.setFlag,
          summary: 'f',
        ),
        const LivingWorldCanonUpdate(
          op: LivingWorldUpdateOp.setRelationship,
          summary: 'r',
        ),
      ];
      expect(
        resolver.selectForImmediateApply(
          proposed,
          policy: LivingWorldUpdatePolicy.manual,
        ),
        isEmpty,
      );
      expect(
        resolver.selectDeferred(
          proposed,
          policy: LivingWorldUpdatePolicy.manual,
        ),
        isEmpty,
      );
    });

    test('autoSafe / propose: safe immediate, relationships deferred', () {
      final proposed = [
        const LivingWorldCanonUpdate(
          op: LivingWorldUpdateOp.setActivePlace,
          summary: 'Pier',
          activePlaceId: 'pl_pier',
        ),
        const LivingWorldCanonUpdate(
          op: LivingWorldUpdateOp.setRelationship,
          summary: 'rel',
        ),
      ];
      for (final policy in [
        LivingWorldUpdatePolicy.autoSafe,
        LivingWorldUpdatePolicy.proposeAfterTurn,
      ]) {
        final immediate = resolver.selectForImmediateApply(
          proposed,
          policy: policy,
        );
        final deferred = resolver.selectDeferred(proposed, policy: policy);
        expect(immediate, hasLength(1));
        expect(immediate.single.op, LivingWorldUpdateOp.setActivePlace);
        expect(deferred, hasLength(1));
        expect(deferred.single.op, LivingWorldUpdateOp.setRelationship);
      }
    });

    test('persist-before-narrate: retrieve sees applied place', () {
      // Ordering proof: apply → retrieve → pack includes new active place
      // (same order Living mode uses before streaming the reply).
      final world = buildSampleHarborWorld();
      expect(world.liveState?.activePlaceId, 'pl_pier');

      final proposed = [
        const LivingWorldCanonUpdate(
          op: LivingWorldUpdateOp.setActivePlace,
          summary: 'Active place → Harbor Inn',
          activePlaceId: 'pl_inn',
        ),
        const LivingWorldCanonUpdate(
          op: LivingWorldUpdateOp.setRelationship,
          summary: 'skip me',
        ),
      ];

      final result = resolver.resolveBeforeNarrate(
        world: world,
        proposed: proposed,
        policy: LivingWorldUpdatePolicy.autoSafe,
      );

      expect(result.resolution.kind, TurnResolutionKind.resolveBeforeNarrate);
      expect(result.resolution.applied, hasLength(1));
      expect(result.resolution.deferred, hasLength(1));
      expect(result.world.liveState?.activePlaceId, 'pl_inn');

      // Narrate step would load this pack next — prove the fact is visible.
      const retriever = LivingWorldRetriever();
      final pack = retriever.retrieve(
        world: result.world,
        recentMessages: const [],
        speakerName: 'Mira',
      );
      expect(pack.liveState?.activePlaceId, 'pl_inn');
      expect(pack.places.any((p) => p.id == 'pl_inn'), isTrue);
      expect(result.resolution.asOfTurnBlock, contains('Harbor Inn'));
    });
  });

  group('LivingWorldLogService', () {
    late Directory tempDir;
    late LivingWorldLogService logs;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('anima_world_log_');
      logs = LivingWorldLogService(
        documentsDirectory: () async => tempDir,
        maxEntries: 3,
      );
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('append + list newest first; trims to maxEntries', () async {
      final world = buildSampleHarborWorld();
      await LivingWorldService(
        documentsDirectory: () async => tempDir,
      ).save(world);

      for (var i = 0; i < 4; i++) {
        await logs.append(
          TurnResolution(
            worldId: world.id,
            at: DateTime.utc(2026, 10, 20, i),
            kind: TurnResolutionKind.afterTurn,
            applied: [
              LivingWorldCanonUpdate(
                op: LivingWorldUpdateOp.addEvent,
                summary: 'event_$i',
              ),
            ],
          ),
        );
      }

      final entries = await logs.listEntries(world.id);
      expect(entries, hasLength(3));
      expect(entries.first.applied.single.summary, 'event_3');
      expect(entries.last.applied.single.summary, 'event_1');
    });

    test('skips empty resolutions', () async {
      await logs.append(
        TurnResolution(
          worldId: 'w_empty',
          at: DateTime.now(),
          kind: TurnResolutionKind.afterTurn,
        ),
      );
      expect(await logs.listEntries('w_empty'), isEmpty);
    });
  });
}
