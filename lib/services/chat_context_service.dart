import '../models/chat_message.dart';
import '../models/memory_summary.dart';
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
  static const memorySummarizeSystemPrompt = '''
You maintain the MEMORY INDEX for a private roleplay chat app (Anima).
This text is injected into live character prompts as a FACT INDEX only — not as
writing samples. Your output must NEVER influence how characters speak.

TASK: MERGE the new chat segment into the running memory. Do not rewrite the
whole index from scratch. Older durable facts must survive.

OUTPUT FORMAT (mandatory — two sections, then bullets):

## Scene
- Location: …
- Present: …
(optional Time: …)

## Ledger
- [pin] Promise: …     (copy every [pin] line verbatim)
- Thread: …
- Promise: …
- Secret (known by Mira): …
- Event (witnesses: Mira, Jay): …
- Relationship: …
- Item: …
- Goal: …
- Injury: …

Labels: Location, Present, Time, Relationship, Event, Secret, Item, Goal,
Thread, Injury, Promise, Change.

Witness tags for private facts (use character names, never "User"):
- Secret (known by Mira, Aedric): …
- Event (witnesses: Mira, King Aethlor): …
- Or (Mira only): … when literally one person knows
NEVER write scene-specific Event/Secret/Relationship bullets without a witness tag.
If only some cast were present, name ONLY those witnesses — never the whole group.
Public world facts (Location, Present, Time, Item, Faction, World, Rule, Lore,
Setting) need no witness tag.

Clinical, objective, telegraphic facts. Past tense for completed events.
NO metaphors, poetry, atmosphere, sensory prose, dialogue quotes, or RP voice.
NO narrative paragraphs. NO reenacting scenes. NO character speech patterns.
Example: "Event (witnesses: Jay, Edric): They entered the tower" — not
"*they slipped into the tower like shadows*".

SCENE RULES (replace each run):
- Scene is ONLY the current physical situation (where / who is there / time).
- Newest Location/Present/Time wins. Do not keep old rooms beside the current one.
- If the new segment does not mention a new location or who is present, keep the
  previous Scene Location/Present.

LEDGER RULES (merge — newest does NOT win):
- Ledger is the durable fact index. KEEP existing ledger bullets unless:
  (a) the new chat CONTRADICTS that fact — then replace it with the updated fact, or
  (b) that Thread/Goal/Promise is explicitly RESOLVED or closed in the new chat, or
  (c) it is an exact duplicate of another ledger bullet.
- NEVER drop a line that starts with "- [pin]". Copy those lines verbatim.
- NEVER drop a Thread: unless the new chat clearly resolves that thread.
- Do not delete old promises, secrets, injuries, relationships, inventory, or
  open plots just because the scene moved on.
- Do not sanitize, moralize, or omit uncomfortable facts.
- Merge wording of true duplicates. Prefer more bullets over losing plot.

LENGTH:
- Scene: at most 10 bullets.
- Ledger: keep durable facts. Do not shrink the ledger just to look tidy.
- Always finish the last bullet — never truncate mid-line.
- Output ONLY the two sections and bullets — no preamble, fences, or commentary.
''';

  /// Default output budget when chat max_tokens is unset or very low.
  static const summarizeDefaultMaxTokens = 2048;

  /// Floor so short user max_tokens settings do not truncate memory rewrites.
  static const summarizeMinTokens = 1024;

  /// Cap so long-chat ledgers can finish without mid-line cutoffs.
  static const summarizeMaxCap = 4096;

  static SamplingSettings summarizeSampling(SamplingSettings base) {
    final user = base.maxTokens;
    final effective = user == null || user < summarizeMinTokens
        ? summarizeDefaultMaxTokens
        : user;
    return base.copyWith(
      maxTokens: effective.clamp(summarizeMinTokens, summarizeMaxCap),
      temperature: base.temperature <= 0.3 ? base.temperature : 0.25,
    );
  }

  List<Map<String, String>> buildSummarizeMessages({
    required List<ChatMessage> chunk,
    required String existingSummary,
    required String userName,
    required String charName,
    int coveredMessageCount = 0,
  }) {
    final transcript = StringBuffer();
    for (final message in chunk) {
      if (message.isGroupBeat && message.beatLines != null) {
        for (final line in message.beatLines!) {
          final who = line.speakerName.trim().isNotEmpty
              ? line.speakerName.trim()
              : charName;
          final lineText = line.text.trim();
          if (lineText.isEmpty) continue;
          transcript.writeln('$who: $lineText');
        }
        transcript.writeln();
        continue;
      }
      final text = message.text.trim();
      if (text.isEmpty) continue;
      if (message.isNarrator) {
        transcript.writeln('Narrator: $text');
      } else if (message.isDirector) {
        transcript.writeln('Director: $text');
      } else {
        final who = message.isUser
            ? userName
            : (message.speakerName?.trim().isNotEmpty == true
                  ? message.speakerName!.trim()
                  : charName);
        transcript.writeln('$who: $text');
      }
      transcript.writeln();
    }

    final parsed = MemorySummaryDocument.parse(existingSummary);
    final existingCanonical = parsed.encode();
    final ledgerTarget = MemorySummaryDocument.ledgerBulletTarget(
      coveredMessageCount,
    );
    final system = StringBuffer()
      ..writeln(memorySummarizeSystemPrompt.trim())
      ..writeln()
      ..writeln(
        'This chat has folded about $coveredMessageCount older messages. '
        'Ledger may use up to $ledgerTarget bullets. Scene stays at most '
        '${MemorySummaryDocument.sceneBulletMax}. Prefer keeping ledger facts '
        'over cutting them to hit a smaller number.',
      );

    final user = StringBuffer();
    if (existingSummary.trim().isNotEmpty) {
      user.writeln(
        'Existing memory (MERGE into this — do not rewrite from scratch):',
      );
      user.writeln(
        existingCanonical.isEmpty ? existingSummary.trim() : existingCanonical,
      );
      user.writeln();
      final pins = parsed.pinnedFacts;
      if (pins.isNotEmpty) {
        user.writeln(
          'PINNED FACTS (copy into ## Ledger verbatim; never drop or rewrite):',
        );
        for (final pin in pins) {
          user.writeln(pin.encodeLine());
        }
        user.writeln();
      }
    } else {
      user.writeln('No existing memory yet. Create ## Scene and ## Ledger.');
      user.writeln();
    }
    user.writeln('New chat segment to fold in (extract new facts, then merge):');
    user.writeln(transcript.toString().trim());
    user.writeln();
    user.writeln(
      'Write the full updated memory now with ## Scene and ## Ledger. '
      'Replace Scene if the location/cast changed; MERGE the Ledger; keep every '
      '[pin] line and every unresolved Thread.',
    );

    return [
      {'role': 'system', 'content': system.toString().trim()},
      {'role': 'user', 'content': user.toString().trim()},
    ];
  }

  /// Normalize a model rewrite and restore any dropped pins.
  static String finalizeSummarizeOutput({
    required String existingSummary,
    required String generated,
  }) {
    return MemorySummaryDocument.finalize(
      existing: existingSummary,
      generated: generated,
    );
  }

  /// Wraps stored memory for injection into live chat prompts.
  static String formatMemoryForPrompt(String memory) {
    final body = memory.trim();
    if (body.isEmpty) return '';
    return '''
Memory index (canonical facts from older story — reference only):
$body

Use only for continuity of facts, locations, relationships, and plot state.
Scene = current place/cast. Ledger = durable plot (do not forget older ledger facts).
Do NOT mimic this summary's tone, wording, or style in character replies.
Character voice comes from the character card and live chat only.
'''
        .trim();
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
    final estimatedSent =
        historyTokens +
        summaryTokens +
        loreTokens +
        importedTokens +
        systemOverheadTokens.clamp(0, 5000);
    final trimmedAway = (messages.length - history.length).clamp(
      0,
      messages.length,
    );
    final notes = <String>[
      if (trimmedAway > 0 || worldSummaryCoveredCount > 0)
        'Older workshop lines stay on device; only ~$historyTokenBudget tokens of '
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
    final historyTokens = estimateConversationTokens(history, isGroup: isGroup);
    final memoryTokens = estimateTokens(memorySummary);
    final extras =
        estimateTokens(systemPrompt) +
        estimateTokens(postHistory) +
        memoryTokens;
    final estimatedSent = historyTokens + extras;
    final trimmedAway = (messages.length - history.length).clamp(
      0,
      messages.length,
    );

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
    final text = m == m.roundToDouble() ? '${m.round()}' : m.toStringAsFixed(1);
    return '${text}M';
  }
}
