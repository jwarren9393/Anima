import 'dart:convert';

import '../models/chat_message.dart';
import '../models/chat_session.dart';
import '../models/character.dart';

/// Import / export chat transcripts (Anima JSON + simple plain text).
class ChatTranscriptCodec {
  static const formatId = 'anima_chat_v1';

  /// Full JSON transcript (keeps swipes). Good for backup / re-import.
  String toJson(
    ChatSession session, {
    Character? character,
    bool pretty = true,
  }) {
    final map = <String, dynamic>{
      'format': formatId,
      'exportedAt': DateTime.now().toIso8601String(),
      'characterId': session.characterId,
      if (character != null) 'characterName': character.name,
      'title': session.title,
      'updatedAt': session.updatedAt.toIso8601String(),
      'authorsNote': session.authorsNote,
      'participantIds': session.participantIds,
      'messages': session.messages.map((m) => m.toJson()).toList(),
    };
    return pretty
        ? const JsonEncoder.withIndent('  ').convert(map)
        : jsonEncode(map);
  }

  /// Human-readable transcript (current swipe only).
  String toPlainText(
    ChatSession session, {
    Character? character,
    String userName = 'User',
  }) {
    final charName = character?.name.trim().isNotEmpty == true
        ? character!.name.trim()
        : 'Character';
    final buffer = StringBuffer()
      ..writeln('# ${session.title}')
      ..writeln('# Character: $charName')
      ..writeln('# Exported: ${DateTime.now().toIso8601String()}')
      ..writeln();

    for (final message in session.messages) {
      final text = message.text.trim();
      if (text.isEmpty) continue;
      final speaker = message.isUser ? userName : charName;
      buffer.writeln('$speaker: $text');
      buffer.writeln();
    }
    return buffer.toString().trimRight();
  }

  /// Parse Anima JSON (or a bare Anima [ChatSession] map).
  ChatSession parseJsonString(
    String raw, {
    required String characterId,
    String? preferredTitle,
  }) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException('Chat transcript JSON must be an object.');
    }
    return fromMap(
      Map<String, dynamic>.from(decoded),
      characterId: characterId,
      preferredTitle: preferredTitle,
    );
  }

  ChatSession fromMap(
    Map<String, dynamic> root, {
    required String characterId,
    String? preferredTitle,
  }) {
    // Full anima_chat_v1 wrapper, or a raw ChatSession map.
    final Map<String, dynamic> sessionMap;
    final format = '${root['format'] ?? ''}';
    if (format == formatId || root.containsKey('messages')) {
      sessionMap = root;
    } else {
      throw const FormatException(
        'Unrecognized chat file. Use an Anima chat export (.json).',
      );
    }

    final messages = <ChatMessage>[];
    final rawMessages = sessionMap['messages'];
    if (rawMessages is List) {
      for (final item in rawMessages) {
        if (item is Map) {
          final map = Map<String, dynamic>.from(item);
          // Accept ST-ish {role, content} as well as Anima {role, text}.
          if (!map.containsKey('text') && map.containsKey('content')) {
            map['text'] = map['content'];
          }
          messages.add(ChatMessage.fromJson(map));
        }
      }
    }

    if (messages.isEmpty) {
      throw const FormatException('This chat file has no messages.');
    }

    final title = (preferredTitle ??
            sessionMap['title'] as String? ??
            'Imported chat')
        .trim();

    return ChatSession(
      id: ChatSession.newId(),
      characterId: characterId,
      title: title.isEmpty ? 'Imported chat' : title,
      updatedAt: DateTime.tryParse(sessionMap['updatedAt'] as String? ?? '') ??
          DateTime.now(),
      messages: messages,
      authorsNote: (sessionMap['authorsNote'] as String? ?? '').trim(),
      participantIds: () {
        final raw = sessionMap['participantIds'];
        if (raw is! List) return const <String>[];
        return raw
            .map((e) => '$e'.trim())
            .where((s) => s.isNotEmpty)
            .toList();
      }(),
    );
  }

  /// Best-effort plain-text import: lines like `Name: message`.
  ChatSession parsePlainText(
    String raw, {
    required String characterId,
    required String characterName,
    String userName = 'User',
    String? preferredTitle,
  }) {
    final lines = raw.split(RegExp(r'\r?\n'));
    final messages = <ChatMessage>[];
    final charLower = characterName.trim().toLowerCase();
    final userLower = userName.trim().toLowerCase();

    final speakerLine = RegExp(r'^([^:]{1,40}):\s*(.*)$');
    String? pendingRole;
    final pending = StringBuffer();

    void flush() {
      final text = pending.toString().trim();
      if (text.isEmpty || pendingRole == null) {
        pending.clear();
        pendingRole = null;
        return;
      }
      messages.add(
        ChatMessage(
          id: ChatMessage.newId(),
          role: pendingRole == 'user' ? ChatRole.user : ChatRole.assistant,
          text: text,
        ),
      );
      pending.clear();
      pendingRole = null;
    }

    for (final line in lines) {
      final trimmed = line.trimRight();
      if (trimmed.startsWith('#')) continue;
      final match = speakerLine.firstMatch(trimmed);
      if (match != null) {
        final speaker = match.group(1)!.trim().toLowerCase();
        final rest = match.group(2) ?? '';
        final isUser = speaker == userLower ||
            speaker == 'user' ||
            speaker == 'you' ||
            speaker == '{{user}}';
        final isChar = speaker == charLower ||
            speaker == 'assistant' ||
            speaker == 'char' ||
            speaker == '{{char}}' ||
            speaker == characterName.trim().toLowerCase();

        if (isUser || isChar) {
          flush();
          pendingRole = isUser ? 'user' : 'assistant';
          pending.write(rest);
          continue;
        }
      }

      if (pendingRole != null) {
        if (pending.isNotEmpty) pending.writeln();
        pending.write(trimmed);
      }
    }
    flush();

    if (messages.isEmpty) {
      throw const FormatException(
        'Could not find chat lines. Use “Name: message” format, or Anima JSON.',
      );
    }

    return ChatSession(
      id: ChatSession.newId(),
      characterId: characterId,
      title: (preferredTitle ?? 'Imported chat').trim().isEmpty
          ? 'Imported chat'
          : (preferredTitle ?? 'Imported chat').trim(),
      updatedAt: DateTime.now(),
      messages: messages,
    );
  }

  /// Auto-detect JSON vs plain text.
  ChatSession parseBytes(
    List<int> bytes, {
    required String characterId,
    required String characterName,
    String userName = 'User',
  }) {
    final text = utf8.decode(bytes).trim();
    if (text.startsWith('{')) {
      return parseJsonString(text, characterId: characterId);
    }
    return parsePlainText(
      text,
      characterId: characterId,
      characterName: characterName,
      userName: userName,
    );
  }
}
