import 'chat_message.dart';

/// One Creation Center workshop: a plain AI chat that builds toward one lorebook.
class WorldWorkshop {
  const WorldWorkshop({
    required this.id,
    required this.title,
    required this.messages,
    required this.updatedAt,
    this.exportedLorebookId,
  });

  final String id;

  /// Shown in the workshop list (often the emerging world name).
  final String title;

  final List<ChatMessage> messages;
  final DateTime updatedAt;

  /// When set, this workshop already produced a global lorebook with this id.
  /// Creating again can update that same book.
  final String? exportedLorebookId;

  WorldWorkshop copyWith({
    String? id,
    String? title,
    List<ChatMessage>? messages,
    DateTime? updatedAt,
    String? exportedLorebookId,
    bool clearExportedLorebookId = false,
  }) {
    return WorldWorkshop(
      id: id ?? this.id,
      title: title ?? this.title,
      messages: messages ?? this.messages,
      updatedAt: updatedAt ?? this.updatedAt,
      exportedLorebookId: clearExportedLorebookId
          ? null
          : (exportedLorebookId ?? this.exportedLorebookId),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'messages': messages.map((m) => m.toJson()).toList(),
        'updatedAt': updatedAt.toIso8601String(),
        if (exportedLorebookId != null && exportedLorebookId!.isNotEmpty)
          'exportedLorebookId': exportedLorebookId,
      };

  factory WorldWorkshop.fromJson(Map<String, dynamic> json) {
    final rawMessages = json['messages'];
    final messages = <ChatMessage>[];
    if (rawMessages is List) {
      for (final item in rawMessages) {
        if (item is Map) {
          messages.add(
            ChatMessage.fromJson(Map<String, dynamic>.from(item)),
          );
        }
      }
    }

    final updatedRaw = json['updatedAt'] as String?;
    return WorldWorkshop(
      id: '${json['id'] ?? ''}'.trim().isEmpty
          ? newId()
          : '${json['id']}'.trim(),
      title: ('${json['title'] ?? ''}').trim().isEmpty
          ? 'New workshop'
          : ('${json['title']}').trim(),
      messages: messages,
      updatedAt: updatedRaw == null
          ? DateTime.now()
          : (DateTime.tryParse(updatedRaw) ?? DateTime.now()),
      exportedLorebookId:
          ('${json['exportedLorebookId'] ?? ''}').trim().isEmpty
              ? null
              : ('${json['exportedLorebookId']}').trim(),
    );
  }

  static String newId() => 'ws_${DateTime.now().millisecondsSinceEpoch}';

  static WorldWorkshop empty({String title = 'New workshop'}) {
    return WorldWorkshop(
      id: newId(),
      title: title,
      messages: const [],
      updatedAt: DateTime.now(),
    );
  }
}
