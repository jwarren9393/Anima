import '../models/persona.dart';
import 'chat_context_service.dart';

/// Rough token footprint of a persona (≈ 1 token per 4 characters).
class PersonaTokenBreakdown {
  const PersonaTokenBreakdown({
    required this.promptTokens,
    required this.fieldTokens,
  });

  final int promptTokens;
  final Map<String, int> fieldTokens;
}

class PersonaTokenService {
  const PersonaTokenService([
    this._context = const ChatContextService(),
  ]);

  final ChatContextService _context;

  int estimateTokens(String text) => _context.estimateTokens(text);

  static String format(int tokens) => ContextEstimate.formatTokenCount(tokens);

  PersonaTokenBreakdown breakdown(Persona persona) {
    if (persona.isAnonymous) {
      return const PersonaTokenBreakdown(
        promptTokens: 0,
        fieldTokens: {},
      );
    }
    final fieldTokens = <String, int>{
      'Identity and role': estimateTokens(persona.description),
      'Appearance': estimateTokens(persona.appearance),
      'Personality': estimateTokens(persona.personality),
      'Background': estimateTokens(persona.background),
      'Goals': estimateTokens(persona.goals),
    };
    return PersonaTokenBreakdown(
      promptTokens: estimateTokens(persona.promptText),
      fieldTokens: fieldTokens,
    );
  }

  int badgeTokens(Persona persona) => breakdown(persona).promptTokens;
}

String personaTokenTooltip(PersonaTokenBreakdown breakdown) {
  final bits = <String>[
    'Persona ~${PersonaTokenService.format(breakdown.promptTokens)}',
  ];
  final topFields = breakdown.fieldTokens.entries
      .where((e) => e.value > 0)
      .toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  if (topFields.isNotEmpty) {
    bits.add(
      topFields
          .take(3)
          .map((e) => '${e.key} ~${PersonaTokenService.format(e.value)}')
          .join(' · '),
    );
  }
  return bits.join('\n');
}
