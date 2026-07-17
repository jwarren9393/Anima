/// One bubble in the chat: either from you or from the AI.
class ChatMessage {
  const ChatMessage({
    required this.role,
    required this.text,
  });

  /// Either [ChatRole.user] (you) or [ChatRole.assistant] (the AI).
  final ChatRole role;

  /// The message text shown on screen.
  final String text;

  bool get isUser => role == ChatRole.user;

  /// Format used when talking to the NanoGPT API.
  Map<String, String> toApiMap() => {
        'role': role == ChatRole.user ? 'user' : 'assistant',
        'content': text,
      };
}

enum ChatRole { user, assistant }
