import 'package:flutter_test/flutter_test.dart';

import 'package:anima/models/chat_message.dart';
import 'package:anima/services/roadway_service.dart';
import 'package:anima/services/settings_service.dart';

void main() {
  const service = RoadwayService();

  test('parseOptions reads numbered and bulleted lines', () {
    const raw = '''
Here are ideas:
1. *Look closer* at the pendant. "Where did you get that?"
2) Ask about the ruins beyond the ridge.
- Offer a trade for information.
* Suggest forming an alliance.
''';
    final options = service.parseOptions(raw);
    expect(options.length, 4);
    expect(options[0], contains('pendant'));
    expect(options[1], contains('ruins'));
    expect(options[2], contains('trade'));
    expect(options[3], contains('alliance'));
  });

  test('parseOptions caps at max', () {
    final raw = List.generate(12, (i) => '${i + 1}. Option $i').join('\n');
    final options = service.parseOptions(raw, max: 6);
    expect(options, hasLength(6));
  });

  test('buildCombineMessages needs at least two selections', () {
    final none = service.buildCombineMessages(
      userName: 'Alex',
      characterName: 'Mira',
      recentMessages: const [],
      selectedOptions: const ['Only one'],
    );
    expect(none, isEmpty);

    final blank = service.buildCombineMessages(
      userName: 'Alex',
      characterName: 'Mira',
      recentMessages: const [],
      selectedOptions: const ['One', '  '],
    );
    expect(blank, isEmpty);
  });

  test('buildCombineMessages includes selected ideas and scene context', () {
    final messages = [
      ChatMessage(
        id: 'm1',
        role: ChatRole.assistant,
        text: '*Mira steps closer* "Trust me."',
      ),
    ];
    final prompt = service.buildCombineMessages(
      userName: 'Alex',
      characterName: 'Mira',
      recentMessages: messages,
      selectedOptions: const [
        '*Take her hand* carefully.',
        '"What happens next?"',
      ],
      roadwayNote: 'Keep it intimate and short.',
    );

    expect(prompt, hasLength(2));
    final system = prompt[0]['content']!;
    final user = prompt[1]['content']!;
    expect(system, contains('Keep it intimate and short.'));
    expect(system, contains('first-person'));
    expect(system, contains('Output only the final message text'));
    expect(user, contains('Mira steps closer'));
    expect(user, contains('*Take her hand* carefully.'));
    expect(user, contains('"What happens next?"'));
    expect(user, contains('Selected path ideas to combine'));
  });

  test('parseCombinedMessage strips wrappers and joins accidental lists', () {
    expect(
      service.parseCombinedMessage('  "Hello there."  '),
      'Hello there.',
    );
    expect(
      service.parseCombinedMessage('```\n*Nods* "Okay."\n```'),
      '*Nods* "Okay."',
    );
    expect(
      service.parseCombinedMessage('1. First beat\n2. Second beat'),
      'First beat Second beat',
    );
  });

  test('parseOptions dedupes identical lines', () {
    const raw = '''
1. *I smile* "Hello."
2. *I smile* "Hello."
3. *I wave* "Hi there."
''';
    final options = service.parseOptions(raw);
    expect(options, hasLength(2));
  });

  test('normalizeUserPerspective fixes third-person action leaks', () {
    expect(
      service.normalizeUserPerspective(
        '"I love you." *Trey looks down at her*',
        userName: 'Trey',
      ),
      '"I love you." *I looks down at her*',
    );
    expect(
      service.normalizeUserPerspective(
        '*Trey\'s hands tremble*',
        userName: 'Trey',
      ),
      '*my hands tremble*',
    );
  });

  test('buildMessages requires first person in system prompt', () {
    final messages = service.buildMessages(
      userName: 'Trey',
      characterName: 'Angela',
      recentMessages: const [],
    );
    final system = messages.first['content']!;
    expect(system, contains('FIRST PERSON'));
    expect(system, isNot(contains('Hard rules')));
    expect(system, contains('Never use the'));
  });

  test('recent context labels player as You not persona name', () {
    final messages = service.buildMessages(
      userName: 'Trey',
      characterName: 'Angela',
      recentMessages: [
        ChatMessage(id: '1', role: ChatRole.user, text: 'Hey.'),
      ],
    );
    final user = messages.last['content']!;
    expect(user, contains('You (player):'));
    expect(user, isNot(contains('Trey (user):')));
  });

  test('generateSampling caps tokens and raises repeat penalties', () {
    const base = SamplingSettings(
      maxTokens: 4096,
      temperature: 0.9,
      topP: 1.0,
    );
    final tuned = RoadwayService.generateSampling(base);
    expect(tuned.maxTokens, lessThanOrEqualTo(RoadwayService.generateMaxTokens));
    expect(tuned.frequencyPenalty, greaterThanOrEqualTo(0.45));
    expect(tuned.temperature, lessThanOrEqualTo(0.72));
  });
}
