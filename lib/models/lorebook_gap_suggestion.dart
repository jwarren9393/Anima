import 'lorebook.dart';

/// One AI-proposed World Info entry that addresses a workshop gap before export.
class LorebookGapSuggestion {
  const LorebookGapSuggestion({
    required this.id,
    required this.gap,
    required this.entry,
  });

  final String id;
  final String gap;
  final LorebookEntry entry;
}
