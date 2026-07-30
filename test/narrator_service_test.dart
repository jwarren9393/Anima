import 'package:anima/models/chat_message.dart';
import 'package:anima/services/narrator_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const service = NarratorService();

  test('ChatMessage narrator role round-trips JSON', () {
    final message = ChatMessage(
      id: 'n1',
      role: ChatRole.narrator,
      text: '*Rain drums on the roof.*',
    );
    final json = message.toJson();
    expect(json['role'], 'narrator');
    final restored = ChatMessage.fromJson(json);
    expect(restored.isNarrator, isTrue);
    expect(restored.text, message.text);
  });

  test('formatForPrompt labels omniscient narrator', () {
    final block = service.formatForPrompt(
      text: 'The door creaks open.',
      userName: 'Jay',
      charName: 'Luna',
    );
    expect(block, contains('Narrator'));
    expect(block, contains('The door creaks open.'));
    expect(block, contains('not Jay or Luna speaking'));
  });

  test('buildGenerateMessages includes nudge and draft', () {
    final messages = service.buildGenerateMessages(
      userName: 'Jay',
      characterName: 'Luna',
      recentMessages: [
        ChatMessage(id: 'u1', role: ChatRole.user, text: 'Hello?'),
        ChatMessage(
          id: 'a1',
          role: ChatRole.assistant,
          text: '*She looks up.* "Hi."',
        ),
      ],
      nudge: 'Make it stormy',
      existingDraft: 'Wind howls.',
    );
    expect(messages.length, 2);
    final user = messages.last['content']!;
    expect(user, contains('Make it stormy'));
    expect(user, contains('Wind howls.'));
    expect(user, contains('Jay: Hello?'));
  });

  test('buildGenerateMessages includes prior narrator lines in context', () {
    final messages = service.buildGenerateMessages(
      userName: 'Jay',
      characterName: 'Luna',
      recentMessages: [
        ChatMessage(
          id: 'n1',
          role: ChatRole.narrator,
          text: 'Candles flicker.',
        ),
      ],
    );
    expect(messages.last['content'], contains('Narrator: Candles flicker.'));
  });
}
