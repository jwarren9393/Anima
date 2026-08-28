import 'package:flutter_test/flutter_test.dart';

import 'package:anima/models/chat_message.dart';
import 'package:anima/models/character.dart';
import 'package:anima/services/group_speaker_inference.dart';

void main() {
  const inference = GroupSpeakerInference();

  Character char(String id, String name) =>
      Character(id: id, name: name, systemPrompt: '');

  test('continues last assistant speaker', () {
    final emma = char('e', 'Emma');
    final madison = char('m', 'Madison');
    final messages = [
      ChatMessage(
        id: '1',
        role: ChatRole.assistant,
        text: 'Hi',
        speakerId: emma.id,
        speakerName: emma.name,
      ),
    ];
    final pick = inference.resolve(
      participants: [emma, madison],
      messages: messages,
      primaryCharacter: madison,
    );
    expect(pick.id, 'e');
  });

  test('after user message prefers name mention then last speaker', () {
    final emma = char('e', 'Emma');
    final madison = char('m', 'Madison');
    final messages = [
      ChatMessage(
        id: '1',
        role: ChatRole.assistant,
        text: 'Hey',
        speakerId: emma.id,
        speakerName: emma.name,
      ),
      ChatMessage(
        id: '2',
        role: ChatRole.user,
        text: 'Madison, what do you think?',
      ),
    ];
    final pick = inference.resolve(
      participants: [emma, madison],
      messages: messages,
    );
    expect(pick.id, 'm');
  });

  test('after user message without mention uses last assistant', () {
    final emma = char('e', 'Emma');
    final madison = char('m', 'Madison');
    final messages = [
      ChatMessage(
        id: '1',
        role: ChatRole.assistant,
        text: 'Hey',
        speakerId: emma.id,
        speakerName: emma.name,
      ),
      ChatMessage(id: '2', role: ChatRole.user, text: 'Sure, sounds good.'),
    ];
    final pick = inference.resolve(
      participants: [emma, madison],
      messages: messages,
    );
    expect(pick.id, 'e');
  });

  test('buildHandoffNudge after another assistant spoke', () {
    final emma = char('e', 'Emma');
    final madison = char('m', 'Madison');
    final messages = [
      ChatMessage(
        id: '1',
        role: ChatRole.assistant,
        text: 'Hey',
        speakerId: emma.id,
        speakerName: emma.name,
      ),
    ];
    final nudge = inference.buildHandoffNudge(
      messages: messages,
      endExclusive: messages.length,
      target: madison,
    );
    expect(nudge, isNotNull);
    expect(nudge!['content'], contains('Emma'));
    expect(nudge['content'], contains('Madison'));
  });

  test('buildHandoffNudge skips when target already spoke last', () {
    final emma = char('e', 'Emma');
    final messages = [
      ChatMessage(
        id: '1',
        role: ChatRole.assistant,
        text: 'Hey',
        speakerId: emma.id,
        speakerName: emma.name,
      ),
    ];
    expect(
      inference.buildHandoffNudge(
        messages: messages,
        endExclusive: messages.length,
        target: emma,
      ),
      isNull,
    );
  });
}
