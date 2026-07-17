import '../models/character.dart';
import '../models/chat_message.dart';
import '../models/lorebook.dart';

/// Result of scanning chat history against a lorebook.
class LorebookInjection {
  const LorebookInjection({
    this.beforeChar = '',
    this.afterChar = '',
    this.matchedCount = 0,
  });

  /// Lore placed before the character description block.
  final String beforeChar;

  /// Lore placed after the character description block.
  final String afterChar;

  final int matchedCount;

  bool get isEmpty => beforeChar.isEmpty && afterChar.isEmpty;
}

/// Keyword-triggered World Info for Anima (SillyTavern-inspired, mobile-simple).
///
/// How it works in plain English:
/// 1. Look at the last few chat messages (scan depth).
/// 2. Find lore entries whose keywords appear (or that are marked “always on”).
/// 3. Keep only enough entries to stay under a small token budget.
/// 4. Hand the text back so [PromptBuilder] can splice it into the system prompt.
///
/// Global lorebooks and the speaking character's embedded book are merged.
class LorebookService {
  const LorebookService();

  /// Parse the embedded book on a character card (imported or edited).
  Lorebook? bookFor(Character character) {
    final raw = character.characterBook;
    if (raw == null || raw.isEmpty) return null;
    try {
      final book = Lorebook.fromJson(raw);
      if (book.entries.isEmpty) return null;
      return book;
    } catch (_) {
      return null;
    }
  }

  /// Scan [messages] and pick lore to inject for this turn.
  ///
  /// Pass [extraBooks] for enabled global / chat-selected World Info books.
  /// When regenerating, pass messages that exclude an empty assistant
  /// placeholder so keywords are only taken from real chat text.
  LorebookInjection buildInjection({
    required Character character,
    required List<ChatMessage> messages,
    List<Lorebook> extraBooks = const [],
    int? scanDepthOverride,
    int? tokenBudgetOverride,
  }) {
    final books = <Lorebook>[
      ...extraBooks,
      ?bookFor(character),
    ];
    if (books.isEmpty) return const LorebookInjection();

    final firstBook = books.first;
    final resolvedDepth =
        (scanDepthOverride ?? firstBook.scanDepth).clamp(1, 50);
    final resolvedBudget =
        (tokenBudgetOverride ?? firstBook.tokenBudget).clamp(10, 4000);

    final haystack = _scanText(messages, resolvedDepth);

    final triggered = <LorebookEntry>[];
    for (final book in books) {
      for (final entry in book.entries) {
        if (!entry.enabled) continue;
        if (entry.content.trim().isEmpty) continue;
        if (_entryMatches(entry, haystack)) {
          triggered.add(entry);
        }
      }
    }

    if (triggered.isEmpty) return const LorebookInjection();

    // insertion_order: lower → earlier in the prompt.
    triggered.sort((a, b) {
      final byOrder = a.insertionOrder.compareTo(b.insertionOrder);
      if (byOrder != 0) return byOrder;
      return (a.id ?? 0).compareTo(b.id ?? 0);
    });

    final kept = _applyBudget(triggered, resolvedBudget);
    final before = <String>[];
    final after = <String>[];
    for (final entry in kept) {
      final text = entry.content.trim();
      if (entry.position == LorebookPosition.afterChar) {
        after.add(text);
      } else {
        before.add(text);
      }
    }

    return LorebookInjection(
      beforeChar: before.join('\n\n'),
      afterChar: after.join('\n\n'),
      matchedCount: kept.length,
    );
  }

  /// Rough token estimate (good enough for a phone budget, not exact).
  int estimateTokens(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return 0;
    return (trimmed.length / 4).ceil().clamp(1, 100000);
  }

  String _scanText(List<ChatMessage> messages, int depth) {
    if (messages.isEmpty) return '';
    final start = (messages.length - depth).clamp(0, messages.length);
    final buffer = StringBuffer();
    for (var i = start; i < messages.length; i++) {
      final text = messages[i].text.trim();
      if (text.isEmpty) continue;
      if (buffer.isNotEmpty) buffer.writeln();
      buffer.write(text);
    }
    return buffer.toString();
  }

  bool _entryMatches(LorebookEntry entry, String haystack) {
    if (entry.constant) return true;
    if (haystack.isEmpty) return false;
    if (entry.keys.isEmpty) return false;

    final primaryHit = _anyKeyIn(entry.keys, haystack, entry.caseSensitive);
    if (!primaryHit) return false;

    if (!entry.selective) return true;
    if (entry.secondaryKeys.isEmpty) return true;
    return _anyKeyIn(entry.secondaryKeys, haystack, entry.caseSensitive);
  }

  bool _anyKeyIn(List<String> keys, String haystack, bool caseSensitive) {
    final hay = caseSensitive ? haystack : haystack.toLowerCase();
    for (final raw in keys) {
      final key = raw.trim();
      if (key.isEmpty) continue;
      final needle = caseSensitive ? key : key.toLowerCase();
      if (hay.contains(needle)) return true;
    }
    return false;
  }

  /// Keep entries until the budget is full; drop lowest [priority] first if needed.
  List<LorebookEntry> _applyBudget(List<LorebookEntry> ordered, int budget) {
    var used = 0;
    final kept = <LorebookEntry>[];

    for (final entry in ordered) {
      final cost = estimateTokens(entry.content);
      if (used + cost <= budget) {
        kept.add(entry);
        used += cost;
        continue;
      }

      // Over budget: try dropping a lower-priority kept entry to make room.
      if (kept.isEmpty) {
        // First entry alone is huge — still include a trimmed slice? Skip.
        continue;
      }

      final droppable = List<LorebookEntry>.from(kept)
        ..sort((a, b) {
          final byPriority = a.priority.compareTo(b.priority);
          if (byPriority != 0) return byPriority;
          return b.insertionOrder.compareTo(a.insertionOrder);
        });

      var freed = false;
      for (final victim in droppable) {
        if (victim.priority >= entry.priority) continue;
        final victimCost = estimateTokens(victim.content);
        if (used - victimCost + cost <= budget) {
          kept.remove(victim);
          used -= victimCost;
          kept.add(entry);
          used += cost;
          freed = true;
          break;
        }
      }
      if (!freed) {
        // Cannot fit — stop adding further (later insertion_order is less critical).
        break;
      }
    }

    // Re-sort by insertion_order after possible swaps.
    kept.sort((a, b) => a.insertionOrder.compareTo(b.insertionOrder));
    return kept;
  }
}
