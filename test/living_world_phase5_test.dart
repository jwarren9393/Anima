import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:anima/models/living_world.dart';
import 'package:anima/models/living_world_update_policy.dart';
import 'package:anima/services/living_world_service.dart';
import 'package:anima/services/living_world_undo_service.dart';
import 'package:anima/services/living_world_update_service.dart';
import 'package:anima/widgets/living_world_picker.dart';

void main() {
  group('LivingWorldUpdatePolicy', () {
    test('round-trips storage values', () {
      expect(
        LivingWorldUpdatePolicyX.fromStorage('manual'),
        LivingWorldUpdatePolicy.manual,
      );
      expect(
        LivingWorldUpdatePolicyX.fromStorage('propose'),
        LivingWorldUpdatePolicy.proposeAfterTurn,
      );
      expect(
        LivingWorldUpdatePolicyX.fromStorage('autoSafe'),
        LivingWorldUpdatePolicy.autoSafe,
      );
      expect(
        LivingWorldUpdatePolicyX.fromStorage('nope'),
        LivingWorldUpdatePolicy.manual,
      );
      expect(LivingWorldUpdatePolicy.autoSafe.storageValue, 'autoSafe');
    });
  });

  group('LivingWorldUpdateService Phase 5', () {
    const service = LivingWorldUpdateService();

    test('isSafeForAutoApply marks relationships as risky', () {
      expect(
        const LivingWorldCanonUpdate(
          op: LivingWorldUpdateOp.addEvent,
          summary: 'e',
        ).isSafeForAutoApply,
        isTrue,
      );
      expect(
        const LivingWorldCanonUpdate(
          op: LivingWorldUpdateOp.setRelationship,
          summary: 'r',
        ).isSafeForAutoApply,
        isFalse,
      );
    });

    test('partitionForAutoSafe splits lists', () {
      final parts = service.partitionForAutoSafe([
        const LivingWorldCanonUpdate(
          op: LivingWorldUpdateOp.setFlag,
          summary: 'f',
        ),
        const LivingWorldCanonUpdate(
          op: LivingWorldUpdateOp.setRelationship,
          summary: 'r',
        ),
        const LivingWorldCanonUpdate(
          op: LivingWorldUpdateOp.setActivePlace,
          summary: 'p',
        ),
      ]);
      expect(parts.safe, hasLength(2));
      expect(parts.risky, hasLength(1));
      expect(parts.risky.single.op, LivingWorldUpdateOp.setRelationship);
    });
  });

  group('LivingWorldUndoService', () {
    late Directory tempDir;
    late LivingWorldService worlds;
    late LivingWorldUndoService undo;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('anima_undo_');
      worlds = LivingWorldService(documentsDirectory: () async => tempDir);
      undo = LivingWorldUndoService(
        documentsDirectory: () async => tempDir,
        maxSnapshots: 3,
      );
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('push + undo restores prior notebook', () async {
      var world = await worlds.save(buildSampleHarborWorld());
      expect(await undo.canUndo(world.id), isFalse);

      final before = world;
      await undo.pushSnapshot(before);
      world = world.copyWith(
        events: [
          ...world.events,
          WorldEvent(
            id: 'e_new',
            text: 'Something new happened on the pier.',
            placeId: 'pl_pier',
            personIds: const ['p_mira'],
          ),
        ],
      );
      world = await worlds.save(world);
      expect(world.events.length, before.events.length + 1);
      expect(await undo.canUndo(world.id), isTrue);

      final restored = await undo.undoLast(
        worldService: worlds,
        worldId: world.id,
      );
      expect(restored, isNotNull);
      expect(restored!.events.length, before.events.length);
      expect(await undo.canUndo(world.id), isFalse);
    });
  });
}
