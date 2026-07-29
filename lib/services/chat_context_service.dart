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

  /// Summarize calls need enough room for a careful memory rewrite.
  static SamplingSettings summarizeSampling(SamplingSettings base) {
    const minTokens = 2048;
    final user = base.maxTokens;
    final effective = user == null || user < minTokens ? minTokens : user;
    return base.copyWith(
      maxTokens: effective.clamp(512, 8192),
      temperature: base.temperature.clamp(0.1, 1.0) <= 0.5
          ? base.temperature
          : 0.35,
    );
  }

  List<Map<String, String>> buildSummarizeMessages({
    required List<ChatMessage> chunk,
    required String existingSummary,
    required String userName,
    required String charName,
    String openingScene = '',
    bool seedOpeningScene = false,
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

    final system =
        '''
You maintain an accurate story memory for a private roleplay chat app (Anima).
Your job is to UPDATE the running memory so older turns can leave the live prompt.

Critical rules:
- Treat the existing memory as a living document — revise or remove facts that the
  new chat segment contradicts or supersedes. Prefer the NEWEST information.
- Track: who is present, relationships, locations, goals, secrets revealed,
  promises, injuries, inventory, and open plot threads.
- When something changes (alliance, location, mood, a character's goal), update
  the summary to reflect the change; do not keep stale facts alongside new ones.
- Keep important emotional tone and character voice notes when they matter later.
- Use clear prose or labeled short bullets. Be specific (names, places, facts).
- Do not sanitize, moralize, or omit uncomfortable story facts.
- Output ONLY the updated memory summary — no preamble, no markdown fences.
'''
            .trim();

    final user = StringBuffer();
    if (existingSummary.trim().isNotEmpty) {
      user.writeln('Existing memory summary (revise — do not blindly append):');
      user.writeln(existingSummary.trim());
      user.writeln();
    } else {
      user.writeln('No existing memory summary yet.');
      user.writeln();
    }
    if (seedOpeningScene && openingScene.trim().isNotEmpty) {
      user.writeln(
        'Story opening (narrator setup at chat start — fold into memory as '
        'established background; update later if the story contradicts it):',
      );
      user.writeln(openingScene.trim());
      user.writeln();
    }
    user.writeln('New chat segment to fold in:');
    user.writeln(transcript.toString().trim());
    user.writeln();
    user.writeln(
      'Write the full updated memory summary now. Merge the opening (if any) '
      'and new segment into one coherent memory; correct any outdated facts.',
    );

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

  /// Estimate for Creation Center: trimmed chat + world summary + lore + overhead.
  ContextEstimate estimateWorkshop({
    required List<ChatMessage> messages,
    String linkedLorebookJson = '',
    String importedSourceText = '',
    String worldSummary = '',
    int worldSummaryCoveredCount = 0,
    int historyTokenBudget = ContextSettings.defaultHistoryTokens,
    int? modelContextLength,
    int systemOverheadTokens = 450,
  }) {
    final full = estimateConversationTokens(messages);
    final summaryTokens = estimateTokens(worldSummary);
    final history = selectHistory(
      messages: messages,
      endExclusive: messages.length,
      memoryCoveredCount: worldSummaryCoveredCount,
      historyTokenBudget: historyTokenBudget,
    );
    final historyTokens = estimateConversationTokens(history);
    final loreTokens = estimateTokens(linkedLorebookJson);
    final importedTokens = estimateTokens(importedSourceText);
    final estimatedSent = historyTokens +
        summaryTokens +
        loreTokens +
        importedTokens +
        systemOverheadTokens.clamp(0, 5000);
    final trimmedAway = (messages.length - history.length).clamp(0, messages.length);
    final notes = <String>[
      if (trimmedAway > 0 || worldSummaryCoveredCount > 0)
        'Older workshop lines stay on device; only ~${historyTokenBudget} tokens of '
            'recent chat are sent (plus world summary).'
      else
        'Sends recent workshop chat within your history budget (plus world summary).',
    ];
    if (importedTokens > 0) {
      notes.add(
        'Imported chat source: ~${ContextEstimate.formatTokenCount(importedTokens)} tokens.',
      );
    }
    if (loreTokens > 0) {
      notes.add('Includes the linked lorebook.');
    }
    if (summaryTokens > 0) {
      notes.add('World summary is injected instead of folded messages.');
    }
    return ContextEstimate(
      messageCount: messages.where((m) => m.text.trim().isNotEmpty).length,
      fullTranscriptTokens: full,
      estimatedSentTokens: estimatedSent,
      memoryTokens: summaryTokens + importedTokens,
      loreTokens: loreTokens,
      historyBudgetTokens: historyTokenBudget,
      modelContextLength: modelContextLength,
      messagesInPrompt: history.length,
      messagesTrimmedAway: trimmedAway,
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