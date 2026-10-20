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
      expect(next.people.map((p) => p.name), containsAll(['Mira', 'Edric', 'Lena']));
      expect(next.places.first.id, startsWith('pl_'));
    });

    test('places pass merges richer descriptions', () {
      var world = LivingWorld(
        id: 'w1',
        title: 'Harbor',
        places: const [
          WorldPlace(id: 'pl_pier', name: 'South Pier'),
        ],
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
        places: const [
          WorldPlace(id: 'pl_pier', name: 'South Pier'),
        ],
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

      expect(seen, LivingWorldFactoryService.passOrder);
      expect(world.title, 'Compiled Town');
      expect(world.places.length, greaterThanOrEqualTo(2));
      expect(world.people.length, greaterThanOrEqualTo(3));
      expect(world.relationships, isNotEmpty);
      expect(world.events, isNotEmpty);
      expect(world.flags, isNotEmpty);
    });
  });
}
