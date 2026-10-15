import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:anima/models/chat_message.dart';
import 'package:anima/models/chat_session.dart';
import 'package:anima/models/living_world.dart';
import 'package:anima/services/living_world_retriever.dart';
import 'package:anima/services/living_world_service.dart';
import 'package:anima/widgets/living_world_picker.dart';

void main() {
  group('LivingWorld parse / validate', () {
    test('round-trips a full notebook', () {
      final world = buildSampleHarborWorld();
      final again = LivingWorld.fromJson(world.toJson());
      expect(again.id, world.id);
      expect(again.title, 'Sample Harbor');
      expect(again.people, hasLength(3));
      expect(again.places, hasLength(3));
      expect(again.relationships, hasLength(3));
      expect(again.events, hasLength(3));
      expect(again.flags, hasLength(3));
      expect(again.liveState?.activePlaceId, 'pl_pier');
    });

    test('rejects missing id / title', () {
      expect(
        () => LivingWorld.fromJson({'title': 'X'}),
        throwsFormatException,
      );
      expect(
        () => LivingWorld.fromJson({'id': 'w1'}),
        throwsFormatException,
      );
    });

    test('rejects unsupported schema version', () {
      expect(
        () => LivingWorld.fromJson({
          'schemaVersion': 99,
          'id': 'w1',
          'title': 'Future',
        }),
        throwsFormatException,
      );
    });

    test('validated drops broken relationship and place links', () {
      final world = LivingWorld(
        id: 'w1',
        title: 'Town',
        people: const [
          WorldPerson(id: 'a', name: 'Ada'),
        ],
        places: const [
          WorldPlace(
            id: 'p1',
            name: 'Pier',
            connectedPlaceIds: ['missing', 'p1'],
          ),
        ],
        relationships: const [
          WorldRelationship(fromId: 'a', toId: 'ghost', score: 10),
          WorldRelationship(fromId: 'a', toId: 'a', score: 999),
        ],
      ).validated();

      expect(world.relationships, hasLength(1));
      expect(world.relationships.single.score, 100);
      expect(world.places.single.connectedPlaceIds, isEmpty);
    });

    test('flag values accept bool / string / number', () {
      final world = LivingWorld.fromJson({
        'id': 'w1',
        'title': 'Flags',
        'flags': [
          {'id': 'f1', 'key': 'open', 'value': true},
          {'id': 'f2', 'key': 'status', 'value': 'banished'},
          {'id': 'f3', 'key': 'count', 'value': 2},
        ],
      });
      expect(world.flags[0].value, isTrue);
      expect(world.flags[1].value, 'banished');
      expect(world.flags[2].value, 2);
    });
  });

  group('ChatSession.worldId', () {
    test('round-trips worldId and clears it', () {
      final session = ChatSession(
        id: 'c1',
        characterId: 'char1',
        title: 'Solo',
        updatedAt: DateTime.utc(2026, 1, 1),
        worldId: 'world_1',
      );
      expect(session.hasLivingWorld, isTrue);
      final json = session.toJson();
      expect(json['worldId'], 'world_1');
      final again = ChatSession.fromJson(json);
      expect(again.worldId, 'world_1');
      expect(again.copyWith(clearWorldId: true).worldId, isNull);
      expect(
        ChatSession.fromJson({
          'id': 'c2',
          'characterId': 'char1',
          'title': 'Old',
          'updatedAt': '2026-01-01T00:00:00.000Z',
          'messages': [],
        }).worldId,
        isNull,
      );
    });
  });

  group('LivingWorldRetriever', () {
    const retriever = LivingWorldRetriever();

    test('retrieves Mira-related canon when she is mentioned', () {
      final world = buildSampleHarborWorld();
      final pack = retriever.retrieve(
        world: world,
        recentMessages: [
          ChatMessage(
            id: 'm1',
            role: ChatRole.user,
            text: 'Mira, what happened to the crate?',
          ),
        ],
        speakerName: 'Mira',
        userName: 'Jay',
      );

      expect(pack.people.map((p) => p.name), contains('Mira'));
      expect(pack.people.map((p) => p.name), contains('Edric'));
      expect(pack.events, isNotEmpty);
      expect(
        pack.events.any((e) => e.text.toLowerCase().contains('crate')),
        isTrue,
      );
      expect(pack.flags.any((f) => f.key.contains('crate')), isTrue);

      final prompt = retriever.formatForPrompt(pack);
      expect(prompt, contains('Living World memory'));
      expect(prompt, contains('authoritative canon'));
      expect(prompt, contains('Mira'));
      expect(prompt, contains('crate'));
    });

    test('includes active place even with sparse mentions', () {
      final world = buildSampleHarborWorld();
      final pack = retriever.retrieve(
        world: world,
        recentMessages: const [],
        speakerName: 'Nobody',
        userName: 'Jay',
      );
      expect(pack.places.map((p) => p.name), contains('South Pier'));
      final prompt = retriever.formatForPrompt(pack);
      expect(prompt, contains('Sample Harbor'));
    });

    test('fitBudget shrinks oversized packs', () {
      final world = buildSampleHarborWorld();
      final fat = LivingWorldPack(
        worldTitle: world.title,
        people: world.people,
        places: world.places,
        relationships: world.relationships,
        events: [
          for (var i = 0; i < 40; i++)
            WorldEvent(
              id: 'e$i',
              text: 'Long event number $i about Mira and the crate on the pier '
                  'with lots of extra words to burn tokens deliberately.',
              personIds: const ['p_mira'],
            ),
        ],
        flags: world.flags,
      );
      final slim = fat.fitBudget(200);
      expect(slim.renderBody().length, lessThan(fat.renderBody().length));
      expect(slim.events.length, lessThan(fat.events.length));
    });
  });

  group('LivingWorldService', () {
    late Directory tempDir;
    late LivingWorldService service;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('anima_worlds_');
      service = LivingWorldService(
        documentsDirectory: () async => tempDir,
      );
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('save / load / list / delete under worlds/', () async {
      final saved = await service.save(buildSampleHarborWorld());
      final loaded = await service.getById(saved.id);
      expect(loaded?.title, 'Sample Harbor');
      expect(loaded?.people, hasLength(3));

      final file = File('${tempDir.path}/worlds/${saved.id}.json');
      expect(await file.exists(), isTrue);

      final summaries = await service.listSummaries();
      expect(summaries, hasLength(1));
      expect(summaries.single.personCount, 3);

      await service.delete(saved.id);
      expect(await service.getById(saved.id), isNull);
    });

    test('importFromBytes assigns a new id on collision', () async {
      final first = await service.save(buildSampleHarborWorld());
      final bytes = utf8.encode(
        const JsonEncoder().convert(first.toJson()),
      );
      final second = await service.importFromBytes(bytes);
      expect(second.id, isNot(first.id));
      expect(second.title, first.title);
    });

    test('parseWorldJson rejects non-object root', () {
      expect(
        () => service.parseWorldJson('[]'),
        throwsFormatException,
      );
    });
  });

  group('livingWorldMenuLabel', () {
    test('shows Off when unbound', () {
      expect(livingWorldMenuLabel(null, null), 'Living World: Off');
      expect(livingWorldMenuLabel('', 'X'), 'Living World: Off');
    });

    test('shows title when bound', () {
      expect(
        livingWorldMenuLabel('w1', 'Sample Harbor'),
        'Living World: Sample Harbor',
      );
    });
  });
}
