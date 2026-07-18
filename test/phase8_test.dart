import 'package:flutter_test/flutter_test.dart';

import 'package:anima/models/character.dart';
import 'package:anima/models/chat_session.dart';
import 'package:anima/services/prompt_builder.dart';

void main() {
  group('Phase 8 prompt helpers', () {
    const builder = PromptBuilder();

    test('authors note appears in post-history block', () {
      final character = Character(
        id: 'c1',
        name: 'Aiko',
        postHistoryInstructions: 'Stay cozy.',
      );
      final text = builder.buildPostHistory(
        character: character,
        userName: 'Sam',
        authorsNote: 'Keep replies under 3 sentences.',
      );
      expect(text, contains('Stay cozy.'));
      expect(text, contains("Author's note:"));
      expect(text, contains('3 sentences'));
    });

    test('continue mode asks for character-only continuation', () {
      final character = Character(id: 'c1', name: 'Aiko');
      final system = builder.buildSystemPrompt(
        character: character,
        userName: 'Sam',
        mode: PromptMode.continueScene,
      );
      expect(system.toLowerCase(), contains('continue'));
      expect(system, contains('Aiko'));
    });

    test('impersonate mode asks for user-only line', () {
      final character = Character(id: 'c1', name: 'Aiko');
      final system = builder.buildSystemPrompt(
        character: character,
        userName: 'Sam',
        mode: PromptMode.impersonate,
      );
      expect(system.toLowerCase(), contains('sam'));
      expect(system.toLowerCase(), contains('only'));
    });

    test('group prompt lists other members', () {
      final aiko = Character(id: 'a', name: 'Aiko', description: 'Barista.');
      final luna = Character(id: 'b', name: 'Luna', description: 'Regular.');
      final system = builder.buildSystemPrompt(
        character: aiko,
        userName: 'Sam',
        others: [luna],
      );
      expect(system, contains('group chat'));
      expect(system, contains('Luna'));
      expect(system, contains('Aiko'));
    });
  });

  group('ChatSession group fields', () {
    test('isGroup when multiple participants', () {
      final solo = ChatSession(
        id: '1',
        characterId: 'c1',
        title: 'Solo',
        updatedAt: DateTime.now(),
      );
      expect(solo.isGroup, isFalse);

      final group = ChatSession(
        id: '2',
        characterId: '__groups__',
        title: 'Group',
        updatedAt: DateTime.now(),
        participantIds: const ['a', 'b'],
      );
      expect(group.isGroup, isTrue);
      expect(group.effectiveParticipantIds, ['a', 'b']);
    });

    test('round-trips authorsNote, participants, personaId, and autoReply', () {
      final session = ChatSession(
        id: 'chat_x',
        characterId: '__groups__',
        title: 'Trio',
        updatedAt: DateTime.utc(2026, 7, 17),
        authorsNote: 'Be playful.',
        participantIds: const ['a', 'b', 'c'],
        nextSpeakerIndex: 2,
        personaId: 'persona_sam',
        autoReply: false,
        lorebookIds: const ['lore_1', 'lore_2'],
        memorySummary: 'They met at the harbor.',
        memoryCoveredCount: 12,
      );
      final restored = ChatSession.fromJson(session.toJson());
      expect(restored.authorsNote, 'Be playful.');
      expect(restored.participantIds, ['a', 'b', 'c']);
      expect(restored.nextSpeakerIndex, 2);
      expect(restored.personaId, 'persona_sam');
      expect(restored.autoReply, isFalse);
      expect(restored.lorebookIds, ['lore_1', 'lore_2']);
      expect(restored.memorySummary, 'They met at the harbor.');
      expect(restored.memoryCoveredCount, 12);
      expect(restored.isGroup, isTrue);

      final legacy = ChatSession.fromJson({
        'id': 'old',
        'characterId': 'c1',
        'title': 'Old',
        'updatedAt': DateTime.utc(2026, 1, 1).toIso8601String(),
        'messages': const [],
      });
      expect(legacy.autoReply, isTrue);
      expect(legacy.lorebookIds, isNull);

      final fresh = ChatSession(
        id: 'new',
        characterId: 'c1',
        title: 'New',
        updatedAt: DateTime.utc(2026, 7, 17),
      );
      expect(fresh.autoReply, isFalse);
    });
  });
}
