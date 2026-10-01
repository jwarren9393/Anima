import 'package:flutter_test/flutter_test.dart';

import 'package:anima/services/persona_card_codec.dart';

void main() {
  const codec = PersonaCardCodec();
  var counter = 0;
  String nextId() => 'persona_test_${++counter}';

  setUp(() => counter = 0);

  group('PersonaCardCodec', () {
    test('reads the app\'s own persona shape', () {
      final personas = codec.parseJson('''
      {
        "id": "persona_1",
        "name": "Jay",
        "description": "A wandering knight.",
        "appearance": "Tall, scarred hands.",
        "personality": "Dry humour.",
        "background": "Raised by wolves.",
        "goals": "Find the last dragon."
      }
      ''');

      expect(personas, hasLength(1));
      final p = personas.single;
      expect(p.id, 'persona_1');
      expect(p.name, 'Jay');
      expect(p.description, 'A wandering knight.');
      expect(p.appearance, 'Tall, scarred hands.');
      expect(p.personality, 'Dry humour.');
      expect(p.background, 'Raised by wolves.');
      expect(p.goals, 'Find the last dragon.');
    });

    test('reads a list of personas', () {
      final personas = codec.parseJson(
        '[{"name": "Jay"}, {"name": "Mira"}]',
        newId: nextId,
      );
      expect(personas.map((p) => p.name), ['Jay', 'Mira']);
      expect(personas.first.id, 'persona_test_1');
    });

    test('reads a {"personas": [...]} wrapper', () {
      final personas = codec.parseJson(
        '{"personas": [{"name": "Mira", "summary": "Scout."}]}',
        newId: nextId,
      );
      expect(personas.single.name, 'Mira');
      expect(personas.single.description, 'Scout.');
    });

    test('reads a nested card object', () {
      final personas = codec.parseJson('''
      {"card": {"title": "Kaelen Vance", "identity": "Disgraced heir."}}
      ''', newId: nextId);
      expect(personas.single.name, 'Kaelen Vance');
      expect(personas.single.description, 'Disgraced heir.');
    });

    test('accepts a plain string persona under the name', () {
      final personas = codec.parseJson(
        '{"name": "Ash", "persona": "A quiet thief with a long memory."}',
        newId: nextId,
      );
      expect(personas.single.name, 'Ash');
      expect(personas.single.description, 'A quiet thief with a long memory.');
    });

    test('matches lenient field aliases, including lists', () {
      final personas = codec.parseJson('''
      {
        "display_name": "Vespera",
        "identity": "Court sorceress.",
        "looks": "Silver hair.",
        "traits": ["patient", "watching"],
        "backstory": "Exiled at twelve.",
        "motivations": "Reclaim her name."
      }
      ''', newId: nextId);

      final p = personas.single;
      expect(p.name, 'Vespera');
      expect(p.description, 'Court sorceress.');
      expect(p.appearance, 'Silver hair.');
      expect(p.personality, 'patient\nwatching');
      expect(p.background, 'Exiled at twelve.');
      expect(p.goals, 'Reclaim her name.');
    });

    test('reads personas out of a full .anima-backup file', () {
      const inner = '[{"name":"Jay","description":"A knight."}]';
      final backup = '''
      {"format": "anima_backup_v1",
       "files": {"anima_chats.json": "[]", "anima_personas.json": ${jsonString(inner)}}}
      ''';
      final personas = codec.parseJson(backup, newId: nextId);
      expect(personas.single.name, 'Jay');
    });

    test('keeps a supplied id but invents one when missing', () {
      final withId = codec.parseJson('{"id":"persona_9","name":"A"}', newId: nextId);
      expect(withId.single.id, 'persona_9');
      final without = codec.parseJson('{"name":"B"}', newId: nextId);
      expect(without.single.id, 'persona_test_1');
    });

    test('takes the first line of a multi-line name', () {
      final personas = codec.parseJson('{"name":"Jay\\nWandering knight"}', newId: nextId);
      expect(personas.single.name, 'Jay');
    });

    test('ignores an avatar path or URL but keeps a bare file name', () {
      final url = codec.parseJson('{"name":"A","avatar_file":"https://x/y.png"}', newId: nextId);
      expect(url.single.avatarFileName, isNull);
      final path = codec.parseJson('{"name":"B","avatar_file":"avatars/b.png"}', newId: nextId);
      expect(path.single.avatarFileName, isNull);
      final bare = codec.parseJson('{"name":"C","avatar_file":"c.png"}', newId: nextId);
      expect(bare.single.avatarFileName, 'c.png');
    });

    test('rejects invalid JSON with a plain-English message', () {
      expect(
        () => codec.parseJson('not json at all'),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('not valid JSON'),
          ),
        ),
      );
    });

    test('rejects an empty file', () {
      expect(() => codec.parseJson('   '), throwsA(isA<FormatException>()));
    });

    test('rejects a file with no usable name', () {
      expect(
        () => codec.parseJson('{"description": "no name here"}'),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('No persona found'),
          ),
        ),
      );
    });
  });
}

/// Quotes [text] as a JSON string, so the backup fixture above stays readable.
String jsonString(String text) {
  final escaped = text
      .replaceAll(r'\', r'\\')
      .replaceAll('"', r'\"')
      .replaceAll('\n', r'\n');
  return '"$escaped"';
}
