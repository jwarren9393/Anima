import '../models/chat_message.dart';
import 'settings_service.dart';

/// Picks which chat bubbles to send and builds memory-summary prompts.
class ChatContextService {
  const ChatContextService();

  /// Rough token estimate — same rule as World Info (1 token ≈ 4 characters).
  int estimateTokens(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return 0;
    return (trimmed.length / 4).ceil();
  }

  int estimateMessageTokens(ChatMessage message, {bool isGroup = false}) {
    var text = message.text.trim();
    if (text.isEmpty) return 0;
    if (isGroup &&
        !message.isUser &&
        message.speakerName != null &&
        message.speakerName!.trim().isNotEmpty) {
      text = '${message.speakerName}: $text';
    }
    // Small overhead for role framing in the API payload.
    return estimateTokens(text) + 4;
  }

  /// Recent history for the API: prefer messages not yet folded into memory,
  /// packed newest-first until [historyTokenBudget] is filled.
  List<ChatMessage> selectHistory({
    required List<ChatMessage> messages,
    required int endExclusive,
    required int memoryCoveredCount,
    required int historyTokenBudget,
    bool isGroup = false,
  }) {
    final end = endExclusive.clamp(0, messages.length);
    final covered = memoryCoveredCount.clamp(0, end);
    final candidates = <ChatMessage>[];
    for (var i = 0; i < end; i++) {
      final message = messages[i];
      if (message.text.trim().isEmpty) continue;
      if (i < covered) continue;
      candidates.add(message);
    }

    // If everything was covered (or empty), fall back to the newest raw lines.
    if (candidates.isEmpty) {
      for (var i = 0; i < end; i++) {
        final message = messages[i];
        if (message.text.trim().isEmpty) continue;
        candidates.add(message);
      }
    }

    final budget = historyTokenBudget.clamp(64, 100000);
    final picked = <ChatMessage>[];
    var used = 0;
    for (var i = candidates.length - 1; i >= 0; i--) {
      final message = candidates[i];
      final cost = estimateMessageTokens(message, isGroup: isGroup);
      if (picked.isNotEmpty && used + cost > budget) break;
      picked.insert(0, message);
      used += cost;
      // Always keep at least the newest message even if it alone exceeds budget.
      if (picked.length == 1 && cost > budget) break;
    }
    return picked;
  }

  /// True when enough new messages exist to run auto-summarize.
  bool shouldAutoSummarize({
    required int messageCount,
    required int memoryCoveredCount,
    required ContextSettings context,
  }) {
    if (!context.autoSummarize) return false;
    final uncovered = messageCount - memoryCoveredCount.clamp(0, messageCount);
    return uncovered >= context.summarizeEveryMessages;
  }

  /// Index up to which messages should be folded into memory (exclusive end).
  /// Newest [summarizeKeepRecent] stay as raw chat.
  int summarizeCutIndex({
    required int messageCount,
    required int memoryCoveredCount,
    required int summarizeKeepRecent,
  }) {
    final keep = summarizeKeepRecent.clamp(1, 80);
    final cut = messageCount - keep;
    if (cut <= memoryCoveredCount) return memoryCoveredCount;
    return cut;
  }

  List<Map<String, String>> buildSummarizeMessages({
    required List<ChatMessage> chunk,
    required String existingSummary,
    required String userName,
    required String charName,
  }) {
    final transcript = StringBuffer();
    for (final message in chunk) {
      final text = message.text.trim();
      if (text.isEmpty) continue;
      final who = message.isUser
          ? userName
          : (message.speakerName?.trim().isNotEmpty == true
              ? message.speakerName!.trim()
              : charName);
      transcript.writeln('$who: $text');
      transcript.writeln();
    }

    final system = '''
You maintain a compact story memory for a private roleplay chat app (Anima).
Update the running summary so older turns can be dropped from the live prompt.
Keep important facts, relationships, open plot threads, and tone.
Write in plain prose (or short bullets). Do not sanitize or moralize.
Output ONLY the updated summary — no preamble.
'''.trim();

    final user = StringBuffer();
    if (existingSummary.trim().isNotEmpty) {
      user.writeln('Existing memory summary:');
      user.writeln(existingSummary.trim());
      user.writeln();
    } else {
      user.writeln('No existing memory summary yet.');
      user.writeln();
    }
    user.writeln('New chat segment to fold in:');
    user.writeln(transcript.toString().trim());
    user.writeln();
    user.writeln('Write the updated memory summary now.');

    return [
      {'role': 'system', 'content': system},
      {'role': 'user', 'content': user.toString().trim()},
    ];
  }
}
