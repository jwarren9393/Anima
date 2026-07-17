/// One bubble in the chat: either from you or from the AI.
///
/// Assistant messages can store several “swipes” (alternate generations),
/// like SillyTavern. [text] is whatever swipe is currently showing.
class ChatMessage {
  ChatMessage({
    required this.id,
    required this.role,
    required this.text,
    List<String>? swipes,
    this.swipeIndex = 0,
    this.speakerId,
    this.speakerName,
  }) : swipes = List<String>.unmodifiable(
          _normalizeSwipes(text: text, swipes: swipes, swipeIndex: swipeIndex),
        );

  /// Stable id for edit/delete/swipe on this device.
  final String id;

  /// Either [ChatRole.user] (you) or [ChatRole.assistant] (the AI).
  final ChatRole role;

  /// The text currently shown (matches [swipes] at [swipeIndex] for assistants).
  final String text;

  /// Alternate AI generations for this bubble (user messages usually have one).
  final List<String> swipes;

  /// Which swipe is visible right now.
  final int swipeIndex;

  /// Group chats: which character said this (assistant bubbles).
  final String? speakerId;
  final String? speakerName;

  bool get isUser => role == ChatRole.user;

  bool get canSwipe => !isUser && swipes.length > 1;

  ChatMessage copyWith({
    String? id,
    ChatRole? role,
    String? text,
    List<String>? swipes,
    int? swipeIndex,
    String? speakerId,
    String? speakerName,
    bool clearSpeaker = false,
  }) {
    final nextText = text ?? this.text;
    final nextSwipes = swipes ?? this.swipes;
    final nextIndex = swipeIndex ?? this.swipeIndex;
    return ChatMessage(
      id: id ?? this.id,
      role: role ?? this.role,
      text: nextText,
      swipes: nextSwipes,
      swipeIndex: nextIndex.clamp(0, (nextSwipes.length - 1).clamp(0, 9999)),
      speakerId: clearSpeaker ? null : (speakerId ?? this.speakerId),
      speakerName: clearSpeaker ? null : (speakerName ?? this.speakerName),
    );
  }

  /// Replace the visible swipe text (used when you edit a message).
  ChatMessage withEditedText(String newText) {
    final trimmed = newText.trim();
    if (isUser || swipes.isEmpty) {
      return copyWith(text: trimmed, swipes: [trimmed], swipeIndex: 0);
    }
    final updated = List<String>.from(swipes);
    final index = swipeIndex.clamp(0, updated.length - 1);
    updated[index] = trimmed;
    return ChatMessage(
      id: id,
      role: role,
      text: trimmed,
      swipes: updated,
      swipeIndex: index,
      speakerId: speakerId,
      speakerName: speakerName,
    );
  }

  /// Add a new AI generation as another swipe and show it.
  ChatMessage withNewSwipe(String newText) {
    final trimmed = newText.trim();
    final updated = [...swipes, trimmed];
    return ChatMessage(
      id: id,
      role: role,
      text: trimmed,
      swipes: updated,
      swipeIndex: updated.length - 1,
      speakerId: speakerId,
      speakerName: speakerName,
    );
  }

  ChatMessage withSwipeIndex(int index) {
    if (swipes.isEmpty) return this;
    final clamped = index.clamp(0, swipes.length - 1);
    return ChatMessage(
      id: id,
      role: role,
      text: swipes[clamped],
      swipes: swipes,
      swipeIndex: clamped,
      speakerId: speakerId,
      speakerName: speakerName,
    );
  }

  Map<String, String> toApiMap() => {
        'role': role == ChatRole.user ? 'user' : 'assistant',
        'content': text,
      };

  Map<String, dynamic> toJson() => {
        'id': id,
        'role': role == ChatRole.user ? 'user' : 'assistant',
        'text': text,
        'swipes': swipes,
        'swipeIndex': swipeIndex,
        if (speakerId != null && speakerId!.isNotEmpty) 'speakerId': speakerId,
        if (speakerName != null && speakerName!.isNotEmpty)
          'speakerName': speakerName,
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final roleRaw = json['role'] as String? ?? 'assistant';
    final text = (json['text'] as String? ?? '').trim();
    final swipesRaw = json['swipes'];
    final swipes = swipesRaw is List
        ? swipesRaw.map((e) => '$e').where((s) => s.trim().isNotEmpty).toList()
        : <String>[];
    return ChatMessage(
      id: json['id'] as String? ?? 'msg_${DateTime.now().millisecondsSinceEpoch}',
      role: roleRaw == 'user' ? ChatRole.user : ChatRole.assistant,
      text: text,
      swipes: swipes.isEmpty && text.isNotEmpty ? [text] : swipes,
      swipeIndex: json['swipeIndex'] as int? ?? 0,
      speakerId: (json['speakerId'] as String?)?.trim(),
      speakerName: (json['speakerName'] as String?)?.trim(),
    );
  }

  static String newId() => 'msg_${DateTime.now().microsecondsSinceEpoch}';

  static List<String> _normalizeSwipes({
    required String text,
    required List<String>? swipes,
    required int swipeIndex,
  }) {
    if (swipes == null || swipes.isEmpty) {
      return [text];
    }
    final cleaned = List<String>.from(swipes);
    final index = swipeIndex.clamp(0, cleaned.length - 1);
    if (index >= 0 && index < cleaned.length) {
      cleaned[index] = text;
    }
    return cleaned;
  }
}

enum ChatRole { user, assistant }
