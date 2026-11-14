import 'package:flutter/material.dart';

/// Chat ⋮ → "Add / update character…". One menu entry that consolidates the
/// three character-in-chat flows. Returns the picked action so the chat screen
/// can open the matching flow:
/// - `'new'`       → create a character from this chat (optionally based on
///                   another card/persona)
/// - `'temporary'` → quick NPC (name + note)
/// - `'update'`    → revise one saved card from this thread's context
Future<String?> showAddUpdateCharacterSheet({required BuildContext context}) {
  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'Add / update character',
                style: theme.textTheme.titleLarge,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.auto_awesome_outlined),
              title: const Text('New character from this chat'),
              subtitle: const Text(
                'AI builds a card from recent messages — optionally based on '
                'another card or persona.',
              ),
              onTap: () => Navigator.pop(sheetContext, 'new'),
            ),
            ListTile(
              leading: const Icon(Icons.person_add_alt_1_outlined),
              title: const Text('Add temporary character'),
              subtitle: const Text('Quick NPC for this story — name + short note.'),
              onTap: () => Navigator.pop(sheetContext, 'temporary'),
            ),
            ListTile(
              leading: const Icon(Icons.edit_note_outlined),
              title: const Text('Update saved character from chat'),
              subtitle: const Text('Revise one saved card from this thread’s context.'),
              onTap: () => Navigator.pop(sheetContext, 'update'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}