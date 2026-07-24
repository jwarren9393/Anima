import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:anima/models/character.dart';
import 'package:anima/models/chat_message.dart';
import 'package:anima/models/chat_session.dart';
import 'package:anima/services/chat_service.dart';

void main() {
  late Directory tempDir;
  late ChatService chatService;

  Character char(String id, String name) => Character(id: id, name: name);

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('anima_chat_service_test');
    chatService = ChatService(documentsDirectory: () async => tempDir);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('updateSessionCast adds a second character without new chat id', () async {
    final solo = ChatSession(
      id: 'chat_solo',
      characterId: 'alice',
      title: 'Alice chat',
      updatedAt: DateTime(2026, 1, 1),
      messages: [
        ChatMessage(
          id: 'm1',
          role: ChatRole.assistant,
          text: 'Hello',
        ),
      ],
    );
    await chatService.saveChat(solo);

    final updated = await chatService.updateSessionCast(
      solo,
      [char('alice', 'Alice'), char('bob', 'Bob')],
    );

    expect(updated.id, 'chat_solo');
    expect(updated.isGroup, isTrue);
    expect(updated.characterId, ChatService.groupsKey);
    expect(updated.participantIds, ['alice', 'bob']);
    expect(updated.messages.single.text, 'Hello');

    final soloBucket = await chatService.listChats('alice');
    expect(soloBucket, isEmpty);

    final groupBucket = await chatService.listChats(ChatService.groupsKey);
    expect(groupBucket.length, 1);
    expect(groupBucket.single.id, 'chat_solo');
  });

  test('updateSessionCast removes characters down to solo bucket', () async {
    final group = ChatSession(
      id: 'chat_group',
      characterId: ChatService.groupsKey,
      title: 'Group',
      updatedAt: DateTime(2026, 1, 1),
      participantIds: const ['alice', 'bob'],
      messages: [
        ChatMessage(id: 'm1', role: ChatRole.user, text: 'Hi'),
      ],
    );
    await chatService.saveChat(group);

    final updated = await chatService.updateSessionCast(
      group,
      [char('alice', 'Alice')],
    );

    expect(updated.id, 'chat_group');
    expect(updated.isGroup, isFalse);
    expect(updated.characterId, 'alice');
    expect(updated.participantIds, isEmpty);

    final groupBucket = await chatService.listChats(ChatService.groupsKey);
    expect(groupBucket, isEmpty);

    final soloBucket = await chatService.listChats('alice');
    expect(soloBucket.single.id, 'chat_group');
  });

  test('updateSessionCast keeps group bucket when editing members', () async {
    final group = ChatSession(
      id: 'chat_group',
      characterId: ChatService.groupsKey,
      title: 'Group',
      updatedAt: DateTime(2026, 1, 1),
      participantIds: const ['alice', 'bob'],
      nextSpeakerIndex: 1,
      messages: const [],
    );
    await chatService.saveChat(group);

    final updated = await chatService.updateSessionCast(
      group,
      [char('alice', 'Alice'), char('bob', 'Bob'), char('cara', 'Cara')],
    );

    expect(updated.characterId, ChatService.groupsKey);
    expect(updated.participantIds, ['alice', 'bob', 'cara']);
    expect(updated.nextSpeakerIndex, 1);

    final file = File(p.join(tempDir.path, 'anima_chats.json'));
    expect(await file.exists(), isTrue);
    final groupBucket = await chatService.listChats(ChatService.groupsKey);
    expect(groupBucket.single.participantIds.length, 3);
  });
}
