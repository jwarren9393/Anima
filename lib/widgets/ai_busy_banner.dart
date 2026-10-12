import 'package:flutter/material.dart';

/// Status strip with a spinner — shown while AI drafts or edits a card.
class AiBusyBanner extends StatelessWidget {
  const AiBusyBanner({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.tertiary;
    return Material(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: accent,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    message,
                    style: theme.textTheme.labelMedium?.copyWith(color: accent),
                  ),
                ),
              ],
            ),
          ),
          LinearProgressIndicator(
            minHeight: 2,
            color: accent,
            backgroundColor: accent.withValues(alpha: 0.15),
          ),
        ],
      ),
    );
  }
}

/// Compact AppBar spinner for the same AI-busy state.
class AiBusyAppBarSpinner extends StatelessWidget {
  const AiBusyAppBarSpinner({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 12),
      child: Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}
