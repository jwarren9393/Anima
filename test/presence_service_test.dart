import 'package:flutter_test/flutter_test.dart';

import 'package:anima/models/character.dart';
import 'package:anima/models/chat_message.dart';
import 'package:anima/services/presence_service.dart';

void main() {
  const presence = PresenceService();

  Character char(String id, String name) => Character(id: id, name: name);

  group('PresenceService history', () {
    test('hides private scene from uninvolved cast', () {
      final mira = char('m1', 'Mira');
      final edric = char('e1', 'Edric');
      final messages = [
        ChatMessage(
          id: 'n1',
          role: ChatRole.narrator,
          text: 'You pull Mira aside into the study, alone.',
        ),
        ChatMessage(id: 'u1', role: ChatRole.user, text: 'Listen closely.'),
        ChatMessage(
          id: 'a1',
          role: ChatRole.assistant,
          text: 'I hear you.',
          speakerId: mira.id,
          speakerName: 'Mira',
        ),
      ];

      final history = presence.filterHistoryForCharacter(
        history: messages,
        allMessages: messages,
        focusCharacter: edric,
        participants: [mira, edric],
        userName: 'Alex',
      );

      expect(history, isEmpty);
    });

    test('targeted user line hidden from unaddressed cast', () {
      final mira = char('m1', 'Mira');
      final king = char('k1', 'King Aethlor');
      final messages = [
        ChatMessage(
          id: 'u1',
          role: ChatRole.user,
          text: 'Mira, meet me after court.',
        ),
      ];

      final history = presence.filterHistoryForCharacter(
        history: messages,
        allMessages: messages,
        focusCharacter: king,
        participants: [king, mira],
        userName: 'Aedric',
      );

      expect(history, isEmpty);
    });

    test('keeps shared scene for present characters', () {
      final mira = char('m1', 'Mira');
      final edric = char('e1', 'Edric');
      final messages = [
        ChatMessage(
          id: 'n1',
          role: ChatRole.narrator,
          text: 'Edric and Mira stand together in the hall.',
        ),
        ChatMessage(id: 'u1', role: ChatRole.user, text: 'Both of you, listen.'),
        ChatMessage(
          id: 'a1',
          role: ChatRole.assistant,
          text: 'Yes?',
          speakerId: edric.id,
          speakerName: 'Edric',
        ),
      ];

      final history = presence.filterHistoryForCharacter(
        history: messages,
        allMessages: messages,
        focusCharacter: mira,
        participants: [mira, edric],
        userName: 'Alex',
      );

      expect(history.length, 3);
    });

    test('solo chat keeps user and character history', () {
      final luna = char('l1', 'Luna');
      final messages = [
        ChatMessage(id: 'u1', role: ChatRole.user, text: 'Hello.'),
        ChatMessage(
          id: 'a1',
          role: ChatRole.assistant,
          text: 'Hi.',
          speakerName: 'Luna',
        ),
      ];

      final history = presence.filterHistoryForCharacter(
        history: messages,
        allMessages: messages,
        focusCharacter: luna,
        participants: [luna],
        userName: 'Alex',
      );

      expect(history.length, 2);
    });

    test('narrator line hidden from characters not in that beat', () {
      final mira = char('m1', 'Mira');
      final edric = char('e1', 'Edric');
      final messages = [
        ChatMessage(
          id: 'n1',
          role: ChatRole.narrator,
          text: 'Mira waits in the garden.',
        ),
      ];

      final history = presence.filterHistoryForCharacter(
        history: messages,
        allMessages: messages,
        focusCharacter: edric,
        participants: [mira, edric],
        userName: 'Alex',
      );

      expect(history, isEmpty);
    });

    test('solo chat keeps full history without filtering', () {
      final luna = char('l1', 'Luna');
      final messages = [
        ChatMessage(
          id: 'n1',
          role: ChatRole.narrator,
          text: 'Mira waits in the garden alone.',
        ),
        ChatMessage(id: 'u1', role: ChatRole.user, text: 'Secret for Mira.'),
      ];

      final history = presence.filterHistoryForCharacter(
        history: messages,
        allMessages: messages,
        focusCharacter: luna,
        participants: [luna],
        userName: 'Alex',
      );

      expect(history.length, 2);
    });

    test('narrator first name matches full cast name for presence', () {
      final ashley = char('a1', 'Ashley Diamond');
      final jaisha = char('j1', 'Jaisha Diamond');
      final messages = [
        ChatMessage(
          id: 'n1',
          role: ChatRole.narrator,
          text:
              'Ashley walks into the kitchen smiling at the two of them on the floor.',
        ),
      ];

      final history = presence.filterHistoryForCharacter(
        history: messages,
        allMessages: messages,
        focusCharacter: ashley,
        participants: [ashley, jaisha],
        userName: 'Jay',
      );

      expect(history.length, 1);
      expect(history.first.isNarrator, isTrue);
    });

    test('narrator everyone phrase includes full cast', () {
      final ashley = char('a1', 'Ashley Diamond');
      final jaisha = char('j1', 'Jaisha Diamond');
      final bam = char('b1', 'Bam');
      final present = presence.physicallyPresentFromLatestNarrator(
        messages: [
          ChatMessage(
            id: 'n1',
            role: ChatRole.narrator,
            text: 'Everyone is in the living room for movie night.',
          ),
        ],
        participants: [ashley, jaisha, bam],
        userName: 'Jay',
      );
      expect(present, contains('jay'));
      expect(present, contains('ashley diamond'));
      expect(present, contains('jaisha diamond'));
      expect(present, contains('bam'));
    });

    test('narrator departure keeps other cast and removes leaver', () {
      final ashley = char('a1', 'Ashley Diamond');
      final jaisha = char('j1', 'Jaisha Diamond');
      final bam = char('b1', 'Bam');
      final jessica = char('s1', 'Jessica');
      final participants = [ashley, jaisha, bam, jessica];
      final priorMessages = [
        ChatMessage(
          id: 'n0',
          role: ChatRole.narrator,
          text: 'Everyone is in the kitchen.',
        ),
        ChatMessage(id: 'u1', role: ChatRole.user, text: 'Morning.'),
      ];
      final snapshot = presence.sceneSnapshotFromLatestNarrator(
        messages: [
          ...priorMessages,
          ChatMessage(
            id: 'n1',
            role: ChatRole.narrator,
            text: 'Jay leaves the house and Jaisha comes back downstairs.',
          ),
        ],
        participants: participants,
        userName: 'Jay',
      );
      expect(snapshot.departed, contains('jay'));
      expect(snapshot.arriving, contains('jaisha diamond'));
      expect(snapshot.present, isNot(contains('jay')));
      expect(snapshot.present, contains('ashley diamond'));
      expect(snapshot.present, contains('jaisha diamond'));
      expect(snapshot.present, contains('bam'));
      expect(snapshot.present, contains('jessica'));
    });
  });

  group('PresenceService memory', () {
    test('filters secret known by tag', () {
      final memory = '''
- Location: The tower
- Secret (known by Mira, Aedric): The hidden key
- Secret (known by Edric): He saw the letter
''';

      final miraMemory = presence.filterMemoryForCharacter(
        memory: memory,
        characterName: 'Mira',
        userName: 'Alex',
        castNames: ['Mira', 'Edric', 'Alex'],
      );
      expect(miraMemory, contains('hidden key'));
      expect(miraMemory, isNot(contains('saw the letter')));

      final edricMemory = presence.filterMemoryForCharacter(
        memory: memory,
        characterName: 'Edric',
        userName: 'Alex',
        castNames: ['Mira', 'Edric', 'Alex'],
      );
      expect(edricMemory, contains('saw the letter'));
      expect(edricMemory, contains('tower'));
      expect(edricMemory, isNot(contains('hidden key')));
    });

    test('keeps public location bullets for everyone', () {
      const memory = '- Location: Harbor district';
      final out = presence.filterMemoryForCharacter(
        memory: memory,
        characterName: 'Edric',
        userName: 'Alex',
        castNames: ['Mira', 'Edric'],
      );
      expect(out, contains('Harbor'));
    });

    test('hides untagged private events naming other cast', () {
      const memory = '- Event: Mira slipped the letter to Aedric in private.';
      final out = presence.filterMemoryForCharacter(
        memory: memory,
        characterName: 'Edric',
        userName: 'Alex',
        castNames: ['Mira', 'Edric', 'Alex'],
      );
      expect(out.trim(), isEmpty);
    });

    test('hides untagged events with no cast names', () {
      const memory = '- Event: Someone whispered a secret in the hall.';
      final out = presence.filterMemoryForCharacter(
        memory: memory,
        characterName: 'Edric',
        userName: 'Alex',
        castNames: ['Mira', 'Edric'],
      );
      expect(out.trim(), isEmpty);
    });
  });
}
