import '../models/lorebook.dart';
import 'chat_context_service.dart';

/// Token footprint of a lorebook or entry (≈ 1 token per 4 characters).
class LorebookTokenBreakdown {
  const LorebookTokenBreakdown({
    required this.enabledTokens,
    required this.totalTokens,
    required this.enabledCount,
    required this.totalCount,
  });

  final int enabledTokens;
  final int totalTokens;
  final int enabledCount;
  final int totalCount;
}

class LorebookTokenService {
  const LorebookTokenService([
    this._context = const ChatContextService(),
  ]);

  final ChatContextService _context;

  int estimateTokens(String text) => _context.estimateTokens(text);

  static String format(int tokens) => ContextEstimate.formatTokenCount(tokens);

  int entryTokens(LorebookEntry entry) {
    final content = entry.content.trim();
    if (content.isEmpty) return 0;
    return estimateTokens(content);
  }

  LorebookTokenBreakdown breakdown(Lorebook book) {
    var enabledTokens = 0;
    var totalTokens = 0;
    var enabledCount = 0;
    for (final entry in book.entries) {
      final tokens = entryTokens(entry);
      if (tokens <= 0) continue;
      totalTokens += tokens;
      if (entry.enabled) {
        enabledTokens += tokens;
        enabledCount++;
      }
    }
    return LorebookTokenBreakdown(
      enabledTokens: enabledTokens,
      totalTokens: totalTokens,
      enabledCount: enabledCount,
      totalCount: book.entries.length,
    );
  }

  /// Tokens from enabled entry content (what can inject into prompts).
  int badgeTokens(Lorebook book) => breakdown(book).enabledTokens;
}

String lorebookTokenTooltip(LorebookTokenBreakdown breakdown) {
  return 'Enabled content ~${LorebookTokenService.format(breakdown.enabledTokens)}'
      ' (${breakdown.enabledCount} entries)'
      '${breakdown.totalTokens > breakdown.enabledTokens ? ' · All content ~${LorebookTokenService.format(breakdown.totalTokens)}' : ''}';
}

String lorebookEntryTokenTooltip(LorebookEntry entry, int tokens) {
  final parts = <String>[
    'Content ~${LorebookTokenService.format(tokens)}',
    if (entry.constant) 'Always on',
    if (!entry.enabled) 'Off — not injected',
    if (entry.keys.isNotEmpty) 'Keys: ${entry.keys.join(', ')}',
  ];
  return parts.join(' · ');
}
