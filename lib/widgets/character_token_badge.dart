import 'package:flutter/material.dart';

import '../services/character_token_service.dart';
import '../services/chat_context_service.dart';

class CharacterTokenBadge extends StatelessWidget {
  const CharacterTokenBadge({
    super.key,
    required this.tokens,
    this.tooltip,
  });

  final int tokens;
  final String? tooltip;

  Color _color(ColorScheme scheme) {
    if (tokens >= 3000) return scheme.error;
    if (tokens >= 1500) return scheme.tertiary;
    return scheme.outline;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final child = Text(
      '~${ContextEstimate.formatTokenCount(tokens)}',
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: _color(scheme),
            fontWeight: FontWeight.w500,
          ),
    );
    if (tooltip == null) return child;
    return Tooltip(message: tooltip!, child: child);
  }
}

String characterTokenTooltip(CharacterTokenBreakdown breakdown) {
  final bits = <String>[
    'Prompt ~${CharacterTokenService.format(breakdown.promptTokens)}',
    if (breakdown.postHistoryTokens > 0)
      'Post-history ~${CharacterTokenService.format(breakdown.postHistoryTokens)}',
    if (breakdown.embeddedLoreTokens > 0)
      'Embedded lore (max) ~${CharacterTokenService.format(breakdown.embeddedLoreTokens)}',
  ];
  return bits.join(' · ');
}
