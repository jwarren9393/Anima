import 'package:anima/models/chat_message.dart';
import 'package:anima/services/narrator_service.dart';
import 'package:anima/services/settings_service.dart';
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

  test('inferPresentCast uses recent speakers not full group cast', () {
    final present = service.inferPresentCast(
      userName: 'Trey',
      focusCharacterName: 'Angela',
      messages: [
        ChatMessage(id: 'u1', role: ChatRole.user, text: 'Hey.'),
        ChatMessage(
          id: 'a1',
          role: ChatRole.assistant,
          speakerName: 'Angela',
          text: '*She smiles.*',
        ),
      ],
    );
    expect(present, contains('Trey'));
    expect(present, contains('Angela'));
    expect(present, isNot(contains('Marcus')));
  });

  test('buildGenerateMessages scopes present cast and current scene', () {
    final messages = service.buildGenerateMessages(
      userName: 'Trey',
      characterName: 'Angela',
      recentMessages: [
        ChatMessage(id: 'u1', role: ChatRole.user, text: 'Hello?'),
        ChatMessage(
          id: 'a1',
          role: ChatRole.assistant,
          speakerName: 'Angela',
          text: '*She looks up.* "Hi."',
        ),
      ],
      isGroup: true,
      otherCharacterNames: const ['Marcus', 'Edric'],
      nudge: 'Describe the current scene',
    );
    final system = messages.first['content']!;
    final user = messages.last['content']!;
    expect(system, contains('ONLY the current moment'));
    expect(system, contains('Do not sanitize'));
    expect(user, contains('Present in this scene'));
    expect(user, contains('Trey'));
    expect(user, contains('Angela'));
    expect(user, contains('Marcus'));
    expect(user, contains('omit unless nudge'));
    expect(user, contains('Current scene'));
    expect(messages.first['content'], isNot(contains('Hard rules')));
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
    expect(messages.first['content'], isNot(contains('Hard rules')));
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

  test('generateSampling caps max tokens and raises repeat penalties', () {
    final tuned = NarratorService.generateSampling(
      const SamplingSettings(maxTokens: 2000, temperature: 0.9),
    );
    expect(tuned.maxTokens, NarratorService.generateMaxTokens);
    expect(tuned.temperature, lessThanOrEqualTo(0.62));
    expect(tuned.frequencyPenalty, greaterThanOrEqualTo(0.35));
    expect(tuned.repetitionPenalty, isNotNull);
  });

  test('cleanGeneratedOutput strips instruction leaks', () {
    final raw = '''
*The room is quiet.* Tension coils in the air.

Narrator note (follow closely):
You are the omniscient narrator of an immersive private roleplay.
Hard rules:
- Output ONE narrator passage only.
''';
    final cleaned = service.cleanGeneratedOutput(raw);
    expect(cleaned, contains('Tension coils'));
    expect(cleaned, isNot(contains('Hard rules')));
    expect(cleaned, isNot(contains('Narrator note')));
  });

  test('cleanGeneratedOutput trims and-building loops', () {
    final raw =
        '*She trembles.* The moment stretches. building and building and building and building.';
    final cleaned = service.cleanGeneratedOutput(raw);
    expect(cleaned, contains('moment stretches'));
    expect(cleaned, isNot(contains('building and building')));
  });

  test('cleanGeneratedOutput cuts inline leak after sentence', () {
    final raw =
        '*Rain falls.* You write narrator lines for a private roleplay chat app.';
    final cleaned = service.cleanGeneratedOutput(raw);
    expect(cleaned.trim(), '*Rain falls.*');
  });
}
