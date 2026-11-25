import 'package:flutter/material.dart';

import '../models/workshop_hub_models.dart';
import '../models/world_workshop.dart';

/// One row of tappable chips — mode, reply length, scene/import badges.
class WorkshopCompactToolbar extends StatelessWidget {
  const WorkshopCompactToolbar({
    super.key,
    required this.workshop,
    required this.hasImportedSource,
    required this.onPickMode,
    required this.onPickReplyLength,
    this.onImportedSource,
    this.onPromptIdeas,
    this.showPromptIdeas = false,
    this.enabled = true,
  });

  final WorldWorkshop workshop;
  final bool hasImportedSource;
  final VoidCallback onPickMode;
  final VoidCallback onPickReplyLength;
  final VoidCallback? onImportedSource;
  final VoidCallback? onPromptIdeas;
  final bool showPromptIdeas;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          _ChipButton(
            label: workshop.mode.label,
            icon: Icons.tune,
            onPressed: enabled ? onPickMode : null,
          ),
          const SizedBox(width: 8),
          _ChipButton(
            label: workshop.replyLength.label,
            icon: Icons.short_text,
            onPressed: enabled ? onPickReplyLength : null,
          ),
          if (hasImportedSource && onImportedSource != null) ...[
            const SizedBox(width: 8),
            _ChipButton(
              label: 'Import',
              icon: Icons.forum_outlined,
              onPressed: enabled ? onImportedSource : null,
            ),
          ],
          if (showPromptIdeas && onPromptIdeas != null) ...[
            const SizedBox(width: 8),
            _ChipButton(
              label: 'Ideas',
              icon: Icons.lightbulb_outline,
              onPressed: enabled ? onPromptIdeas : null,
            ),
          ],
          if (workshop.isLorebookStale) ...[
            const SizedBox(width: 8),
            Chip(
              avatar: Icon(
                Icons.warning_amber_rounded,
                size: 18,
                color: theme.colorScheme.error,
              ),
              label: Text(
                'Lore stale',
                style: TextStyle(color: theme.colorScheme.error),
              ),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ],
      ),
    );
  }
}

class _ChipButton extends StatelessWidget {
  const _ChipButton({
    required this.label,
    required this.icon,
    this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: Icon(icon, size: 18),
      label: Text(label),
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}

/// Bottom sheet: pick brainstorm mode.
Future<WorkshopMode?> pickWorkshopMode(
  BuildContext context, {
  required WorkshopMode current,
}) {
  return showModalBottomSheet<WorkshopMode>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final mode in WorkshopMode.values)
            ListTile(
              leading: Icon(
                current == mode ? Icons.check_circle : Icons.circle_outlined,
              ),
              title: Text(mode.label),
              subtitle: Text(mode.subtitle),
              onTap: () => Navigator.pop(context, mode),
            ),
        ],
      ),
    ),
  );
}

/// Bottom sheet: pick reply length.
Future<WorkshopReplyLength?> pickWorkshopReplyLength(
  BuildContext context, {
  required WorkshopReplyLength current,
}) {
  return showModalBottomSheet<WorkshopReplyLength>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final mode in WorkshopReplyLength.values)
            ListTile(
              leading: Icon(
                current == mode ? Icons.check_circle : Icons.circle_outlined,
              ),
              title: Text(mode.label),
              subtitle: Text(mode.subtitle),
              onTap: () => Navigator.pop(context, mode),
            ),
        ],
      ),
    ),
  );
}

/// Bottom sheet: brainstorm prompt chips.
Future<String?> pickWorkshopPromptIdea(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          const ListTile(title: Text('Try a prompt')),
          for (final idea in [
            'Describe the setting in 3 sentences',
            'Who are the main factions?',
            'What is the central conflict?',
            'Suggest 5 lorebook entry ideas',
            'What locations matter most?',
            'Who should the cast include?',
          ])
            ListTile(
              title: Text(idea),
              onTap: () => Navigator.pop(context, idea),
            ),
        ],
      ),
    ),
  );
}
