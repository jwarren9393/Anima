import 'package:flutter/material.dart';

/// Actions available from the mobile composer tools sheet (+ button).
class ChatComposerToolsActions {
  const ChatComposerToolsActions({
    required this.onSceneMoods,
    required this.onNarrator,
    this.onGroupReact,
  });

  final VoidCallback? onSceneMoods;
  final VoidCallback? onNarrator;
  final VoidCallback? onGroupReact;
}

/// Opens the compact composer toolbox (mobile — keeps the typing row uncluttered).
Future<void> showChatComposerToolsSheet({
  required BuildContext context,
  required int activeMoodCount,
  required bool showGroupReact,
  required ChatComposerToolsActions actions,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) {
      final theme = Theme.of(context);
      final scheme = theme.colorScheme;

      Widget tile({
        required IconData icon,
        required String label,
        String? subtitle,
        VoidCallback? onTap,
        bool highlight = false,
      }) {
        return ListTile(
          leading: Icon(
            icon,
            color: highlight ? scheme.tertiary : scheme.onSurfaceVariant,
          ),
          title: Text(label),
          subtitle: subtitle == null ? null : Text(subtitle),
          onTap: onTap == null
              ? null
              : () {
                  Navigator.pop(context);
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    onTap();
                  });
                },
        );
      }

      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: Text('Composer tools', style: theme.textTheme.titleMedium),
            ),
            const SizedBox(height: 4),
            tile(
              icon: activeMoodCount > 0 ? Icons.mood : Icons.mood_outlined,
              label: activeMoodCount > 0
                  ? 'Scene moods ($activeMoodCount on)'
                  : 'Scene moods',
              onTap: actions.onSceneMoods,
              highlight: activeMoodCount > 0,
            ),
            tile(
              icon: Icons.theater_comedy_outlined,
              label: 'Narrator',
              onTap: actions.onNarrator,
            ),
            if (showGroupReact)
              tile(
                icon: Icons.groups_outlined,
                label: 'Group react',
                onTap: actions.onGroupReact,
              ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}
