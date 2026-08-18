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

  test('formatForPrompt labels mandatory scene law', () {
    final block = service.formatForPrompt(
      text: 'The door creaks open.',
      userName: 'Jay',
      charName: 'Luna',
    );
    expect(block, contains('PLAYER NARRATOR'));
    expect(block, contains('SCENE LAW'));
    expect(block, contains('MANDATORY'));
    expect(block, contains('The door creaks open.'));
    expect(block, contains('NOT a suggestion'));
    expect(block, contains('MUST treat location and who is present as true'));
  });

  test('latestNarratorId returns most recent narrator before end', () {
    final id = service.latestNarratorId(
      [
        ChatMessage(
          id: 'n1',
          role: ChatRole.narrator,
          text: 'Old beat.',
        ),
        ChatMessage(id: 'u1', role: ChatRole.user, text: 'Hi'),
        ChatMessage(
          id: 'n2',
          role: ChatRole.narrator,
          text: 'New beat.',
        ),
      ],
      endExclusive: 3,
    );
    expect(id, 'n2');
  });

  test('historyBlockFor skips active narrator', () {
    final message = ChatMessage(
      id: 'n2',
      role: ChatRole.narrator,
      text: 'Active.',
    );
    expect(
      service.historyBlockFor(message: message, activeNarratorId: 'n2'),
      isNull,
    );
    final historical = service.historyBlockFor(
      message: message,
      activeNarratorId: 'n1',
    );
    expect(historical, isNotNull);
    expect(historical!['content'], contains('Earlier narrator beat'));
  });

  test('activeSceneLawBlock adds entrance line when speaker is named', () {
    final block = service.activeSceneLawBlock(
      messages: [
        ChatMessage(
          id: 'n1',
          role: ChatRole.narrator,
          text: 'Ashley walks into the kitchen smiling at the two of them.',
        ),
      ],
      activeNarratorId: 'n1',
      userName: 'Jay',
      charName: 'Ashley Diamond',
      isGroup: true,
      speakingAsName: 'Ashley Diamond',
      physicallyPresent: {'jay', 'jaisha diamond', 'ashley diamond'},
    );
    expect(block, isNotNull);
    expect(block!, contains('You are Ashley Diamond'));
    expect(block, contains('ARE physically in this scene'));
    expect(block, contains('phone'));
    expect(block, isNot(contains('already moved on')));
  });

  test('activeSceneLawBlock suppresses entrance after speaker already replied', () {
    final block = service.activeSceneLawBlock(
      messages: [
        ChatMessage(
          id: 'n1',
          role: ChatRole.narrator,
          text: 'Ashley walks into the kitchen smiling at the two of them.',
        ),
        ChatMessage(id: 'u1', role: ChatRole.user, text: 'Hey Ash.'),
        ChatMessage(
          id: 'a1',
          role: ChatRole.assistant,
          speakerName: 'Ashley Diamond',
          text: '*She grins.* "Hey guys!"',
        ),
        ChatMessage(id: 'u2', role: ChatRole.user, text: 'Come sit.'),
      ],
      activeNarratorId: 'n1',
      userName: 'Jay',
      charName: 'Ashley Diamond',
      isGroup: true,
      speakingAsName: 'Ashley Diamond',
      physicallyPresent: {'jay', 'jaisha diamond', 'ashley diamond'},
      endExclusive: 4,
      excludeMessageIndex: 3,
    );
    expect(block, isNotNull);
    expect(block!, contains('already moved on'));
    expect(block, contains('Do NOT'));
    expect(block, contains('re-walk-in'));
    expect(block, isNot(contains('enact your entrance')));
    expect(block, isNot(contains('You are Ashley Diamond — enact')));
  });

  test('activeSceneLawBlock tells cast not to steal another arrival beat', () {
    final block = service.activeSceneLawBlock(
      messages: [
        ChatMessage(
          id: 'n1',
          role: ChatRole.narrator,
          text: 'Jay leaves the house and Jaisha comes back downstairs.',
        ),
      ],
      activeNarratorId: 'n1',
      userName: 'Jay',
      charName: 'Ashley Diamond',
      isGroup: true,
      speakingAsName: 'Ashley Diamond',
      physicallyPresent: {
        'ashley diamond',
        'jaisha diamond',
        'bam',
        'jessica',
      },
      departedPresent: {'jay'},
      narratorBeatFor: {'jaisha diamond'},
    );
    expect(block, isNotNull);
    expect(block!, contains('NOT physically present'));
    expect(block, contains('jay'));
    expect(block, contains('do NOT perform their action'));
    expect(block, contains('jaisha diamond'));
    expect(block, isNot(contains('Comes back down the stairs')));
  });

  test('userSpokeAfterNarrator detects player line after narrator', () {
    expect(
      service.userSpokeAfterNarrator(
        messages: [
          ChatMessage(
            id: 'n1',
            role: ChatRole.narrator,
            text: 'Jay comes home.',
          ),
          ChatMessage(id: 'u1', role: ChatRole.user, text: 'Hey baby.'),
        ],
        narratorId: 'n1',
      ),
      isTrue,
    );
    expect(
      service.userSpokeAfterNarrator(
        messages: [
          ChatMessage(
            id: 'n1',
            role: ChatRole.narrator,
            text: 'Jay comes home.',
          ),
        ],
        narratorId: 'n1',
      ),
      isFalse,
    );
  });

  test('activeSceneLawBlock tells cast to respond when player already spoke', () {
    final block = service.activeSceneLawBlock(
      messages: [
        ChatMessage(
          id: 'n1',
          role: ChatRole.narrator,
          text:
              'Later that evening, Jay comes back home and Ashley is in the living room.',
        ),
        ChatMessage(id: 'u1', role: ChatRole.user, text: 'Hey baby, I\'m home.'),
      ],
      activeNarratorId: 'n1',
      userName: 'Jay',
      charName: 'Ashley Diamond',
      isGroup: true,
      speakingAsName: 'Ashley Diamond',
      physicallyPresent: {'jay', 'ashley diamond'},
      narratorBeatFor: {'jay'},
      endExclusive: 2,
    );
    expect(block, isNotNull);
    expect(block!, contains('Jay already spoke'));
    expect(block, contains('respond to their last line'));
  });

  test('activeSceneLawBlock tells Ashley to follow Jaisha after she already spoke', () {
    final block = service.activeSceneLawBlock(
      messages: [
        ChatMessage(
          id: 'n1',
          role: ChatRole.narrator,
          text:
              'An hour later, Jaisha makes it home while Jay and Ashley are on the couch. '
              'Jaisha comes in and hugs them both.',
        ),
        ChatMessage(
          id: 'a1',
          role: ChatRole.assistant,
          speakerName: 'Jaisha Diamond',
          text: '*flops on the couch* "Hi, I missed you both."',
        ),
      ],
      activeNarratorId: 'n1',
      userName: 'Jay',
      charName: 'Ashley Diamond',
      isGroup: true,
      speakingAsName: 'Ashley Diamond',
      physicallyPresent: {'jay', 'ashley diamond', 'jaisha diamond'},
      narratorBeatFor: {'jaisha diamond'},
      endExclusive: 2,
    );
    expect(block, isNotNull);
    expect(block!, contains('already enacted this narrator beat in chat'));
    expect(block, contains('do NOT act surprised'));
    expect(block, isNot(contains('MUST react as if these facts already happened')));
  });

  test('sceneContinuedAfterNarrator detects other cast lines', () {
    final continuation = service.sceneContinuedAfterNarrator(
      messages: [
        ChatMessage(
          id: 'n1',
          role: ChatRole.narrator,
          text: 'Jaisha arrives.',
        ),
        ChatMessage(
          id: 'a1',
          role: ChatRole.assistant,
          speakerName: 'Jaisha Diamond',
          text: 'Hey.',
        ),
      ],
      narratorId: 'n1',
      speakerName: 'Ashley Diamond',
    );
    expect(continuation.continued, isTrue);
    expect(continuation.castWhoSpoke, contains('Jaisha Diamond'));
  });

  test('characterAlreadyRepliedSinceNarrator matches first names', () {
    expect(
      service.characterAlreadyRepliedSinceNarrator(
        messages: [
          ChatMessage(
            id: 'n1',
            role: ChatRole.narrator,
            text: 'Ashley enters.',
          ),
          ChatMessage(
            id: 'a1',
            role: ChatRole.assistant,
            speakerName: 'Ashley',
            text: '*waves*',
          ),
        ],
        narratorId: 'n1',
        speakerName: 'Ashley Diamond',
      ),
      isTrue,
    );
  });

  test('activeSceneLawBlock off-screen cast knows scene but not dialogue', () {
    final block = service.activeSceneLawBlock(
      messages: [
        ChatMessage(
          id: 'n1',
          role: ChatRole.narrator,
          text:
              'Jay and Jaisha wrestle on the kitchen floor, flour everywhere.',
        ),
      ],
      activeNarratorId: 'n1',
      userName: 'Jay',
      charName: 'Bam',
      isGroup: true,
      speakingAsName: 'Bam',
      physicallyPresent: {'jay', 'jaisha diamond'},
    );
    expect(block, isNotNull);
    expect(block!, contains('NOT physically in this scene yet'));
    expect(block, contains('kitchen'));
    expect(block, contains('did NOT hear private dialogue'));
  });

  test('activeSceneLawBlock returns mandatory block for latest narrator', () {
    final block = service.activeSceneLawBlock(
      messages: [
        ChatMessage(
          id: 'n1',
          role: ChatRole.narrator,
          text: 'Rain falls.',
        ),
      ],
      activeNarratorId: 'n1',
      userName: 'Jay',
      charName: 'Luna',
    );
    expect(block, isNotNull);
    expect(block!, contains('Rain falls.'));
    expect(block, contains('MANDATORY'));
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
