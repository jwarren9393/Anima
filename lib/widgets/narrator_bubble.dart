import 'package:flutter/material.dart';

import '../models/ui_style_settings.dart';
import 'rp_rich_text.dart';

/// Narrator-style opening scene shown above chat messages (not a character bubble).
class NarratorBubble extends StatelessWidget {
  const NarratorBubble({
    super.key,
    required this.text,
    this.onTap,
    this.injecting = false,
  });

  final String text;
  final VoidCallback? onTap;
  final bool injecting;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ui = AnimaUiTheme.of(context);
    final baseStyle = (theme.textTheme.bodyMedium ?? const TextStyle()).copyWith(
      fontSize:
          (theme.textTheme.bodyMedium?.fontSize ?? 16) * ui.chatFontScale,
      height: 1.45,
    );

    final bubble = Material(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.72),
      borderRadius: BorderRadius.circular(ui.chatBubbleRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(ui.chatBubbleRadius),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.auto_stories_outlined,
                    size: 16,
                    color: theme.colorScheme.tertiary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Opening scene',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.tertiary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (injecting) ...[
                    const SizedBox(width: 8),
                    Tooltip(
                      message:
                          'Still included in AI prompts until you send a message '
                          'or turn it off in ⋮.',
                      child: Icon(
                        Icons.psychology_outlined,
                        size: 15,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const Spacer(),
                  if (onTap != null)
                    Icon(
                      Icons.edit_outlined,
                      size: 16,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                ],
              ),
              const SizedBox(height: 8),
              RpRichText(
                text: text,
                baseStyle: baseStyle.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return Align(
      alignment: Alignment.center,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.92,
        ),
        child: bubble,
      ),
    );
  }
}
