import 'package:flutter_test/flutter_test.dart';

import 'package:anima/models/chat_message.dart';
import 'package:anima/models/living_world.dart';
import 'package:anima/services/living_world_retriever.dart';
import 'package:anima/services/living_world_update_service.dart';
import 'package:anima/widgets/living_world_picker.dart';

void main() {
  group('schema v1 → v2 migration', () {
    test('loads v1 JSON as schema 2 with empty continuity', () {
      final world = LivingWorld.fromJson({
        'schemaVersion': 1,
        'id': 'w_v1',
        'title': 'Old Harbor',
        'people': [
          {'id': 'p_a', 'name': 'Ada'},
        ],
        'places': [
          {'id': 'pl_1', 'name': 'Pier'},
        ],
        'events': [
          {'id': 'e1', 'text': 'Something happened', 'personIds': ['p_a']},
        ],
        'flags': [
          {'id': 'f1', 'key': 'open', 'value': true},
        ],
      });

      expect(world.schemaVersion, LivingWorld.currentSchemaVersion);
      expect(world.schemaVersion, 2);
      expect(world.people, hasLength(1));
      expect(world.places, hasLength(1));
      expect(world.events, hasLength(1));
      expect(world.threads, isEmpty);
      expect(world.promises, isEmpty);
      expect(world.secrets, isEmpty);
      expect(world.people.single.inventory, isEmpty);
      expect(world.toJson()['schemaVersion'], 2);
    });

    test('missing schemaVersion treats as v1 and upgrades', () {
      final world = LivingWorld.fromJson({
        'id': 'w_legacy',
        'title': 'Legacy',
        'people': [
          {'id': 'p1', 'name': 'Pat'},
        ],
      });
      expect(world.schemaVersion, 2);
      expect(world.people.single.name, 'Pat');
    });

    test('migration does not wipe harbor people and places', () {
      // Simulate a v1 save of the sample (no continuity keys).
      final v1 = {
        'schemaVersion': 1,
        'id': 'world_harbor',
        'title': 'Sample Harbor',
        'genreNote': 'Quiet coastal town',
        'people': [
          {
            'id': 'p_mira',
            'name': 'Mira',
            'summary': 'Harbor clerk',
          },
          {'id': 'p_edric', 'name': 'Edric'},
          {'id': 'p_lena', 'name': 'Lena'},
        ],
        'places': [
          {'id': 'pl_pier', 'name': 'South Pier'},
          {'id': 'pl_market', 'name': 'Night Market'},
          {'id': 'pl_inn', 'name': 'Harbor Inn'},
        ],
        'relationships': [
          {'fromId': 'p_mira', 'toId': 'p_edric', 'score': 40},
        ],
        'events': [
          {
            'id': 'e1',
            'text': 'Mira logged a missing crate',
            'personIds': ['p_mira'],
          },
        ],
        'flags': [
          {'id': 'f1', 'key': 'mira_knows_crate_missing', 'value': true},
        ],
        'liveState': {
          'activePlaceId': 'pl_pier',
          'personLocations': {'p_mira': 'pl_pier'},
        },
      };

      final world = LivingWorld.fromJson(v1);
      expect(world.people.map((p) => p.name), containsAll(['Mira', 'Edric', 'Lena']));
      expect(world.places, hasLength(3));
      expect(world.relationships, hasLength(1));
      expect(world.events, hasLength(1));
      expect(world.liveState?.activePlaceId, 'pl_pier');
      expect(world.threads, isEmpty);
    });
  });

  group('sample harbor continuity', () {
    test('round-trips threads promises secrets inventory', () {
      final world = buildSampleHarborWorld();
      expect(world.schemaVersion, 2);
      expect(world.threads, hasLength(1));
      expect(world.threads.single.title, 'Missing crate');
      expect(world.promises.single.fromId, 'p_edric');
      expect(world.secrets.single.witnessIds, contains('p_lena'));
      expect(
        world.people.firstWhere((p) => p.id == 'p_mira').inventory,
        contains('pier ledger'),
      );

      final again = LivingWorld.fromJson(world.toJson());
      expect(again.threads.single.id, world.threads.single.id);
      expect(again.promises.single.text, world.promises.single.text);
      expect(again.secrets.single.text, contains('letter'));
      expect(
        again.people.firstWhere((p) => p.id == 'p_mira').inventory,
        ['pier ledger'],
      );
    });

    test('validated drops promise with unknown person', () {
      final world = buildSampleHarborWorld()
          .copyWith(
            promises: [
              const WorldPromise(
                id: 'pr_bad',
                text: 'Ghost promise',
                fromId: 'p_ghost',
                toId: 'p_mira',
              ),
              ...buildSampleHarborWorld().promises,
            ],
          )
          .validated();
      expect(world.promises.any((p) => p.id == 'pr_bad'), isFalse);
      expect(world.promises.any((p) => p.id == 'pr_dawn_check'), isTrue);
    });
  });

  group('continuity update ops', () {
    const service = LivingWorldUpdateService();

    test('parses upsert and close; drops unknown ids', () {
      final world = buildSampleHarborWorld();
      const raw = '''
{
  "updates": [
    {
      "op": "upsertThread",
      "id": "th_crate",
      "title": "Missing crate",
      "summary": "Still missing; Edric checks at dawn.",
      "status": "open",
      "personIds": ["p_mira", "p_edric"],
      "placeId": "pl_pier"
    },
    {
      "op": "upsertPromise",
      "text": "Mira will open the letter with Jay.",
      "fromId": "p_mira",
      "toId": "p_edric",
      "status": "open"
    },
    {
      "op": "upsertSecret",
      "text": "The letter is from Mira's sister.",
      "subjectIds": ["p_mira"],
      "witnessIds": ["p_lena"],
      "status": "open"
    },
    {
      "op": "setInventory",
      "personId": "p_mira",
      "items": ["pier ledger", "sealed letter"]
    },
    {
      "op": "closePromise",
      "id": "pr_dawn_check"
    },
    {
      "op": "closeThread",
      "id": "th_missing"
    },
    {
      "op": "setInventory",
      "personId": "p_ghost",
      "items": ["sword"]
    }
  ]
}
''';
      final updates = service.parseProposal(raw, world: world);
      // closeThread th_missing does not exist → dropped; ghost inventory dropped.
      expect(updates, hasLength(5));
      expect(updates[0].op, LivingWorldUpdateOp.upsertThread);
      expect(updates[1].op, LivingWorldUpdateOp.upsertPromise);
      expect(updates[2].op, LivingWorldUpdateOp.upsertSecret);
      expect(updates[3].op, LivingWorldUpdateOp.setInventory);
      expect(updates[4].op, LivingWorldUpdateOp.closePromise);
      expect(updates.every((u) => u.isSafeForAutoApply), isTrue);
    });

    test('apply upserts, closes, and sets inventory', () {
      final world = buildSampleHarborWorld();
      final updates = service.parseProposal(
        '''
{
  "updates": [
    {"op":"upsertThread","id":"th_crate","title":"Missing crate",
     "summary":"Updated summary","status":"open","personIds":["p_mira"]},
    {"op":"closePromise","id":"pr_dawn_check"},
    {"op":"closeSecret","id":"sec_letter"},
    {"op":"setInventory","personId":"p_edric","items":["seal wrench"]}
  ]
}
''',
        world: world,
      );
      final after = service.applyUpdates(world, updates, runSystems: false);
      expect(
        after.threads.single.summary,
        'Updated summary',
      );
      expect(after.promises.single.status, WorldContinuityStatus.closed);
      expect(after.secrets.single.status, WorldContinuityStatus.closed);
      expect(
        after.people.firstWhere((p) => p.id == 'p_edric').inventory,
        ['seal wrench'],
      );
      // Mira inventory unchanged.
      expect(
        after.people.firstWhere((p) => p.id == 'p_mira').inventory,
        ['pier ledger'],
      );
    });
  });

  group('retriever continuity', () {
    const retriever = LivingWorldRetriever();

    test('open promise and thread for Mira are retrieved', () {
      final world = buildSampleHarborWorld();
      final pack = retriever.retrieve(
        world: world,
        recentMessages: [
          ChatMessage(
            id: 'm1',
            role: ChatRole.user,
            text: 'Mira, about that missing crate — did Edric check?',
          ),
        ],
        speakerName: 'Mira',
        userName: 'Jay',
      );

      expect(pack.threads.map((t) => t.id), contains('th_crate'));
      expect(pack.promises.map((p) => p.id), contains('pr_dawn_check'));
      final prompt = retriever.formatForPrompt(pack);
      expect(prompt, contains('Threads'));
      expect(prompt, contains('Missing crate'));
      expect(prompt, contains('Promises'));
      expect(prompt, contains('pier ledger'));
    });

    test('closed continuity skipped unless strongly mentioned', () {
      final world = buildSampleHarborWorld().copyWith(
        threads: [
          const WorldThread(
            id: 'th_old',
            title: 'Settled dock dispute',
            summary: 'Resolved last season.',
            status: WorldContinuityStatus.closed,
            personIds: ['p_mira'],
          ),
        ],
        promises: [
          const WorldPromise(
            id: 'pr_old',
            text: 'Old favor already repaid',
            fromId: 'p_edric',
            toId: 'p_mira',
            status: WorldContinuityStatus.closed,
          ),
        ],
      );
      final pack = retriever.retrieve(
        world: world,
        recentMessages: [
          ChatMessage(
            id: 'm1',
            role: ChatRole.user,
            text: 'Mira, how is the pier today?',
          ),
        ],
        speakerName: 'Mira',
        userName: 'Jay',
      );
      expect(pack.threads.any((t) => t.id == 'th_old'), isFalse);
      expect(pack.promises.any((p) => p.id == 'pr_old'), isFalse);

      final packMention = retriever.retrieve(
        world: world,
        recentMessages: [
          ChatMessage(
            id: 'm2',
            role: ChatRole.user,
            text: 'Remember the settled dock dispute?',
          ),
        ],
        speakerName: 'Mira',
        userName: 'Jay',
      );
      expect(packMention.threads.map((t) => t.id), contains('th_old'));
    });

    test('secret boosts when speaker is a witness', () {
      final world = buildSampleHarborWorld();
      final pack = retriever.retrieve(
        world: world,
        recentMessages: [
          ChatMessage(
            id: 'm1',
            role: ChatRole.user,
            text: 'Lena, anything new at the market?',
          ),
        ],
        speakerName: 'Lena',
        userName: 'Jay',
      );
      expect(pack.secrets.map((s) => s.id), contains('sec_letter'));
      expect(retriever.formatForPrompt(pack), contains('Secrets'));
    });
  });
}
