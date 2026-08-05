import '../services/settings_service.dart';

/// What to pull from a saved roleplay chat into a Creation Center workshop.
class WorkshopChatImportOptions {
  const WorkshopChatImportOptions({
    this.includeMemorySummary = true,
    this.includeRecentMessages = true,
    this.includeCharacters = true,
    this.includePersona = true,
    this.includeGlobalLorebooks = false,
    this.includeEmbeddedCharacterLore = false,
    this.includeAuthorsNote = true,
    this.keepRecent = ContextSettings.defaultKeepRecent,
  });

  final bool includeMemorySummary;
  final bool includeRecentMessages;
  final bool includeCharacters;
  final bool includePersona;

  /// Global World Info books explicitly linked on the chat ([ChatSession.lorebookIds]).
  final bool includeGlobalLorebooks;

  /// Lorebooks embedded on imported character cards.
  final bool includeEmbeddedCharacterLore;
  final bool includeAuthorsNote;

  /// How many recent messages to keep (matches Summarize “keep recent” setting).
  final int keepRecent;

  static const defaults = WorkshopChatImportOptions();

  WorkshopChatImportOptions copyWith({
    bool? includeMemorySummary,
    bool? includeRecentMessages,
    bool? includeCharacters,
    bool? includePersona,
    bool? includeGlobalLorebooks,
    bool? includeEmbeddedCharacterLore,
    bool? includeAuthorsNote,
    int? keepRecent,
  }) {
    return WorkshopChatImportOptions(
      includeMemorySummary:
          includeMemorySummary ?? this.includeMemorySummary,
      includeRecentMessages:
          includeRecentMessages ?? this.includeRecentMessages,
      includeCharacters: includeCharacters ?? this.includeCharacters,
      includePersona: includePersona ?? this.includePersona,
      includeGlobalLorebooks:
          includeGlobalLorebooks ?? this.includeGlobalLorebooks,
      includeEmbeddedCharacterLore: includeEmbeddedCharacterLore ??
          this.includeEmbeddedCharacterLore,
      includeAuthorsNote: includeAuthorsNote ?? this.includeAuthorsNote,
      keepRecent: keepRecent ?? this.keepRecent,
    );
  }

  /// One-line summary stored on the imported source for the workshop UI.
  String summaryLine({
    required int totalMessages,
    required int recentCount,
    required bool hasMemory,
    required int globalLoreCount,
    required int embeddedLoreCount,
  }) {
    final bits = <String>[];
    if (includeMemorySummary && hasMemory) bits.add('memory summary');
    if (includeRecentMessages && recentCount > 0) {
      bits.add(
        '$recentCount recent message${recentCount == 1 ? '' : 's'}'
        ' (of $totalMessages)',
      );
    }
    if (includeCharacters) bits.add('character cards');
    if (includePersona) bits.add('persona');
    if (includeGlobalLorebooks && globalLoreCount > 0) {
      bits.add(
        '$globalLoreCount linked lorebook${globalLoreCount == 1 ? '' : 's'}',
      );
    }
    if (includeEmbeddedCharacterLore && embeddedLoreCount > 0) {
      bits.add(
        '$embeddedLoreCount embedded lorebook'
        '${embeddedLoreCount == 1 ? '' : 's'}',
      );
    }
    if (includeAuthorsNote) bits.add('author\'s note');
    if (bits.isEmpty) return 'Custom import (minimal)';
    return bits.join(' · ');
  }
}
