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

  /// Rough size of a full message list (saved transcript on device).
  int estimateConversationTokens(
    List<ChatMessage> messages, {
    bool isGroup = false,
  }) {
    var total = 0;
    for (final message in messages) {
      total += estimateMessageTokens(message, isGroup: isGroup);
    }
    return total;
  }

  /// Estimate for Creation Center: chat + optional linked lorebook + prompt overhead.
  ContextEstimate estimateWorkshop({
    required List<ChatMessage> messages,
    String linkedLorebookJson = '',
    String importedSourceText = '',
    int? modelContextLength,
    int systemOverheadTokens = 450,
  }) {
    final chatTokens = estimateConversationTokens(messages);
    final loreTokens = estimateTokens(linkedLorebookJson);
    final importedTokens = estimateTokens(importedSourceText);
    final estimatedSent = chatTokens +
        loreTokens +
        importedTokens +
        systemOverheadTokens.clamp(0, 5000);
    final notes = <String>[
      'Includes a small system-prompt cushion. Creation Center sends the full chat.',
    ];
    if (importedTokens > 0) {
      notes.add(
        'Imported chat source: ~${ContextEstimate.formatTokenCount(importedTokens)} tokens.',
      );
    }
    if (loreTokens > 0) {
      notes.add('Includes the linked lorebook.');
    }
    return ContextEstimate(
      messageCount: messages.where((m) => m.text.trim().isNotEmpty).length,
      fullTranscriptTokens: chatTokens,
      estimatedSentTokens: estimatedSent,
      memoryTokens: importedTokens,
      loreTokens: loreTokens,
      historyBudgetTokens: null,
      modelContextLength: modelContextLength,
      notes: notes.join(' '),
    );
  }

  /// Estimate for a normal roleplay chat (full vs trimmed-to-budget send size).
  ContextEstimate estimateChat({
    required List<ChatMessage> messages,
    required int memoryCoveredCount,
    required int historyTokenBudget,
    String memorySummary = '',
    String systemPrompt = '',
    String postHistory = '',
    bool isGroup = false,
    int? modelContextLength,
  }) {
    final full = estimateConversationTokens(messages, isGroup: isGroup);
    final history = selectHistory(
      messages: messages,
      endExclusive: messages.length,
      memoryCoveredCount: memoryCoveredCount,
      historyTokenBudget: historyTokenBudget,
      isGroup: isGroup,
    );
    final historyTokens =
        estimateConversationTokens(history, isGroup: isGroup);
    final memoryTokens = estimateTokens(memorySummary);
    final extras = estimateTokens(systemPrompt) +
        estimateTokens(postHistory) +
        memoryTokens;
    final estimatedSent = historyTokens + extras;
    final trimmedAway = (messages.length - history.length).clamp(0, messages.length);

    return ContextEstimate(
      messageCount: messages.where((m) => m.text.trim().isNotEmpty).length,
      fullTranscriptTokens: full,
      estimatedSentTokens: estimatedSent,
      memoryTokens: memoryTokens,
      loreTokens: 0,
      historyBudgetTokens: historyTokenBudget,
      modelContextLength: modelContextLength,
      messagesInPrompt: history.length,
      messagesTrimmedAway: trimmedAway,
      notes: trimmedAway > 0
          ? 'Anima will only send the newest ~$historyTokenBudget tokens of '
              'history (plus memory/system). Older raw lines stay on device.'
          : 'Anima can currently send this whole chat within your history budget.',
    );
  }
}

/// Rough prompt/context size snapshot for UI (menu / Creation Center banner).
class ContextEstimate {
  const ContextEstimate({
    required this.messageCount,
    required this.fullTranscriptTokens,
    required this.estimatedSentTokens,
    required this.memoryTokens,
    required this.loreTokens,
    required this.historyBudgetTokens,
    required this.modelContextLength,
    this.messagesInPrompt,
    this.messagesTrimmedAway = 0,
    this.notes = '',
  });

  final int messageCount;
  final int fullTranscriptTokens;
  final int estimatedSentTokens;
  final int memoryTokens;
  final int loreTokens;
  final int? historyBudgetTokens;
  final int? modelContextLength;
  final int? messagesInPrompt;
  final int messagesTrimmedAway;
  final String notes;

  /// 0–1 when model context is known; null otherwise.
  double? get fillRatio {
    final max = modelContextLength;
    if (max == null || max <= 0) return null;
    return (estimatedSentTokens / max).clamp(0.0, 2.0);
  }

  String get compactBannerLine {
    final bits = <String>[
      '$messageCount msg${messageCount == 1 ? '' : 's'}',
      '~${formatTokenCount(estimatedSentTokens)} tokens',
    ];
    final max = modelContextLength;
    if (max != null && max > 0) {
      final pct = ((estimatedSentTokens / max) * 100).clamp(0, 999).round();
      bits.add('$pct% of ${formatTokenCount(max)} ctx');
    }
    return bits.join(' · ');
  }

  /// Formats a token count for UI: `850`, `1.2K`, `16K`, `128K`.
  static String formatTokenCount(int tokens) {
    final n = tokens < 0 ? 0 : tokens;
    if (n < 1000) return '$n';
    if (n < 10000) {
      final k = n / 1000;
      final text = k == k.roundToDouble()
          ? '${k.round()}'
          : k.toStringAsFixed(1);
      return '${text}K';
    }
    if (n < 1000000) return '${(n / 1000).round()}K';
    final m = n / 1000000;
    final text = m == m.roundToDouble()
        ? '${m.round()}'
        : m.toStringAsFixed(1);
    return '${text}M';
  }
}