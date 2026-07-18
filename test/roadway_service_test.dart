import 'package:flutter_test/flutter_test.dart';

import 'package:anima/models/chat_message.dart';
import 'package:anima/services/roadway_service.dart';

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
    expect(system, contains('ONE cohesive message'));
    expect(system, contains('Do NOT add titles, numbering'));
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
}
