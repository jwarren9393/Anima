import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:anima/models/character.dart';
import 'package:anima/models/chat_message.dart';
import 'package:anima/models/chat_session.dart';
import 'package:anima/services/character_card_codec.dart';
import 'package:anima/services/chat_transcript_codec.dart';
import 'package:anima/services/settings_service.dart';

void main() {
  group('chat transcripts', () {
    final codec = ChatTranscriptCodec();

    ChatSession sampleSession() {
      return ChatSession(
        id: 'chat_1',
        characterId: 'char_1',
        title: 'Cafe night',
        updatedAt: DateTime.utc(2026, 7, 17),
        messages: [
          ChatMessage(
            id: 'm1',
            role: ChatRole.assistant,
            text: 'Evening.',
            swipes: const ['Evening.', 'We are closing.'],
            swipeIndex: 0,
          ),
          ChatMessage(
            id: 'm2',
            role: ChatRole.user,
            text: 'One coffee, please.',
          ),
        ],
      );
    }

    test('round-trips Anima JSON with swipes', () {
      final character = Character(id: 'char_1', name: 'Aiko');
      final json = codec.toJson(sampleSession(), character: character);
      final map = jsonDecode(json) as Map<String, dynamic>;
      expect(map['format'], ChatTranscriptCodec.formatId);
      expect(map['characterName'], 'Aiko');

      final imported = codec.parseJsonString(
        json,
        characterId: 'char_1',
      );
      expect(imported.messages, hasLength(2));
      expect(imported.messages.first.swipes, hasLength(2));
      expect(imported.messages.last.text, 'One coffee, please.');
      expect(imported.id, isNot('chat_1')); // new id on import
    });

    test('exports and imports plain text', () {
      final character = Character(id: 'char_1', name: 'Aiko');
      final text = codec.toPlainText(
        sampleSession(),
        character: character,
        userName: 'Sam',
      );
      expect(text, contains('Aiko: Evening.'));
      expect(text, contains('Sam: One coffee, please.'));

      final imported = codec.parsePlainText(
        text,
        characterId: 'char_1',
        characterName: 'Aiko',
        userName: 'Sam',
      );
      expect(imported.messages.length, greaterThanOrEqualTo(2));
      expect(imported.messages.first.isUser, isFalse);
      expect(imported.messages.any((m) => m.isUser), isTrue);
    });
  });

  group('PNG card export', () {
    final codec = CharacterCardCodec();

    test('embeds chara chunk that re-imports', () {
      final character = Character(
        id: 'char_png',
        name: 'Luna',
        description: 'A quiet astronomer.',
        firstMes: 'Look up.',
        personality: 'Curious',
      );
      final png = codec.toCardPng(character);
      expect(png[0], 137);
      expect(png[1], 80);

      final roundTrip = codec.parseBytes(png, preferredId: 'char_png');
      expect(roundTrip.name, 'Luna');
      expect(roundTrip.description, 'A quiet astronomer.');
      expect(roundTrip.firstMes, 'Look up.');
    });

    test('V3 PNG includes ccv3 and still parses', () {
      final character = Character(
        id: 'char_v3',
        name: 'V3Bot',
        description: 'desc',
        firstMes: 'Hi',
      );
      final png = codec.toCardPng(character, asV3: true);
      final extracted = codec.extractJsonFromPng(png);
      expect(extracted, isNotNull);
      final map = jsonDecode(extracted!) as Map<String, dynamic>;
      // Prefer ccv3 → should be V3 spec when both present (extract prefers ccv3).
      expect(map['spec'], 'chara_card_v3');
    });
  });

  group('sampling defaults', () {
    test('SamplingSettings defaults are sensible', () {
      const s = SamplingSettings();
      expect(s.temperature, 0.8);
      expect(s.topP, 0.95);
      expect(s.maxTokens, isNull);
      expect(SettingsService.subscriptionBaseUrl, contains('subscription'));
    });
  });
}
