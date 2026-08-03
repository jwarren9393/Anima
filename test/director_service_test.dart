import 'package:flutter_test/flutter_test.dart';

import 'package:anima/models/chat_message.dart';
import 'package:anima/models/chat_session.dart';
import 'package:anima/services/director_service.dart';

void main() {
  const director = DirectorService();

  group('DirectorService', () {
    test('active instruction is mandatory and names the character', () {
      final block = director.formatActiveInstruction(
        text: 'Mira looks suspicious and asks where they went.',
        charName: 'Mira',
        userName: 'Alex',
      );
      expect(block, contains('MANDATORY'));
      expect(block, contains('Mira looks suspicious'));
      expect(block, contains('Mira MUST follow'));
      expect(block, contains('NOT dialogue from Alex'));
    });

    test('pendingText resolves from session id', () {
      const noteId = 'dir_1';
      final session = ChatSession(
        id: 'c1',
        characterId: 'char',
        title: 'Test',
        updatedAt: DateTime(2026),
        messages: [
          ChatMessage(id: noteId, role: ChatRole.director, text: 'She hesitates.'),
        ],
        pendingDirectorMessageId: noteId,
      );
      expect(director.pendingText(session), 'She hesitates.');
    });

    test('reconcilePendingId clears when note removed', () {
      final messages = [
        ChatMessage(id: 'u1', role: ChatRole.user, text: 'Hi'),
      ];
      expect(
        director.reconcilePendingId(messages, 'dir_missing'),
        isNull,
      );
    });
  });
}
