import 'package:flutter_test/flutter_test.dart';

import 'package:anima/models/chat_message.dart';
import 'package:anima/services/world_workshop_builder.dart';

void main() {
  const builder = WorldWorkshopBuilder();

  group('WorldWorkshopBuilder', () {
    test('parseLorebookJson accepts plain JSON object', () {
      const raw = '''
{
  "name": "Harbor City",
  "description": "Rainy coast",
  "entries": [
    {
      "name": "Harbor",
      "keys": ["harbor", "docks"],
      "content": "The harbor smells of salt and iron.",
      "enabled": true,
      "constant": false
    }
  ]
}
''';
      final book = builder.parseLorebookJson(raw);
      expect(book.name, 'Harbor City');
      expect(book.entries, hasLength(1));
      expect(book.entries.first.keys, contains('harbor'));
      expect(book.entries.first.content, contains('salt'));
    });

    test('parseLorebookJson strips markdown fences', () {
      const raw = '''
Here you go:
```json
{"name":"X","entries":[{"keys":["x"],"content":"lore about x"}]}
```
''';
      final book = builder.parseLorebookJson(raw);
      expect(book.name, 'X');
      expect(book.entries, hasLength(1));
    });

    test('parseLorebookJson rejects empty entries', () {
      expect(
        () => builder.parseLorebookJson('{"name":"Empty","entries":[]}'),
        throwsA(isA<FormatException>()),
      );
    });

    test('suggestTitle uses first user message', () {
      final title = builder.suggestTitle([
        ChatMessage(
          id: '1',
          role: ChatRole.user,
          text: 'A buried god under the harbor',
        ),
      ]);
      expect(title, 'A buried god under the harbor');
    });

    test('buildExportMessages includes transcript', () {
      final messages = builder.buildExportMessages(
        conversation: [
          ChatMessage(
            id: '1',
            role: ChatRole.user,
            text: 'Rainy city with guilds',
          ),
          ChatMessage(
            id: '2',
            role: ChatRole.assistant,
            text: 'Tell me about the guilds.',
          ),
        ],
        guidanceNote: 'Do not sanitize.',
      );
      expect(messages.length, 2);
      expect(messages[0]['content'], contains('Do not sanitize.'));
      expect(messages[1]['content'], contains('Rainy city with guilds'));
      expect(messages[1]['content'], contains('Tell me about the guilds.'));
    });
  });
}
