import 'package:flutter/material.dart';

import '../models/character.dart';
import '../services/character_service.dart';

/// Small chip shown on temporary character rows.
class TemporaryCharacterBadge extends StatelessWidget {
  const TemporaryCharacterBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Chip(
      label: Text(
        'Temporary',
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      backgroundColor: theme.colorScheme.tertiaryContainer.withValues(alpha: 0.85),
      side: BorderSide.none,
    );
  }
}

/// Quick-create a lightweight NPC (name + one note field) for the current scene.
Future<Character?> showTemporaryCharacterSheet({
  required BuildContext context,
  required CharacterService characterService,
}) async {
  final nameController = TextEditingController();
  final noteController = TextEditingController();

  final result = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) {
      return Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Temporary character',
                  style: Theme.of(sheetContext).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  'For a quick NPC in this story. Saved with a Temporary badge — '
                  'promote to a full card anytime from Characters.',
                  style: Theme.of(sheetContext).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: nameController,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    hintText: 'e.g. Tavern keeper',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: noteController,
                  minLines: 2,
                  maxLines: 5,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Quick note (optional)',
                    hintText: 'Gruff dockhand, knows the harbor routes…',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () {
                    if (nameController.text.trim().isEmpty) return;
                    Navigator.pop(sheetContext, true);
                  },
                  child: const Text('Add temporary character'),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );

  if (result != true) {
    nameController.dispose();
    noteController.dispose();
    return null;
  }

  final name = nameController.text.trim();
  final note = noteController.text.trim();
  nameController.dispose();
  noteController.dispose();
  if (name.isEmpty) return null;

  final character = Character(
    id: characterService.newId(),
    name: name,
    description: note,
    isTemporary: true,
    tags: const ['temporary'],
  );
  await characterService.upsert(character);
  return character;
}
