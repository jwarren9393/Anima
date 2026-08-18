import 'package:flutter_test/flutter_test.dart';

import 'package:anima/models/character.dart';
import 'package:anima/models/chat_message.dart';
import 'package:anima/models/chat_session.dart';
import 'package:anima/models/lorebook.dart';
import 'package:anima/models/persona.dart';
import 'package:anima/services/chat_session_resolver.dart';
import 'package:anima/services/presence_service.dart';

void main() {
  const resolver = ChatSessionResolver();
  const presence = PresenceService();

  test('resolver prefers chat character override', () {
    const library = Character(id: 'c1', name: 'Mira', description: 'Stranger');
    final session = ChatSession(
      id: 'chat1',
      characterId: 'c1',
      title: 'Test',
      updatedAt: DateTime(2026, 1, 1),
      characterOverrides: {
        'c1': Character(
          id: 'c1',
          name: 'Mira',
          description: 'Dating {{user}}',
        ),
      },
    );

    final resolved = resolver.resolveCharacter(library, session);
    expect(resolved.description, contains('Dating'));
  });

  test('resolver merges chat lorebook', () {
    final session = ChatSession(
      id: 'chat1',
      characterId: 'c1',
      title: 'Test',
      updatedAt: DateTime(2026, 1, 1),
      chatLorebook: const Lorebook(
        name: 'Arc',
        entries: [
          LorebookEntry(id: 1, keys: ['arc'], content: 'Story facts'),
        ],
      ),
    );
    expect(resolver.chatLorebooks(session), hasLength(1));
  });

  test('session round-trips overrides and chat lore', () {
    final session = ChatSession(
      id: 'chat1',
      characterId: 'c1',
      title: 'Test',
      updatedAt: DateTime(2026, 1, 1),
      characterOverrides: {
        'c1': const Character(id: 'c1', name: 'Mira'),
      },
      personaOverride: const Persona(id: 'p1', name: 'Jay'),
      chatLorebook: const Lorebook(
        name: 'Thread lore',
        entries: [
          LorebookEntry(id: 1, keys: ['dating'], content: 'They are together.'),
        ],
      ),
    );

    final restored = ChatSession.fromJson(session.toJson());
    expect(restored.characterOverrides['c1']?.name, 'Mira');
    expect(restored.personaOverride?.name, 'Jay');
    expect(restored.chatLorebook?.name, 'Thread lore');
  });

  test('ensureLastUserMessageIncluded keeps latest user line for replies', () {
    final messages = [
      ChatMessage(id: 'n1', role: ChatRole.narrator, text: 'Only Aria is here.'),
      ChatMessage(id: 'u1', role: ChatRole.user, text: 'Hello Aria.'),
      ChatMessage(
        id: 'a1',
        role: ChatRole.assistant,
        text: 'Hi.',
        speakerName: 'Aria',
      ),
      ChatMessage(id: 'u2', role: ChatRole.user, text: 'What did I just say?'),
    ];

    final filtered = presence.filterHistoryForCharacter(
      history: messages,
      allMessages: messages,
      focusCharacter: const Character(id: 'b1', name: 'Bren'),
      participants: const [
        Character(id: 'a1', name: 'Aria'),
        Character(id: 'b1', name: 'Bren'),
      ],
      userName: 'Jay',
    );
    expect(filtered.any((m) => m.id == 'u2'), isFalse);

    final fixed = presence.ensureLastUserMessageIncluded(
      visibleHistory: filtered,
      allMessages: messages,
      endExclusive: messages.length,
    );
    expect(fixed.any((m) => m.id == 'u2'), isTrue);
  });
}
