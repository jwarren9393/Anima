import 'chat_message.dart';

/// One saved conversation (solo or group) — SillyTavern-style chat thread.
class ChatSession {
  ChatSession({
    required this.id,
    required this.characterId,
    required this.title,
    required this.updatedAt,
    List<ChatMessage>? messages,
    this.authorsNote = '',
    List<String>? participantIds,
    this.nextSpeakerIndex = 0,
  })  : messages = List<ChatMessage>.from(messages ?? const []),
        participantIds = List<String>.from(participantIds ?? const []);

  final String id;

  /// Solo: the character id. Group: storage bucket id (see [ChatService.groupsKey]).
  final String characterId;

  final String title;
  final DateTime updatedAt;
  final List<ChatMessage> messages;

  /// Chat-level instructions (SillyTavern Author's Note) — injected each turn.
  final String authorsNote;

  /// Group members (character ids). Empty / single = solo chat with [characterId].
  final List<String> participantIds;

  /// Round-robin index into [participantIds] for who speaks next in a group.
  final int nextSpeakerIndex;

  bool get isGroup => participantIds.length > 1;

  /// Effective cast for prompting (falls back to [characterId] when solo).
  List<String> get effectiveParticipantIds {
    if (participantIds.isNotEmpty) return participantIds;
    if (characterId.isEmpty) return const [];
    return [characterId];
  }

  ChatSession copyWith({
    String? id,
    String? characterId,
    String? title,
    DateTime? updatedAt,
    List<ChatMessage>? messages,
    String? authorsNote,
    List<String>? participantIds,
    int? nextSpeakerIndex,
  }) {
    return ChatSession(
      id: id ?? this.id,
      characterId: characterId ?? this.characterId,
      title: title ?? this.title,
      updatedAt: updatedAt ?? this.updatedAt,
      messages: messages ?? this.messages,
      authorsNote: authorsNote ?? this.authorsNote,
      participantIds: participantIds ?? this.participantIds,
      nextSpeakerIndex: nextSpeakerIndex ?? this.nextSpeakerIndex,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'characterId': characterId,
        'title': title,
        'updatedAt': updatedAt.toIso8601String(),
        'messages': messages.map((m) => m.toJson()).toList(),
        'authorsNote': authorsNote,
        'participantIds': participantIds,
        'nextSpeakerIndex': nextSpeakerIndex,
      };

  factory ChatSession.fromJson(Map<String, dynamic> json) {
    final rawMessages = json['messages'];
    final messages = <ChatMessage>[];
    if (rawMessages is List) {
      for (final item in rawMessages) {
        if (item is Map) {
          messages.add(ChatMessage.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }

    final participants = <String>[];
    final rawParts = json['participantIds'];
    if (rawParts is List) {
      for (final item in rawParts) {
        final id = '$item'.trim();
        if (id.isNotEmpty) participants.add(id);
      }
    }

    return ChatSession(
      id: json['id'] as String? ?? '',
      characterId: json['characterId'] as String? ?? '',
      title: (json['title'] as String? ?? 'Chat').trim().isEmpty
          ? 'Chat'
          : (json['title'] as String).trim(),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
      messages: messages,
      authorsNote: (json['authorsNote'] as String? ?? '').trim(),
      participantIds: participants,
      nextSpeakerIndex: json['nextSpeakerIndex'] as int? ?? 0,
    );
  }

  static String newId() => 'chat_${DateTime.now().millisecondsSinceEpoch}';
}
