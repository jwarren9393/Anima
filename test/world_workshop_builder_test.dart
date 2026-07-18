import 'package:flutter_test/flutter_test.dart';

import 'package:anima/models/character.dart';
import 'package:anima/models/chat_message.dart';
import 'package:anima/models/chat_session.dart';
import 'package:anima/models/global_lorebook.dart';
import 'package:anima/models/lorebook.dart';
import 'package:anima/models/persona.dart';
import 'package:anima/models/world_workshop.dart';
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
      text:
          'Mira wears oilskin and owes the Tide Guild. '
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
      final chat = builder.chatSystemPrompt(sourceLorebook: sourceLorebook);
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
      expect(
        messages[0]['content'],
        contains('Do NOT include a character_book'),
      );
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

  group('WorldWorkshopBuilder personas', () {
    test(
      'persona generation prompt stays player-focused and includes lore',
      () {
        final messages = builder.buildPersonaExportMessages(
          conversation: sampleConversation(),
          personaName: 'Mira',
          personaSummary: 'Dock smuggler',
          sourceLorebook: sourceLorebook,
        );
        expect(messages[0]['content'], contains('human user will play'));
        expect(messages[0]['content'], contains('"appearance"'));
        expect(messages[0]['content'], contains('Do not include greetings'));
        expect(messages[1]['content'], contains('Imported Harbor'));
        expect(messages[1]['content'], contains('Mira'));
      },
    );

    test('parsePersonaJson builds structured persona with a fresh id', () {
      const raw = '''
```json
{
  "name": "Mira",
  "description": "A smuggler tied to the Tide Guild.",
  "appearance": "Dark hair and an oilskin coat.",
  "personality": "Wry and loyal.",
  "background": "Raised near the docks.",
  "goals": "Protect her crew."
}
```
''';
      final persona = builder.parsePersonaJson(
        raw,
        preferredId: 'persona_mira',
      );
      expect(persona.id, 'persona_mira');
      expect(persona.name, 'Mira');
      expect(persona.appearance, contains('oilskin'));
      expect(persona.personality, contains('loyal'));
      expect(persona.background, contains('docks'));
      expect(persona.goals, contains('crew'));
      expect(persona.promptText, contains('Identity and role'));
    });

    test('parsePersonaJson supports fallback name and legacy aliases', () {
      final persona = builder.parsePersonaJson(
        '{"role":"Heir","backstory":"Old house","motivation":"Restore it"}',
        preferredId: 'persona_heir',
        fallbackName: 'Valerius Blackwood',
      );
      expect(persona.name, 'Valerius Blackwood');
      expect(persona.description, 'Heir');
      expect(persona.background, 'Old house');
      expect(persona.goals, 'Restore it');
    });
  });

  group('WorldWorkshopBuilder chat import', () {
    ChatSession sampleSession({
      String summary = '',
      int covered = 0,
      List<ChatMessage>? messages,
    }) {
      return ChatSession(
        id: 'chat_1',
        characterId: 'char_a',
        title: 'Harbor Night',
        updatedAt: DateTime(2026, 7, 18),
        personaId: 'persona_1',
        authorsNote: 'Keep it rainy.',
        participantIds: const ['char_a', 'char_b'],
        lorebookIds: const ['lore_1'],
        memorySummary: summary,
        memoryCoveredCount: covered,
        messages: messages ??
            [
              ChatMessage(
                id: 'm1',
                role: ChatRole.assistant,
                text: 'Old covered line.',
                speakerId: 'char_a',
                speakerName: 'Mira',
              ),
              ChatMessage(
                id: 'm2',
                role: ChatRole.user,
                text: 'We slip past the watch.',
              ),
              ChatMessage(
                id: 'm3',
                role: ChatRole.assistant,
                text: 'Stay low near the crates.',
                speakerId: 'char_b',
                speakerName: 'Captain Vex',
              ),
            ],
      );
    }

    test('selectRecentMessages prefers uncovered after summary', () {
      final recent = builder.selectRecentMessagesForImport(
        sampleSession(summary: 'They smuggled crates.', covered: 1),
      );
      expect(recent, hasLength(2));
      expect(recent.first.text, contains('slip past'));
      expect(recent.last.speakerName, 'Captain Vex');
    });

    test('selectRecentMessages falls back when no summary', () {
      final many = <ChatMessage>[
        for (var i = 0; i < 50; i++)
          ChatMessage(
            id: 'n$i',
            role: i.isEven ? ChatRole.user : ChatRole.assistant,
            text: 'Line $i',
            speakerName: i.isEven ? null : 'Mira',
          ),
      ];
      final recent = builder.selectRecentMessagesForImport(
        sampleSession(messages: many),
      );
      expect(recent, hasLength(WorldWorkshopBuilder.importFallbackRecent));
      expect(recent.first.text, 'Line 10');
      expect(recent.last.text, 'Line 49');
    });

    test('buildImportedChatSource packs cards, persona, lore, speakers', () {
      final source = builder.buildImportedChatSource(
        session: sampleSession(summary: 'Dock heist in progress.', covered: 1),
        characters: const [
          Character(
            id: 'char_a',
            name: 'Mira',
            description: 'Dock smuggler',
            personality: 'Wry',
          ),
          Character(
            id: 'char_b',
            name: 'Captain Vex',
            description: 'Night watch',
            characterBook: {
              'name': 'Vex notes',
              'entries': [
                {
                  'keys': ['watch'],
                  'content': 'Vex bribes the watch captains.',
                },
              ],
            },
          ),
        ],
        persona: const Persona(
          id: 'persona_1',
          name: 'Ash',
          description: 'A quiet fixer',
        ),
        linkedLorebooks: const [
          GlobalLorebook(
            id: 'lore_1',
            book: Lorebook(
              name: 'Harbor',
              entries: [
                LorebookEntry(
                  id: 1,
                  keys: ['harbor'],
                  content: 'Salt and iron.',
                ),
              ],
            ),
          ),
        ],
        skippedNotes: const ['Character id char_missing (deleted)'],
      );

      expect(source.hasContent, isTrue);
      expect(source.chatTitle, 'Harbor Night');
      expect(source.isGroup, isTrue);
      expect(source.memorySummary, contains('Dock heist'));
      expect(source.recentTranscript, contains('Ash: We slip past'));
      expect(source.recentTranscript, contains('Captain Vex: Stay low'));
      expect(source.charactersText, contains('### Mira'));
      expect(source.personaText, contains('Player persona'));
      expect(source.loreReferenceText, contains('Harbor'));
      expect(source.loreReferenceText, contains('Embedded on Captain Vex'));
      expect(source.skippedNotes, contains('Character id char_missing (deleted)'));
      expect(source.promptText, contains('IMPORTED CHAT SOURCE'));
    });

    test('imported source appears in workshop prompts', () {
      final source = builder.buildImportedChatSource(
        session: sampleSession(summary: 'Summary text.', covered: 1),
        characters: const [
          Character(id: 'char_a', name: 'Mira', description: 'Smuggler'),
        ],
        persona: const Persona(id: 'persona_1', name: 'Ash'),
      );
      final chat = builder.chatSystemPrompt(importedSource: source);
      final export = builder.buildExportMessages(
        conversation: sampleConversation(),
        importedSource: source,
      );
      final detect = builder.buildCharacterDetectMessages(
        conversation: const [],
        importedSource: source,
      );
      expect(chat, contains('IMPORTED CHAT SOURCE'));
      expect(chat, contains('Harbor Night'));
      expect(export[1]['content'], contains('IMPORTED CHAT SOURCE'));
      expect(export[1]['content'], contains('Summary text.'));
      expect(detect[1]['content'], contains('Mira'));
    });

    test('WorldWorkshop JSON round-trips imported source', () {
      final source = builder.buildImportedChatSource(
        session: sampleSession(summary: 'Kept.', covered: 0),
        characters: const [Character(id: 'char_a', name: 'Mira')],
      );
      final workshop = WorldWorkshop.empty(title: 'From chat').copyWith(
        importedSource: source,
      );
      final restored = WorldWorkshop.fromJson(workshop.toJson());
      expect(restored.importedSource, isNotNull);
      expect(restored.importedSource!.chatTitle, 'Harbor Night');
      expect(restored.importedSource!.memorySummary, 'Kept.');
      expect(restored.importedSource!.characterNames, contains('Mira'));

      final legacy = WorldWorkshop.fromJson({
        'id': 'ws_old',
        'title': 'Old',
        'messages': [],
        'updatedAt': DateTime(2026, 1, 1).toIso8601String(),
      });
      expect(legacy.importedSource, isNull);
    });
  });
}
