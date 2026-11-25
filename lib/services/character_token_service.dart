import '../models/character.dart';
import '../models/lorebook.dart';
import 'chat_context_service.dart';
import 'prompt_builder.dart';

/// Rough token footprint of a character card (≈ 1 token per 4 characters).
class CharacterTokenBreakdown {
  const CharacterTokenBreakdown({
    required this.promptTokens,
    required this.postHistoryTokens,
    required this.embeddedLoreTokens,
    required this.groupSummaryTokens,
    required this.fieldTokens,
  });

  final int promptTokens;
  final int postHistoryTokens;
  final int embeddedLoreTokens;
  final int groupSummaryTokens;
  final Map<String, int> fieldTokens;

  int get speakerTotal => promptTokens + postHistoryTokens;
  int get withLoreMax => speakerTotal + embeddedLoreTokens;
}

/// Breakdown for the next chat reply (built from real prompt pieces).
class ChatPromptBreakdown {
  const ChatPromptBreakdown({
    required this.speakerName,
    required this.speakerCardTokens,
    required this.castSummaries,
    required this.loreTokens,
    required this.loreMatchedCount,
    required this.personaTokens,
    required this.memoryTokens,
    required this.historyTokens,
    required this.postHistoryTokens,
    required this.estimatedSentTokens,
  });

  final String speakerName;
  final int speakerCardTokens;
  final List<({String name, int tokens})> castSummaries;
  final int loreTokens;
  final int loreMatchedCount;
  final int personaTokens;
  final int memoryTokens;
  final int historyTokens;
  final int postHistoryTokens;
  final int estimatedSentTokens;
}

class CharacterTokenService {
  const CharacterTokenService([
    this._context = const ChatContextService(),
    this._promptBuilder = const PromptBuilder(),
  ]);

  final ChatContextService _context;
  final PromptBuilder _promptBuilder;

  int estimateTokens(String text) => _context.estimateTokens(text);

  static String format(int tokens) => ContextEstimate.formatTokenCount(tokens);

  CharacterTokenBreakdown breakdown(Character character) {
    final fieldTokens = <String, int>{
      'System prompt': estimateTokens(
        character.systemPrompt.trim().isEmpty
            ? PromptBuilder.defaultSystemSeed
            : character.systemPrompt,
      ),
      'Description': estimateTokens(character.description),
      'Personality': estimateTokens(character.personality),
      'Scenario': estimateTokens(character.scenario),
      'Example dialogue': estimateTokens(character.mesExample),
    };

    final promptBody = <String>[
      if (character.systemPrompt.trim().isNotEmpty)
        character.systemPrompt.trim()
      else
        PromptBuilder.defaultSystemSeed,
      if (character.description.trim().isNotEmpty)
        'Description:\n${character.description.trim()}',
      if (character.personality.trim().isNotEmpty)
        'Personality:\n${character.personality.trim()}',
      if (character.scenario.trim().isNotEmpty)
        'Scenario:\n${character.scenario.trim()}',
      if (character.mesExample.trim().isNotEmpty)
        'Example dialogue:\n${character.mesExample.trim()}',
    ].join('\n\n');

    return CharacterTokenBreakdown(
      promptTokens: estimateTokens(promptBody),
      postHistoryTokens: estimateTokens(character.postHistoryInstructions),
      embeddedLoreTokens: _embeddedLoreTokens(character),
      groupSummaryTokens: estimateTokens(_promptBuilder.characterSummary(character)),
      fieldTokens: fieldTokens,
    );
  }

  int badgeTokens(Character character) => breakdown(character).speakerTotal;

  int _embeddedLoreTokens(Character character) {
    final Lorebook? book = character.lorebook;
    if (book == null) return 0;
    var total = 0;
    for (final entry in book.entries) {
      if (!entry.enabled) continue;
      final content = entry.content.trim();
      if (content.isEmpty) continue;
      total += estimateTokens(content);
    }
    return total;
  }
}
