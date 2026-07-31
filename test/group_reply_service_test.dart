import 'package:flutter_test/flutter_test.dart';

import 'package:anima/models/character.dart';
import 'package:anima/services/group_reply_service.dart';
import 'package:anima/services/settings_service.dart';

void main() {
  const service = GroupReplyService();

  Character char(String id, String name) =>
      Character(id: id, name: name, systemPrompt: '');

  test('parseBeatReply reads Name: lines in order', () {
    final angela = char('a', 'Angela');
    final marcus = char('m', 'Marcus');
    const raw = '''
Angela: *her eyes widen* "You're serious?"
Marcus: *steps closer, jaw tight*
''';
    final beats = service.parseBeatReply(raw, [angela, marcus]);
    expect(beats, hasLength(2));
    expect(beats[0].character.id, 'a');
    expect(beats[0].text, contains('eyes widen'));
    expect(beats[1].character.id, 'm');
    expect(beats[1].text, contains('steps closer'));
  });

  test('parseBeatReply skips unknown names and duplicates', () {
    final angela = char('a', 'Angela');
    const raw = '''
1. Angela: First line.
2. Angela: Duplicate.
Stranger: Who?
Angela: Third should be skipped.
''';
    final beats = service.parseBeatReply(raw, [angela]);
    expect(beats, hasLength(1));
    expect(beats.first.text, contains('First line'));
  });

  test('buildBeatMessages requires at least two speakers', () {
    final msgs = service.buildBeatMessages(
      speakers: [char('a', 'Angela')],
      allInChat: [char('a', 'Angela')],
      historyApiMessages: const [],
      userName: 'Jay',
    );
    expect(msgs, isEmpty);
  });

  test('buildBeatMessages lists silent cast and format', () {
    final angela = char('a', 'Angela');
    final marcus = char('m', 'Marcus');
    final edric = char('e', 'Edric');
    final msgs = service.buildBeatMessages(
      speakers: [angela, marcus],
      allInChat: [angela, marcus, edric],
      historyApiMessages: [
        {'role': 'user', 'content': 'Jay: We need to talk.'},
      ],
      userName: 'Jay',
      nudge: 'everyone reacts to the news',
    );
    expect(msgs, isNotEmpty);
    final system = msgs.first['content']!;
    expect(system, contains('Angela'));
    expect(system, contains('Marcus'));
    expect(system, contains('silent in this beat'));
    expect(system, contains('Edric'));
    expect(system, contains('coordinated group beat'));
    final user = msgs.lastWhere((m) => m['role'] == 'user');
    expect(user['content'], contains('everyone reacts'));
  });

  test('beatSampling caps tokens by speaker count', () {
    const base = SamplingSettings(maxTokens: 500, temperature: 0.9);
    final two = GroupReplyService.beatSampling(base, 2);
    final six = GroupReplyService.beatSampling(base, 6);
    expect(two.maxTokens, 500);
    expect(six.maxTokens, 1088);
    expect(two.maxTokens, lessThan(six.maxTokens!));
    expect(six.maxTokens, lessThanOrEqualTo(1400));
  });

  test('beatSampling ignores low user max_tokens below beat budget', () {
    const short = SamplingSettings(maxTokens: 350, temperature: 0.7);
    final tuned = GroupReplyService.beatSampling(short, 3);
    expect(tuned.maxTokens, greaterThanOrEqualTo(608));
  });

  test('parseBeatReply fills missing speakers from multiline block', () {
    final angela = char('a', 'Angela');
    final marcus = char('m', 'Marcus');
    final edric = char('e', 'King Edric Vyre III');
    const raw = '''
Angela: *gasps* "No way."

King Edric Vyre III: *his jaw tightens* "We move at dawn."
Marcus: *steps between them* "Enough."
''';
    final beats = service.parseBeatReply(raw, [angela, marcus, edric]);
    expect(beats, hasLength(3));
    expect(beats.map((b) => b.character.id), ['a', 'm', 'e']);
  });

  test('buildBeatMessages warns against copying prior beat text', () {
    final angela = char('a', 'Angela');
    final marcus = char('m', 'Marcus');
    final msgs = service.buildBeatMessages(
      speakers: [angela, marcus],
      allInChat: [angela, marcus],
      historyApiMessages: const [],
      userName: 'Jay',
      priorBeatToAvoid: 'Angela: *old line* "Same words."',
    );
    final user = msgs.lastWhere((m) => m['role'] == 'user');
    expect(user['content'], contains('Do NOT reuse'));
    expect(user['content'], contains('old line'));
    final system = msgs.first['content']!;
    expect(system, contains('Never copy'));
  });

  test('parseBeatReply matches shortened names to full card names', () {
    final edric = char('e', 'King Edric Vyre III');
    final marcus = char('m', 'Marcus');
    const raw = '''
Edric: *nods slowly* "Understood."
Marcus: *scoffs* "As if."
''';
    final beats = service.parseBeatReply(raw, [edric, marcus]);
    expect(beats, hasLength(2));
    expect(beats.first.character.id, 'e');
  });
}
