import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/chat_message.dart';
import '../models/chat_session.dart';
import '../models/character.dart';
import 'prompt_builder.dart';

/// Saves chat threads on this device, grouped by character.
///
/// File: app documents / `anima_chats.json`
/// Nothing here is uploaded to GitHub.
class ChatService {
  ChatService({Future<Directory> Function()? documentsDirectory})
      : _documentsDirectory =
            documentsDirectory ?? getApplicationDocumentsDirectory;

  static const _fileName = 'anima_chats.json';

  final Future<Directory> Function() _documentsDirectory;

  Future<File> _file() async {
    final dir = await _documentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  Future<Map<String, dynamic>> _readRoot() async {
    final file = await _file();
    if (!await file.exists()) return {};
    try {
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return {};
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      return {};
    } catch (_) {
      return {};
    }
  }

  Future<void> _writeRoot(Map<String, dynamic> root) async {
    final file = await _file();
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(root));
  }

  /// All chats for one character, newest first.
  Future<List<ChatSession>> listChats(String characterId) async {
    final root = await _readRoot();
    final entry = root[characterId];
    if (entry is! Map) return [];
    final chatsRaw = entry['chats'];
    if (chatsRaw is! List) return [];
    final chats = <ChatSession>[];
    for (final item in chatsRaw) {
      if (item is Map) {
        final session = ChatSession.fromJson(Map<String, dynamic>.from(item));
        if (session.id.isNotEmpty) chats.add(session);
      }
    }
    chats.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return chats;
  }

  Future<String?> getActiveChatId(String characterId) async {
    final root = await _readRoot();
    final entry = root[characterId];
    if (entry is! Map) return null;
    final id = entry['activeChatId'] as String?;
    if (id == null || id.isEmpty) return null;
    return id;
  }

  Future<void> setActiveChatId(String characterId, String chatId) async {
    final root = await _readRoot();
    final entry = Map<String, dynamic>.from(
      root[characterId] is Map
          ? Map<String, dynamic>.from(root[characterId] as Map)
          : {'chats': <dynamic>[], 'activeChatId': null},
    );
    entry['activeChatId'] = chatId;
    root[characterId] = entry;
    await _writeRoot(root);
  }

  /// Loads the active chat for a character, or creates one with a greeting.
  Future<ChatSession> loadOrCreateActiveChat(
    Character character, {
    String userName = 'User',
  }) async {
    final chats = await listChats(character.id);
    final activeId = await getActiveChatId(character.id);

    if (activeId != null) {
      for (final chat in chats) {
        if (chat.id == activeId) return chat;
      }
    }
    if (chats.isNotEmpty) {
      await setActiveChatId(character.id, chats.first.id);
      return chats.first;
    }

    return startNewChat(character, userName: userName);
  }

  /// Starts a fresh chat (keeps older chats). Adds greeting swipe(s) if set.
  Future<ChatSession> startNewChat(
    Character character, {
    String userName = 'User',
  }) async {
    final builder = const PromptBuilder();
    final greetings = character.allGreetings
        .map(
          (g) => builder.expandGreeting(
            greeting: g,
            character: character,
            userName: userName,
          ),
        )
        .where((g) => g.trim().isNotEmpty)
        .toList();

    final messages = <ChatMessage>[];
    if (greetings.isNotEmpty) {
      messages.add(
        ChatMessage(
          id: ChatMessage.newId(),
          role: ChatRole.assistant,
          text: greetings.first,
          swipes: greetings,
          swipeIndex: 0,
        ),
      );
    }

    final session = ChatSession(
      id: ChatSession.newId(),
      characterId: character.id,
      title: _defaultTitle(character),
      updatedAt: DateTime.now(),
      messages: messages,
    );

    await saveChat(session);
    await setActiveChatId(character.id, session.id);
    return session;
  }

  Future<void> saveChat(ChatSession session) async {
    final root = await _readRoot();
    final entry = Map<String, dynamic>.from(
      root[session.characterId] is Map
          ? Map<String, dynamic>.from(root[session.characterId] as Map)
          : {'chats': <dynamic>[], 'activeChatId': session.id},
    );

    final chatsRaw = entry['chats'] is List
        ? List<dynamic>.from(entry['chats'] as List)
        : <dynamic>[];

    final updatedSession = session.copyWith(updatedAt: DateTime.now());
    final encoded = updatedSession.toJson();
    final index = chatsRaw.indexWhere(
      (item) => item is Map && item['id'] == session.id,
    );
    if (index >= 0) {
      chatsRaw[index] = encoded;
    } else {
      chatsRaw.add(encoded);
    }

    entry['chats'] = chatsRaw;
    entry['activeChatId'] = entry['activeChatId'] ?? session.id;
    root[session.characterId] = entry;
    await _writeRoot(root);
  }

  Future<void> deleteChat(String characterId, String chatId) async {
    final root = await _readRoot();
    final entry = root[characterId];
    if (entry is! Map) return;

    final map = Map<String, dynamic>.from(entry);
    final chatsRaw = map['chats'] is List
        ? List<dynamic>.from(map['chats'] as List)
        : <dynamic>[];
    chatsRaw.removeWhere((item) => item is Map && item['id'] == chatId);
    map['chats'] = chatsRaw;

    if (map['activeChatId'] == chatId) {
      map['activeChatId'] =
          chatsRaw.isNotEmpty && chatsRaw.first is Map
              ? (chatsRaw.first as Map)['id']
              : null;
    }

    root[characterId] = map;
    await _writeRoot(root);
  }

  String _defaultTitle(Character character) {
    final stamp = DateTime.now();
    final mm = stamp.month.toString().padLeft(2, '0');
    final dd = stamp.day.toString().padLeft(2, '0');
    final hh = stamp.hour.toString().padLeft(2, '0');
    final min = stamp.minute.toString().padLeft(2, '0');
    return '${character.name} · $mm/$dd $hh:$min';
  }

  /// Storage bucket for multi-character group chats.
  static const groupsKey = '__groups__';

  /// All group chats, newest first.
  Future<List<ChatSession>> listGroupChats() => listChats(groupsKey);

  /// Start a group chat with 2+ characters (round-robin replies).
  Future<ChatSession> startGroupChat(
    List<Character> members, {
    String userName = 'User',
  }) async {
    if (members.length < 2) {
      throw ArgumentError('Group chats need at least two characters.');
    }
    final builder = const PromptBuilder();
    final first = members.first;
    final greetings = first.allGreetings
        .map(
          (g) => builder.expandGreeting(
            greeting: g,
            character: first,
            userName: userName,
          ),
        )
        .where((g) => g.trim().isNotEmpty)
        .toList();

    final messages = <ChatMessage>[];
    if (greetings.isNotEmpty) {
      messages.add(
        ChatMessage(
          id: ChatMessage.newId(),
          role: ChatRole.assistant,
          text: greetings.first,
          swipes: greetings,
          swipeIndex: 0,
          speakerId: first.id,
          speakerName: first.name,
        ),
      );
    }

    final names = members.map((m) => m.name.trim()).where((n) => n.isNotEmpty);
    final stamp = DateTime.now();
    final mm = stamp.month.toString().padLeft(2, '0');
    final dd = stamp.day.toString().padLeft(2, '0');
    final hh = stamp.hour.toString().padLeft(2, '0');
    final min = stamp.minute.toString().padLeft(2, '0');

    final session = ChatSession(
      id: ChatSession.newId(),
      characterId: groupsKey,
      title: 'Group · ${names.join(', ')} · $mm/$dd $hh:$min',
      updatedAt: DateTime.now(),
      messages: messages,
      participantIds: members.map((m) => m.id).toList(),
      nextSpeakerIndex: greetings.isEmpty ? 0 : 1 % members.length,
    );

    await saveChat(session);
    await setActiveChatId(groupsKey, session.id);
    return session;
  }
}
