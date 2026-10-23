import 'package:flutter_test/flutter_test.dart';

import 'package:anima/models/chat_message.dart';
import 'package:anima/models/living_world.dart';
import 'package:anima/services/living_world_update_service.dart';
import 'package:anima/widgets/living_world_picker.dart';

void main() {
  const service = LivingWorldUpdateService();

  LivingWorld sample() => buildSampleHarborWorld();

  group('parseProposal', () {
    test('parses valid updates and drops unknown ids', () {
      final world = sample();
      const raw = '''
{
  "updates": [
    {
      "op": "addEvent",
      "text": "Mira decided to tell Jay about the sealed letter.",
      "placeId": "pl_pier",
      "personIds": ["p_mira"]
    },
    {
      "op": "setFlag",
      "key": "mira_told_jay_about_letter",
      "value": true
    },
    {
      "op": "setRelationship",
      "fromId": "p_mira",
      "toId": "p_edric",
      "score": 55,
      "labels": ["allies"]
    },
    {
      "op": "setActivePlace",
      "placeId": "pl_inn"
    },
    {
      "op": "setPersonLocation",
      "personId": "p_mira",
      "placeId": "pl_inn"
    },
    {
      "op": "addEvent",
      "text": "Ghost did something",
      "personIds": ["p_ghost"]
    },
    {
      "op": "setActivePlace",
      "placeId": "pl_nowhere"
    }
  ]
}
''';

      final updates = service.parseProposal(raw, world: world);
      expect(updates, hasLength(5));
      expect(updates[0].op, LivingWorldUpdateOp.addEvent);
      expect(updates[0].event?.text, contains('sealed letter'));
      expect(updates[1].op, LivingWorldUpdateOp.setFlag);
      expect(updates[2].op, LivingWorldUpdateOp.setRelationship);
      expect(updates[2].relationship?.score, 55);
      expect(updates[3].op, LivingWorldUpdateOp.setActivePlace);
      expect(updates[4].op, LivingWorldUpdateOp.setPersonLocation);
    });

    test('accepts fenced JSON', () {
      final world = sample();
      const raw = '''
Here you go:
```json
{"updates":[{"op":"setFlag","key":"dock_closed","value":false}]}
```
''';
      final updates = service.parseProposal(raw, world: world);
      expect(updates, hasLength(1));
      expect(updates.single.flag?.value, isFalse);
    });

    test('empty updates list is ok', () {
      final updates = service.parseProposal('{"updates":[]}', world: sample());
      expect(updates, isEmpty);
    });

    test('throws when updates key missing', () {
      expect(
        () => service.parseProposal('{"oops":[]}', world: sample()),
        throwsFormatException,
      );
    });
  });

  group('applyUpdates', () {
    test('applies selected events flags relationships and live state', () {
      final world = sample();
      final proposed = service.parseProposal('''
{
  "updates": [
    {"op":"addEvent","text":"Jay promised Mira silence about the letter.","personIds":["p_mira"]},
    {"op":"setFlag","key":"jay_promised_silence","value":true},
    {"op":"setRelationship","fromId":"p_mira","toId":"p_lena","score":25,"labels":["cautious trust"]},
    {"op":"setActivePlace","placeId":"pl_market"},
    {"op":"setPersonLocation","personId":"p_edric","placeId":"pl_inn"}
  ]
}
''', world: world);

      final updated = service.applyUpdates(world, proposed);
      expect(
        updated.events.any((e) => e.text.contains('promised Mira')),
        isTrue,
      );
      expect(updated.flags.any((f) => f.key == 'jay_promised_silence'), isTrue);
      expect(
        updated.relationships.any(
          (r) => r.fromId == 'p_mira' && r.toId == 'p_lena' && r.score == 25,
        ),
        isTrue,
      );
      expect(updated.liveState?.activePlaceId, 'pl_market');
      expect(updated.liveState?.personLocations['p_edric'], 'pl_inn');
      // Original Mira@pier still present unless overwritten
      expect(updated.liveState?.personLocations['p_mira'], 'pl_pier');
    });

    test('setFlag replaces existing key case-insensitively', () {
      final world = sample();
      final proposed = service.parseProposal(
        '{"updates":[{"op":"setFlag","key":"MIRA_KNOWS_CRATE_MISSING","value":false}]}',
        world: world,
      );
      final updated = service.applyUpdates(world, proposed);
      final matches = updated.flags.where(
        (f) => f.key.toLowerCase() == 'mira_knows_crate_missing',
      );
      // Original key kept or new key — one logical flag after merge by key
      expect(
        updated.flags.where(
          (f) => f.key.toLowerCase() == 'mira_knows_crate_missing',
        ),
        hasLength(1),
      );
      expect(matches.single.value, isFalse);
    });

    test('applying nothing returns the same world content', () {
      final world = sample();
      final again = service.applyUpdates(world, const []);
      expect(again.events.length, world.events.length);
      expect(again.flags.length, world.flags.length);
    });
  });

  group('buildProposeMessages', () {
    test('includes roster ids and recent chat', () {
      final world = sample();
      final messages = service.buildProposeMessages(
        world: world,
        recentMessages: [
          ChatMessage(
            id: '1',
            role: ChatRole.user,
            text: 'I tell Mira I will keep the letter secret.',
          ),
          ChatMessage(
            id: '2',
            role: ChatRole.assistant,
            text: '*I nod.* "Deal."',
            speakerName: 'Mira',
          ),
        ],
        userName: 'Jay',
        speakerName: 'Mira',
      );
      expect(messages, hasLength(2));
      final user = messages[1]['content']!;
      expect(user, contains('p_mira'));
      expect(user, contains('pl_pier'));
      expect(user, contains('keep the letter secret'));
      expect(messages[0]['content'], contains('JSON'));
      expect(messages[0]['content'], contains('upsertPerson'));
    });
  });

  group('upsertPerson', () {
    test('parses and applies a newly introduced person', () {
      final world = sample();
      final updates = service.parseProposal('''
{"updates":[{"op":"upsertPerson","name":"Lady Cassalin",
 "summary":"Daughter of the Ravensmere tolls lord"}]}
''', world: world);
      expect(updates, hasLength(1));
      expect(updates.single.op, LivingWorldUpdateOp.upsertPerson);
      expect(updates.single.isSafeForAutoApply, isFalse);
      expect(updates.single.reviewLabel, 'New person');
      expect(updates.single.person?.name, 'Lady Cassalin');

      final updated = service.applyUpdates(world, updates);
      expect(updated.people.any((p) => p.name == 'Lady Cassalin'), isTrue);
      expect(updated.people.length, world.people.length + 1);
    });

    test('drops upsertPerson when the name is already on the roster', () {
      final world = sample();
      final updates = service.parseProposal(
        '{"updates":[{"op":"upsertPerson","name":"Mira","summary":"Already here"}]}',
        world: world,
      );
      expect(updates, isEmpty);
    });

    test('round-trips through pending JSON', () {
      final world = sample();
      final updates = service.parseProposal(
        '{"updates":[{"op":"upsertPerson","name":"Cassalin","summary":"Toll heir"}]}',
        world: world,
      );
      final raw = updates.single.toJson();
      final again = LivingWorldCanonUpdate.fromJson(raw);
      expect(again.op, LivingWorldUpdateOp.upsertPerson);
      expect(again.person?.name, 'Cassalin');
      final applied = service.applyUpdates(world, [again]);
      expect(applied.people.any((p) => p.name == 'Cassalin'), isTrue);
    });

    test('partition marks upsertPerson as risky', () {
      final world = sample();
      final updates = service.parseProposal('''
{"updates":[
 {"op":"setFlag","key":"feast_started","value":true},
 {"op":"upsertPerson","name":"Cassalin","summary":"Guest"}
]}
''', world: world);
      final parts = service.partitionForAutoSafe(updates);
      expect(
        parts.safe.any((u) => u.op == LivingWorldUpdateOp.setFlag),
        isTrue,
      );
      expect(
        parts.risky.any((u) => u.op == LivingWorldUpdateOp.upsertPerson),
        isTrue,
      );
    });
  });
}
