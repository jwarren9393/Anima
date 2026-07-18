import '../models/character.dart';
import '../models/chat_message.dart';
import '../models/lorebook.dart';

typedef LoreTriggerListener = void Function(List<String> labels);

/// Result of scanning chat history against a lorebook.
class LorebookInjection {
  const LorebookInjection({
    this.beforeChar = '',
    this.afterChar = '',
    this.matchedCount = 0,
    this.triggeredLabels = const [],
  });

  /// Lore placed before the character description block.
  final String beforeChar;

  /// Lore placed after the character description block.
  final String afterChar;

  final int matchedCount;

  /// Human-readable book / entry labels approved by the token budget.
  final List<String> triggeredLabels;

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
    bool? recursiveScanningOverride,
    LoreTriggerListener? onTriggered,
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
    final recursiveScanning = recursiveScanningOverride ??
        books.any((book) => book.recursiveScanning);

    final haystack = _scanText(messages, resolvedDepth);
    final candidates = <_LoreCandidate>[];
    var ordinal = 0;
    for (final book in books) {
      for (final entry in book.entries) {
        if (!entry.enabled) continue;
        if (entry.content.trim().isEmpty) continue;
        candidates.add(
          _LoreCandidate(book: book, entry: entry, ordinal: ordinal++),
        );
      }
    }

    final triggered = <_LoreMatch>[
      for (final candidate in candidates)
        if (_entryMatches(candidate.entry, haystack))
          _LoreMatch(candidate: candidate, depth: 0),
    ];
    if (triggered.isEmpty) return const LorebookInjection();

    var kept = _applyBudget(triggered, resolvedBudget);
    if (recursiveScanning && kept.isNotEmpty) {
      kept = _expandRecursively(
        candidates: candidates,
        directMatches: triggered,
        initiallyKept: kept,
        budget: resolvedBudget,
      );
    }

    final before = <String>[];
    final after = <String>[];
    for (final match in kept) {
      final entry = match.candidate.entry;
      final text = entry.content.trim();
      if (entry.position == LorebookPosition.afterChar) {
        after.add(text);
      } else {
        before.add(text);
      }
    }

    final labels = List<String>.unmodifiable(
      kept.map((match) => match.candidate.displayLabel),
    );
    if (labels.isNotEmpty) onTriggered?.call(labels);

    return LorebookInjection(
      beforeChar: before.join('\n\n'),
      afterChar: after.join('\n\n'),
      matchedCount: kept.length,
      triggeredLabels: labels,
    );
  }

  List<_LoreMatch> _expandRecursively({
    required List<_LoreCandidate> candidates,
    required List<_LoreMatch> directMatches,
    required List<_LoreMatch> initiallyKept,
    required int budget,
  }) {
    final discovered = <int, _LoreMatch>{
      for (final match in directMatches) match.candidate.ordinal: match,
    };
    final scanned = <int>{};
    var kept = initiallyKept;

    while (true) {
      final frontier = kept
          .where((match) => !scanned.contains(match.candidate.ordinal))
          .toList();
      if (frontier.isEmpty) break;

      var added = false;
      for (final source in frontier) {
        scanned.add(source.candidate.ordinal);
        final sourceText = source.candidate.entry.content;
        for (final candidate in candidates) {
          if (discovered.containsKey(candidate.ordinal)) continue;
          if (!_entryMatches(candidate.entry, sourceText)) continue;
          discovered[candidate.ordinal] = _LoreMatch(
            candidate: candidate,
            depth: source.depth + 1,
          );
          added = true;
        }
      }
      if (!added) continue;
      kept = _applyBudget(discovered.values.toList(), budget);
    }

    return kept;
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

  /// Keep the highest-priority entries that fit, then restore prompt order.
  ///
  /// Direct matches win ties over deeper recursive matches. Within an equal
  /// priority and depth, lower insertion order wins.
  List<_LoreMatch> _applyBudget(List<_LoreMatch> matches, int budget) {
    var used = 0;
    final kept = <_LoreMatch>[];
    final ranked = List<_LoreMatch>.from(matches)
      ..sort((a, b) {
        final byPriority =
            b.candidate.entry.priority.compareTo(a.candidate.entry.priority);
        if (byPriority != 0) return byPriority;
        final byDepth = a.depth.compareTo(b.depth);
        if (byDepth != 0) return byDepth;
        final byOrder = a.candidate.entry.insertionOrder
            .compareTo(b.candidate.entry.insertionOrder);
        if (byOrder != 0) return byOrder;
        return a.candidate.ordinal.compareTo(b.candidate.ordinal);
      });

    for (final match in ranked) {
      final entry = match.candidate.entry;
      final cost = estimateTokens(entry.content);
      if (used + cost <= budget) {
        kept.add(match);
        used += cost;
      }
    }

    kept.sort((a, b) {
      final byOrder = a.candidate.entry.insertionOrder
          .compareTo(b.candidate.entry.insertionOrder);
      if (byOrder != 0) return byOrder;
      return a.candidate.ordinal.compareTo(b.candidate.ordinal);
    });
    return kept;
  }
}

class _LoreCandidate {
  const _LoreCandidate({
    required this.book,
    required this.entry,
    required this.ordinal,
  });

  final Lorebook book;
  final LorebookEntry entry;
  final int ordinal;

  String get displayLabel {
    final bookName = book.name.trim();
    final entryName = entry.displayLabel;
    return bookName.isEmpty ? entryName : '$bookName — $entryName';
  }
}

class _LoreMatch {
  const _LoreMatch({required this.candidate, required this.depth});

  final _LoreCandidate candidate;
  final int depth;
}
