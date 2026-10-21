import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:anima/models/living_world.dart';
import 'package:anima/models/living_world_update_policy.dart';
import 'package:anima/services/living_world_pending_service.dart';
import 'package:anima/services/living_world_service.dart';
import 'package:anima/services/living_world_update_service.dart';
import 'package:anima/widgets/living_world_picker.dart';

void main() {
  group('LivingWorldUpdatePolicy Phase 11 copy', () {
    test('autoSafe help mentions Review pending and quiet play', () {
      final help = LivingWorldUpdatePolicy.autoSafe.helpText.toLowerCase();
      expect(help, contains('review pending'));
      expect(help, contains('quietly'));
    });

    test('manual help mentions quietest / learning', () {
      final help = LivingWorldUpdatePolicy.manual.helpText.toLowerCase();
      expect(help, contains('quietest'));
    });
  });

  group('LivingWorldCanonUpdate serialization', () {
    test('relationship round-trips for pending queue', () {
      final update = LivingWorldCanonUpdate(
        op: LivingWorldUpdateOp.setRelationship,
        summary: 'Mira trusts Jay more',
        relationship: const WorldRelationship(
          fromId: 'p_mira',
          toId: 'p_jay',
          score: 40,
          labels: ['aid'],
        ),
      );
      final again = LivingWorldCanonUpdate.fromJson(update.toJson());
      expect(again.op, LivingWorldUpdateOp.setRelationship);
      expect(again.summary, 'Mira trusts Jay more');
      expect(again.relationship?.fromId, 'p_mira');
      expect(again.relationship?.toId, 'p_jay');
      expect(again.relationship?.score, 40);
      expect(again.isSafeForAutoApply, isFalse);
      expect(again.pendingKey, contains('setRelationship'));
    });

    test('event round-trips', () {
      final update = LivingWorldCanonUpdate(
        op: LivingWorldUpdateOp.addEvent,
        summary: 'Harbor bell rang',
        event: const WorldEvent(
          id: 'ev_1',
          text: 'The harbor bell rang at dusk.',
          placeId: 'pl_dock',
        ),
      );
      final again = LivingWorldCanonUpdate.fromJson(update.toJson());
      expect(again.event?.text, 'The harbor bell rang at dusk.');
      expect(again.event?.placeId, 'pl_dock');
      expect(again.isSafeForAutoApply, isTrue);
    });
  });

  group('LivingWorldPendingService', () {
    late Directory tempDir;
    late LivingWorldPendingService pending;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('anima_lw_pending_');
      pending = LivingWorldPendingService(
        documentsDirectory: () async => tempDir,
        maxPending: 5,
      );
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('enqueue persists and dedupes by pendingKey', () async {
      final world = buildSampleHarborWorld();
      final worlds = LivingWorldService(
        documentsDirectory: () async => tempDir,
      );
      await worlds.save(world);

      final a = LivingWorldCanonUpdate(
        op: LivingWorldUpdateOp.setRelationship,
        summary: 'A likes B',
        relationship: WorldRelationship(
          fromId: world.people.first.id,
          toId: world.people.last.id,
          score: 10,
        ),
      );
      final dup = LivingWorldCanonUpdate(
        op: LivingWorldUpdateOp.setRelationship,
        summary: 'A likes B',
        relationship: WorldRelationship(
          fromId: world.people.first.id,
          toId: world.people.last.id,
          score: 20,
        ),
      );
      final b = LivingWorldCanonUpdate(
        op: LivingWorldUpdateOp.setRelationship,
        summary: 'B distrusts A',
        relationship: WorldRelationship(
          fromId: world.people.last.id,
          toId: world.people.first.id,
          score: -15,
        ),
      );

      var list = await pending.enqueue(world.id, [a, dup]);
      expect(list, hasLength(1));
      list = await pending.enqueue(world.id, [b]);
      expect(list, hasLength(2));
      expect(await pending.count(world.id), 2);

      // Reload from disk
      final reloaded = LivingWorldPendingService(
        documentsDirectory: () async => tempDir,
      );
      final fromDisk = await reloaded.list(world.id);
      expect(fromDisk, hasLength(2));
      expect(fromDisk.first.relationship?.score, 10);
    });

    test('removeApplied keeps unselected ops', () async {
      final world = buildSampleHarborWorld();
      final a = LivingWorldCanonUpdate(
        op: LivingWorldUpdateOp.setRelationship,
        summary: 'Keep me',
        relationship: WorldRelationship(
          fromId: world.people.first.id,
          toId: world.people.last.id,
          score: 1,
        ),
      );
      final b = LivingWorldCanonUpdate(
        op: LivingWorldUpdateOp.setRelationship,
        summary: 'Apply me',
        relationship: WorldRelationship(
          fromId: world.people.last.id,
          toId: world.people.first.id,
          score: 2,
        ),
      );
      await pending.enqueue(world.id, [a, b]);
      final kept = await pending.removeApplied(world.id, [b]);
      expect(kept, hasLength(1));
      expect(kept.single.summary, 'Keep me');
    });

    test('clear deletes the pending file', () async {
      final world = buildSampleHarborWorld();
      await pending.enqueue(world.id, [
        const LivingWorldCanonUpdate(
          op: LivingWorldUpdateOp.setRelationship,
          summary: 'x',
        ),
      ]);
      expect(await pending.count(world.id), 1);
      await pending.clear(world.id);
      expect(await pending.count(world.id), 0);
    });

    test('maxPending trims oldest', () async {
      final world = buildSampleHarborWorld();
      for (var i = 0; i < 7; i++) {
        await pending.enqueue(world.id, [
          LivingWorldCanonUpdate(
            op: LivingWorldUpdateOp.setRelationship,
            summary: 'rel $i',
          ),
        ]);
      }
      final list = await pending.list(world.id);
      expect(list, hasLength(5));
      expect(list.first.summary, 'rel 2');
      expect(list.last.summary, 'rel 6');
    });
  });
}
