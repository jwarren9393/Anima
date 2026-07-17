import 'package:flutter_test/flutter_test.dart';

import 'package:anima/models/character.dart';
import 'package:anima/models/chat_message.dart';
import 'package:anima/models/lorebook.dart';
import 'package:anima/services/lorebook_service.dart';
import 'package:anima/services/prompt_builder.dart';

void main() {
  const lore = LorebookService();
  const prompts = PromptBuilder();

  Character characterWithBook(Lorebook book) {
    return Character(
      id: 'c1',
      name: 'Aiko',
      description: 'A barista.',
      characterBook: book.toJson(),
    );
  }

  List<ChatMessage> msgs(List<String> texts) {
    return [
      for (var i = 0; i < texts.length; i++)
        ChatMessage(
          id: 'm$i',
          role: i.isEven ? ChatRole.user : ChatRole.assistant,
          text: texts[i],
        ),
    ];
  }

  test('fires keyword entry and injects before character defs', () {
    final book = Lorebook(
      scanDepth: 4,
      tokenBudget: 500,
      entries: [
        LorebookEntry(
          keys: const ['sword', 'blade'],
          content: 'The blade is named Dawncutter.',
          insertionOrder: 100,
          position: LorebookPosition.beforeChar,
        ),
      ],
    );
    final character = characterWithBook(book);
    final injection = lore.buildInjection(
      character: character,
      messages: msgs(['I draw my sword carefully.']),
    );

    expect(injection.matchedCount, 1);
    expect(injection.beforeChar, contains('Dawncutter'));
    expect(injection.afterChar, isEmpty);

    final system = prompts.buildSystemPrompt(
      character: character,
      userName: 'Alex',
      lore: injection,
    );
    expect(system, contains('World info:'));
    expect(system, contains('Dawncutter'));
    expect(system.indexOf('Dawncutter'), lessThan(system.indexOf('Description:')));
  });

  test('always-on entry fires without keywords', () {
    final book = Lorebook(
      entries: [
        LorebookEntry(
          constant: true,
          content: 'Magic is illegal in the city.',
          keys: const [],
        ),
      ],
    );
    final injection = lore.buildInjection(
      character: characterWithBook(book),
      messages: msgs(['Hello there.']),
    );
    expect(injection.matchedCount, 1);
    expect(injection.beforeChar, contains('Magic is illegal'));
  });

  test('selective entry needs primary and secondary keys', () {
    final book = Lorebook(
      entries: [
        LorebookEntry(
          keys: const ['dragon'],
          secondaryKeys: const ['hoard'],
          selective: true,
          content: 'The dragon hoard is cursed.',
        ),
      ],
    );
    final character = characterWithBook(book);

    final miss = lore.buildInjection(
      character: character,
      messages: msgs(['I saw a dragon in the sky.']),
    );
    expect(miss.matchedCount, 0);

    final hit = lore.buildInjection(
      character: character,
      messages: msgs(['The dragon guards its hoard.']),
    );
    expect(hit.matchedCount, 1);
  });

  test('disabled entries are ignored', () {
    final book = Lorebook(
      entries: [
        LorebookEntry(
          enabled: false,
          keys: const ['sword'],
          content: 'Should not appear.',
        ),
      ],
    );
    final injection = lore.buildInjection(
      character: characterWithBook(book),
      messages: msgs(['My sword is ready.']),
    );
    expect(injection.isEmpty, isTrue);
  });

  test('token budget drops lower-priority entries', () {
    final book = Lorebook(
      tokenBudget: 20, // ~80 characters
      entries: [
        LorebookEntry(
          keys: const ['a'],
          content: 'AAAA' * 10, // 40 chars ≈ 10 tokens
          insertionOrder: 10,
          priority: 1,
        ),
        LorebookEntry(
          keys: const ['a'],
          content: 'BBBB' * 10,
          insertionOrder: 20,
          priority: 50,
        ),
      ],
    );
    final injection = lore.buildInjection(
      character: characterWithBook(book),
      messages: msgs(['letter a']),
    );
    // Budget 20 can fit both (~20 tokens) or force a drop depending on estimate.
    // With 10+10=20 exactly both fit; tighten further:
    expect(injection.matchedCount, lessThanOrEqualTo(2));

    final tight = Lorebook(
      tokenBudget: 12,
      entries: book.entries,
    );
    final tightInjection = lore.buildInjection(
      character: characterWithBook(tight),
      messages: msgs(['letter a']),
    );
    expect(tightInjection.matchedCount, 1);
    expect(tightInjection.beforeChar, contains('BBBB'));
    expect(tightInjection.beforeChar, isNot(contains('AAAA')));
  });

  test('after_char placement goes after description block', () {
    final book = Lorebook(
      entries: [
        LorebookEntry(
          keys: const ['rain'],
          content: 'It always rains in Harbor.',
          position: LorebookPosition.afterChar,
        ),
      ],
    );
    final character = characterWithBook(book);
    final injection = lore.buildInjection(
      character: character,
      messages: msgs(['The rain never stops.']),
    );
    final system = prompts.buildSystemPrompt(
      character: character,
      userName: 'Sam',
      lore: injection,
    );
    expect(system.indexOf('Description:'), lessThan(system.indexOf('It always rains')));
  });

  test('round-trips character_book JSON', () {
    final raw = {
      'name': 'Shop lore',
      'scan_depth': 6,
      'token_budget': 300,
      'recursive_scanning': false,
      'extensions': {'x': 1},
      'entries': [
        {
          'keys': ['register'],
          'content': 'The register is sticky.',
          'enabled': true,
          'insertion_order': 100,
          'extensions': <String, dynamic>{},
          'constant': false,
          'position': 'before_char',
        },
      ],
    };
    final book = Lorebook.fromJson(raw);
    expect(book.name, 'Shop lore');
    expect(book.scanDepth, 6);
    expect(book.entries, hasLength(1));
    expect(book.entries.first.keys, ['register']);

    final character = Character(
      id: 'c',
      name: 'Shopkeep',
      characterBook: book.toJson(),
    );
    expect(character.enabledLoreEntryCount, 1);
    expect(lore.bookFor(character)?.entries.first.content, contains('sticky'));
  });

  test('merges global lorebooks with character book', () {
    final character = characterWithBook(
      Lorebook(
        entries: [
          LorebookEntry(
            keys: const ['sword'],
            content: 'Character blade lore.',
            insertionOrder: 200,
          ),
        ],
      ),
    );
    final global = Lorebook(
      name: 'World',
      entries: [
        LorebookEntry(
          keys: const ['sword'],
          content: 'Global forge lore.',
          insertionOrder: 50,
        ),
      ],
    );
    final injection = lore.buildInjection(
      character: character,
      messages: msgs(['I draw my sword.']),
      extraBooks: [global],
    );
    expect(injection.matchedCount, 2);
    expect(injection.beforeChar, contains('Global forge'));
    expect(injection.beforeChar, contains('Character blade'));
    expect(
      injection.beforeChar.indexOf('Global forge'),
      lessThan(injection.beforeChar.indexOf('Character blade')),
    );
  });

  test('parses SillyTavern World Info map-style entries', () {
    final book = Lorebook.parseImport({
      'name': 'ST World',
      'entries': {
        '0': {
          'uid': 0,
          'key': ['harbor'],
          'keysecondary': [],
          'content': 'Harbor is foggy.',
          'disable': false,
          'order': 10,
          'position': 0,
          'constant': false,
        },
        '1': {
          'uid': 1,
          'key': ['rain'],
          'content': 'It rains forever.',
          'disable': true,
          'order': 20,
          'position': 1,
        },
      },
    });
    expect(book.name, 'ST World');
    expect(book.entries, hasLength(2));
    expect(book.entries.first.keys, ['harbor']);
    expect(book.entries.first.enabled, isTrue);
    expect(book.entries[1].enabled, isFalse);
    expect(book.entries[1].position, LorebookPosition.afterChar);
  });
}
