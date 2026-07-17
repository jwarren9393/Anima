import 'chat_message.dart';

/// One saved conversation with a character (SillyTavern-style chat thread).
class ChatSession {
  ChatSession({
    required this.id,
    required this.characterId,
    required this.title,
    required this.updatedAt,
    List<ChatMessage>? messages,
  }) : messages = List<ChatMessage>.from(messages ?? const []);

  final String id;
  final String characterId;
  final String title;
  final DateTime updatedAt;
  final List<ChatMessage> messages;

  ChatSession copyWith({
    String? id,
    String? characterId,
    String? title,
    DateTime? updatedAt,
    List<ChatMessage>? messages,
  }) {
    return ChatSession(
      id: id ?? this.id,
      characterId: characterId ?? this.characterId,
      title: title ?? this.title,
      updatedAt: updatedAt ?? this.updatedAt,
      messages: messages ?? this.messages,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'characterId': characterId,
        'title': title,
        'updatedAt': updatedAt.toIso8601String(),
        'messages': messages.map((m) => m.toJson()).toList(),
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
    return ChatSession(
      id: json['id'] as String? ?? '',
      characterId: json['characterId'] as String? ?? '',
      title: (json['title'] as String? ?? 'Chat').trim().isEmpty
          ? 'Chat'
          : (json['title'] as String).trim(),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
      messages: messages,
    );
  }

  static String newId() => 'chat_${DateTime.now().millisecondsSinceEpoch}';
}
