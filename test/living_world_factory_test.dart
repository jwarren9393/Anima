import 'package:flutter_test/flutter_test.dart';

import 'package:anima/models/living_world.dart';
import 'package:anima/services/living_world_factory_service.dart';

void main() {
  const factory = LivingWorldFactoryService();
  const request = LivingWorldFactoryRequest(
    brainstorm: 'A rainy harbor town with a missing crate.',
    targetPlaceCount: 4,
    targetPersonCount: 6,
  );

  group('LivingWorldFactoryService prompts', () {
    test('each pass builds system+user messages', () {
      final world = LivingWorld.empty(title: 'Draft');
      for (final pass in LivingWorldFactoryService.passOrder) {
        final messages = factory.buildPassMessages(
          pass: pass,
          request: request,
          world: world,
        );
        expect(messages, hasLength(2));
        expect(messages[0]['role'], 'system');
        expect(messages[1]['role'], 'user');
        expect(messages[0]['content'], contains('JSON'));
        expect(messages[1]['content'], contains('brainstorm'));
      }
    });
  });

  group('LivingWorldFactoryService applyPass', () {
    test('outline seeds stub people and places', () {
      final world = LivingWorld.empty(title: 'Draft');
      final next = factory.applyPass(
        pass: LivingWorldFactoryPass.outline,
        world: world,
        request: request,
        rawResponse: '''
{
  "title": "Gray Harbor",
  "genreNote": "Rainy working docks",
  "placeNames": ["South Pier", "Night Market", "Harbor Inn"],
  "personNames": ["Mira", "Edric", "Lena"],
  "themes": ["missing crate"]
}
''',
      );
      expect(next.title, 'Gray Harbor');
      expect(next.genreNote, contains('Rainy'));
      expect(next.places.length, 3);
      expect(
        next.people.map((p) => p.name),
        containsAll(['Mira', 'Edric', 'Lena']),
      );
      expect(next.places.first.id, startsWith('pl_'));
    });

    test('places pass merges richer descriptions', () {
      var world = LivingWorld(
        id: 'w1',
        title: 'Harbor',
        places: const [WorldPlace(id: 'pl_pier', name: 'South Pier')],
      );
      world = factory.applyPass(
        pass: LivingWorldFactoryPass.places,
        world: world,
        rawResponse: '''
{
  "places": [
    {
      "id": "pl_pier",
      "name": "South Pier",
      "description": "Working docks and salt air.",
      "connectedPlaceIds": ["pl_market"]
    },
    {
      "id": "pl_market",
      "name": "Night Market",
      "description": "Lantern stalls.",
      "connectedPlaceIds": ["pl_pier"]
    }
  ]
}
''',
      );
      expect(world.places, hasLength(2));
      expect(
        world.places.firstWhere((p) => p.id == 'pl_pier').description,
        contains('Working docks'),
      );
    });

    test('people + relationships + seed canon validate ids', () {
      var world = LivingWorld(
        id: 'w1',
        title: 'Harbor',
        places: const [WorldPlace(id: 'pl_pier', name: 'South Pier')],
        people: const [
          WorldPerson(id: 'p_mira', name: 'Mira'),
          WorldPerson(id: 'p_edric', name: 'Edric'),
        ],
      );

      world = factory.applyPass(
        pass: LivingWorldFactoryPass.people,
        world: world,
        rawResponse: '''
{
  "people": [
    {"id": "p_mira", "name": "Mira", "summary": "Harbor clerk", "personalityNotes": "Dry"},
    {"id": "p_edric", "name": "Edric", "summary": "Boat lead", "personalityNotes": "Blunt"}
  ]
}
''',
      );
      expect(world.people.first.summary, 'Harbor clerk');

      world = factory.applyPass(
        pass: LivingWorldFactoryPass.relationships,
        world: world,
        rawResponse: '''
{
  "relationships": [
    {"fromId": "p_mira", "toId": "p_edric", "score": 40, "labels": ["coworker"]},
    {"fromId": "p_mira", "toId": "ghost", "score": 10}
  ]
}
''',
      );
      expect(world.relationships, hasLength(1));
      expect(world.relationships.single.score, 40);

      world = factory.applyPass(
        pass: LivingWorldFactoryPass.seedCanon,
        world: world,
        rawResponse: '''
{
  "events": [
    {
      "id": "e1",
      "text": "Mira logged a missing crate.",
      "placeId": "pl_pier",
      "personIds": ["p_mira", "ghost"]
    }
  ],
  "flags": [
    {"id": "f1", "key": "crate_missing", "value": true}
  ],
  "liveState": {
    "activePlaceId": "pl_pier",
    "personLocations": {"p_mira": "pl_pier", "ghost": "pl_pier"}
  }
}
''',
      );
      expect(world.events, hasLength(1));
      expect(world.events.single.personIds, ['p_mira']);
      expect(world.flags.single.key, 'crate_missing');
      expect(world.liveState?.activePlaceId, 'pl_pier');
      expect(world.liveState?.personLocations.containsKey('ghost'), isFalse);
    });

    test('strips markdown fences from model output', () {
      final world = factory.applyPass(
        pass: LivingWorldFactoryPass.outline,
        world: LivingWorld.empty(title: 'X'),
        request: request,
        rawResponse: '''
```json
{"title": "Fenced", "genreNote": "ok", "placeNames": ["A"], "personNames": ["B"]}
```
''',
      );
      expect(world.title, 'Fenced');
      expect(world.places, hasLength(1));
      expect(world.people, hasLength(1));
    });

    test('salvages complete people from truncated JSON', () {
      // Mimics NanoGPT cutting off mid-object when max tokens run out.
      const truncated = '''
{"people":[
 {"id":"p_ada","name":"Ada","summary":"Mayor","personalityNotes":"Calm","inventory":[]},
 {"id":"p_ben","name":"Ben","summary":"Dockhand","personalityNotes":"Loud","inventory":["rope"]},
 {"id":"p_cara","name":"Cara","summary":"Merchant","personalityNotes":"Sharp","inventory":["Gulf trade writ","Sealed letters of cre
''';
      final world = factory.applyPass(
        pass: LivingWorldFactoryPass.people,
        world: LivingWorld.empty(title: 'Harbor'),
        request: request,
        rawResponse: truncated,
      );
      expect(world.people.length, 2);
      expect(world.people.map((p) => p.name), containsAll(['Ada', 'Ben']));
    });
  });

  group('LivingWorldFactoryService.compile', () {
    test('runs all passes through completePass callback', () async {
      final canned = <LivingWorldFactoryPass, String>{
        LivingWorldFactoryPass.outline: '''
{"title":"Compiled Town","genreNote":"Test","placeNames":["Square","Docks"],
"personNames":["Ada","Ben","Cara"]}
''',
        LivingWorldFactoryPass.places: '''
{"places":[
 {"id":"pl_square","name":"Square","description":"Center","connectedPlaceIds":["pl_docks"]},
 {"id":"pl_docks","name":"Docks","description":"Water","connectedPlaceIds":["pl_square"]}
]}
''',
        LivingWorldFactoryPass.people: '''
{"people":[
 {"id":"p_ada","name":"Ada","summary":"Mayor","personalityNotes":"Calm"},
 {"id":"p_ben","name":"Ben","summary":"Dockhand","personalityNotes":"Loud"},
 {"id":"p_cara","name":"Cara","summary":"Merchant","personalityNotes":"Sharp"}
]}
''',
        LivingWorldFactoryPass.relationships: '''
{"relationships":[{"fromId":"p_ada","toId":"p_ben","score":20,"labels":["duty"]}]}
''',
        LivingWorldFactoryPass.seedCanon: '''
{"events":[{"id":"e1","text":"Ada opened the square market.","placeId":"pl_square","personIds":["p_ada"]}],
"flags":[{"id":"f1","key":"market_open","value":true}],
"liveState":{"activePlaceId":"pl_square","personLocations":{"p_ada":"pl_square"}}}
''',
      };

      final seen = <LivingWorldFactoryPass>[];
      final world = await factory.compile(
        request: request,
        completePass: (pass, messages) async {
          seen.add(pass);
          expect(messages, isNotEmpty);
          return canned[pass]!;
        },
      );

      // People may run as multiple batch calls; other passes once each.
      expect(seen.first, LivingWorldFactoryPass.outline);
      expect(seen.contains(LivingWorldFactoryPass.places), isTrue);
      expect(seen.contains(LivingWorldFactoryPass.people), isTrue);
      expect(seen.contains(LivingWorldFactoryPass.relationships), isTrue);
      expect(seen.last, LivingWorldFactoryPass.seedCanon);
      expect(world.title, 'Compiled Town');
      expect(world.places.length, greaterThanOrEqualTo(2));
      expect(world.people.length, greaterThanOrEqualTo(3));
      expect(world.relationships, isNotEmpty);
      expect(world.events, isNotEmpty);
      expect(world.flags, isNotEmpty);
    });

    test('people pass batches large rosters', () async {
      final bigRequest = LivingWorldFactoryRequest(
        brainstorm: 'Big cast test',
        targetPlaceCount: 3,
        targetPersonCount: 20,
      );
      var peopleCalls = 0;
      final world = await factory.compile(
        request: bigRequest,
        completePass: (pass, messages) async {
          if (pass == LivingWorldFactoryPass.outline) {
            return '''
{"title":"Crowd","genreNote":"Test","placeNames":["A","B","C"],
"personNames":[${List.generate(20, (i) => '"P$i"').join(',')}]}
''';
          }
          if (pass == LivingWorldFactoryPass.places) {
            return '''
{"places":[
 {"id":"pl_a","name":"A","description":"a","connectedPlaceIds":["pl_b"]},
 {"id":"pl_b","name":"B","description":"b","connectedPlaceIds":["pl_a"]},
 {"id":"pl_c","name":"C","description":"c","connectedPlaceIds":["pl_a"]}
]}
''';
          }
          if (pass == LivingWorldFactoryPass.people) {
            peopleCalls++;
            expect(messages[1]['content'], contains('This people batch'));
            // Return whatever names the batch asked for is hard; return a
            // fixed batch-sized set — merge keeps growing via apply.
            final start =
                (peopleCalls - 1) * kLivingWorldFactoryPeopleBatchSize;
            final people = <String>[];
            for (
              var i = start;
              i < start + kLivingWorldFactoryPeopleBatchSize && i < 20;
              i++
            ) {
              people.add(
                '{"id":"p_$i","name":"P$i","summary":"Role $i","personalityNotes":"x"}',
              );
            }
            return '{"people":[${people.join(",")}]}';
          }
          if (pass == LivingWorldFactoryPass.relationships) {
            return '{"relationships":[]}';
          }
          return '{"events":[],"flags":[]}';
        },
      );
      expect(peopleCalls, (20 / kLivingWorldFactoryPeopleBatchSize).ceil());
      expect(world.people.length, greaterThanOrEqualTo(16));
    });

    test('planPeopleBatches pads invent slots when outline is short', () {
      final plans = LivingWorldFactoryService.planPeopleBatches(
        outlineNames: const [
          'Elara',
          'Valen',
          'Malcor',
          'Soren',
          'Aldric',
          'Valerius',
        ],
        target: 24,
      );
      final named = plans.whereType<List<String>>().expand((e) => e).toList();
      expect(named, hasLength(6));
      final inventBatches = plans.where((p) => p == null).length;
      // 24 - 6 = 18 invent slots → ceil(18/8) = 3; 6 names fit in one batch.
      expect(inventBatches, 3);
      expect(plans.length, 1 + inventBatches);
    });

    test('planPeopleBatches invent-only when outline empty', () {
      final plans = LivingWorldFactoryService.planPeopleBatches(
        outlineNames: const [],
        target: 10,
      );
      expect(plans.every((p) => p == null), isTrue);
      expect(plans, hasLength(2)); // 8 + 2
    });

    test('people pass invents padding after a short outline cast', () async {
      final request = LivingWorldFactoryRequest(
        brainstorm: 'Seed cast only',
        targetPlaceCount: 3,
        targetPersonCount: 12,
      );
      var peopleCalls = 0;
      final world = await factory.compile(
        request: request,
        completePass: (pass, messages) async {
          if (pass == LivingWorldFactoryPass.outline) {
            return '''
{"title":"Thin","genreNote":"Test","placeNames":["A","B","C"],
"personNames":["Ada","Ben"]}
''';
          }
          if (pass == LivingWorldFactoryPass.places) {
            return '''
{"places":[
 {"id":"pl_a","name":"A","description":"a","connectedPlaceIds":["pl_b"]},
 {"id":"pl_b","name":"B","description":"b","connectedPlaceIds":["pl_a"]},
 {"id":"pl_c","name":"C","description":"c","connectedPlaceIds":["pl_a"]}
]}
''';
          }
          if (pass == LivingWorldFactoryPass.people) {
            peopleCalls++;
            final content = messages[1]['content']!;
            if (content.contains('This people batch')) {
              return '''
{"people":[
 {"id":"p_ada","name":"Ada","summary":"One","personalityNotes":"x"},
 {"id":"p_ben","name":"Ben","summary":"Two","personalityNotes":"y"}
]}
''';
            }
            // Invent padding batch
            expect(content, contains('Invent new people'));
            return '''
{"people":[
 {"id":"p_c1","name":"Cara","summary":"New","personalityNotes":"z"},
 {"id":"p_c2","name":"Dan","summary":"New","personalityNotes":"z"},
 {"id":"p_c3","name":"Eve","summary":"New","personalityNotes":"z"},
 {"id":"p_c4","name":"Fay","summary":"New","personalityNotes":"z"},
 {"id":"p_c5","name":"Gus","summary":"New","personalityNotes":"z"},
 {"id":"p_c6","name":"Hana","summary":"New","personalityNotes":"z"},
 {"id":"p_c7","name":"Ivy","summary":"New","personalityNotes":"z"},
 {"id":"p_c8","name":"Jon","summary":"New","personalityNotes":"z"}
]}
''';
          }
          if (pass == LivingWorldFactoryPass.relationships) {
            return '{"relationships":[]}';
          }
          return '{"events":[],"flags":[]}';
        },
      );
      expect(peopleCalls, greaterThanOrEqualTo(2));
      expect(world.people.length, greaterThanOrEqualTo(10));
      expect(world.people.any((p) => p.name == 'Cara'), isTrue);
    });
  });
}
