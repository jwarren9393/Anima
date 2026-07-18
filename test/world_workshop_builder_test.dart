import 'package:flutter_test/flutter_test.dart';

import 'package:anima/models/chat_message.dart';
import 'package:anima/models/lorebook.dart';
import 'package:anima/services/world_workshop_builder.dart';

void main() {
  final builder = WorldWorkshopBuilder();

  List<ChatMessage> sampleConversation() => [
        ChatMessage(
          id: '1',
          role: ChatRole.user,
          text: 'Rainy city with guilds. Mira is a dock smuggler.',
        ),
        ChatMessage(
          id: '2',
          role: ChatRole.assistant,
          text: 'Mira wears oilskin and owes the Tide Guild. '
              'Captain Vex runs the night watch.',
        ),
      ];

  const sourceLorebook = Lorebook(
    name: 'Imported Harbor',
    description: 'An imported setting',
    entries: [
      LorebookEntry(
        id: 7,
        name: 'Mira',
        keys: ['Mira', 'dock smuggler'],
        content: 'Mira runs contraband for the Tide Guild.',
        priority: 25,
      ),
    ],
  );

  group('WorldWorkshopBuilder lorebook', () {
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
        conversation: sampleConversation(),
        guidanceNote: 'Do not sanitize.',
      );
      expect(messages.length, 2);
      expect(messages[0]['content'], contains('Do not sanitize.'));
      expect(messages[1]['content'], contains('Rainy city with guilds'));
      expect(messages[1]['content'], contains('Captain Vex'));
    });

    test('linked lorebook is included in chat and update prompts', () {
      final chat = builder.chatSystemPrompt(
        sourceLorebook: sourceLorebook,
      );
      final update = builder.buildExportMessages(
        conversation: sampleConversation(),
        sourceLorebook: sourceLorebook,
      );
      expect(chat, contains('CURRENT LINKED LOREBOOK'));
      expect(chat, contains('Imported Harbor'));
      expect(chat, contains('Tide Guild'));
      expect(update[1]['content'], contains('current linked lorebook'));
      expect(update[1]['content'], contains('"priority": 25'));
      expect(update[1]['content'], contains('Preserve its entries'));
    });
  });

  group('WorldWorkshopBuilder characters', () {
    test('formatTranscript labels speakers', () {
      final text = builder.formatTranscript(sampleConversation());
      expect(text, contains('User: Rainy city with guilds'));
      expect(text, contains('Assistant: Mira wears oilskin'));
    });

    test('buildCharacterDetectMessages includes transcript and guidance', () {
      final messages = builder.buildCharacterDetectMessages(
        conversation: sampleConversation(),
        guidanceNote: 'Keep it raw.',
      );
      expect(messages.length, 2);
      expect(messages[0]['content'], contains('Keep it raw.'));
      expect(messages[0]['content'], contains('characters'));
      expect(messages[1]['content'], contains('Mira is a dock smuggler'));
    });

    test('linked lorebook feeds character detection and generation', () {
      final detect = builder.buildCharacterDetectMessages(
        conversation: const [],
        sourceLorebook: sourceLorebook,
      );
      final generate = builder.buildCharacterExportMessages(
        conversation: const [],
        characterName: 'Mira',
        sourceLorebook: sourceLorebook,
      );
      expect(detect[1]['content'], contains('Imported Harbor'));
      expect(detect[1]['content'], contains('Tide Guild'));
      expect(generate[1]['content'], contains('Imported Harbor'));
      expect(generate[1]['content'], contains('Tide Guild'));
    });

    test('parseCharacterCandidatesJson reads names and summaries', () {
      const raw = '''
{
  "characters": [
    {"name": "Mira", "summary": "Dock smuggler"},
    {"name": "Captain Vex", "summary": "Night watch"},
    {"name": "mira", "summary": "duplicate ignored"}
  ]
}
''';
      final list = builder.parseCharacterCandidatesJson(raw);
      expect(list, hasLength(2));
      expect(list.first.name, 'Mira');
      expect(list.first.summary, 'Dock smuggler');
      expect(list[1].name, 'Captain Vex');
    });

    test('parseCharacterCandidatesJson accepts empty list', () {
      final list = builder.parseCharacterCandidatesJson('{"characters":[]}');
      expect(list, isEmpty);
    });

    test('parseCharacterCandidatesJson rejects malformed output', () {
      expect(
        () => builder.parseCharacterCandidatesJson('not json at all'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => builder.parseCharacterCandidatesJson('{"characters":"nope"}'),
        throwsA(isA<FormatException>()),
      );
    });

    test('buildCharacterExportMessages focuses on one name', () {
      final messages = builder.buildCharacterExportMessages(
        conversation: sampleConversation(),
        characterName: 'Mira',
        characterSummary: 'Dock smuggler',
        guidanceNote: 'Do not sanitize.',
      );
      expect(messages[0]['content'], contains('Mira'));
      expect(messages[0]['content'], contains('Dock smuggler'));
      expect(messages[0]['content'], contains('Do not sanitize.'));
      expect(messages[0]['content'], contains('Do NOT include a character_book'));
      expect(messages[1]['content'], contains('Rainy city with guilds'));
    });

    test('parseCharacterJson builds card with fresh id and no book', () {
      const raw = '''
{
  "spec": "chara_card_v2",
  "spec_version": "2.0",
  "data": {
    "name": "Mira",
    "description": "A dock smuggler in oilskin.",
    "personality": "Wry, loyal to her crew.",
    "scenario": "Rainy night on the piers.",
    "first_mes": "*Mira glances over.* Need something moved?",
    "alternate_greetings": ["*She tips her hood.* Busy night."],
    "mes_example": "<START>\\n{{user}}: Hi\\n{{char}}: Keep your voice down.",
    "system_prompt": "Stay in character as Mira.",
    "post_history_instructions": "Keep replies terse.",
    "creator_notes": "From Creation Center",
    "tags": ["smuggler", "harbor"],
    "character_book": {
      "name": "should be dropped",
      "entries": [{"keys":["x"],"content":"y"}]
    }
  }
}
''';
      final character = builder.parseCharacterJson(
        raw,
        preferredId: 'char_workshop_mira',
      );
      expect(character.id, 'char_workshop_mira');
      expect(character.name, 'Mira');
      expect(character.description, contains('oilskin'));
      expect(character.personality, contains('Wry'));
      expect(character.firstMes, contains('Need something moved'));
      expect(character.alternateGreetings, hasLength(1));
      expect(character.tags, containsAll(['smuggler', 'harbor']));
      expect(character.characterBook, isNull);
      expect(character.creator, isNotEmpty);
    });

    test('parseCharacterJson uses fallback name and rejects nameless', () {
      final withFallback = builder.parseCharacterJson(
        '{"data":{"name":"","description":"Someone"}}',
        preferredId: 'char_1',
        fallbackName: 'Vex',
      );
      expect(withFallback.name, 'Vex');

      expect(
        () => builder.parseCharacterJson(
          '{"data":{"name":"","description":"Someone"}}',
          preferredId: 'char_2',
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('parseCharacterJson strips fences and ignores model id', () {
      const raw = '''
```json
{"name":"Vex","description":"Captain","id":"evil_overwrite"}
```
''';
      final character = builder.parseCharacterJson(
        raw,
        preferredId: 'char_safe',
      );
      expect(character.id, 'char_safe');
      expect(character.name, 'Vex');
    });
  });
}
