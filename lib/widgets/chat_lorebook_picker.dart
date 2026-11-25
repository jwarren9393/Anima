import 'package:flutter/material.dart';

import '../models/global_lorebook.dart';

/// Pick which library lorebooks apply to one chat (at start or Manage cast).
///
/// Returns `null` if cancelled. An empty list means no library lorebooks for
/// this chat (character-card lore still applies when they speak).
Future<List<String>?> pickChatLorebookIds(
  BuildContext context, {
  required List<GlobalLorebook> allBooks,
  List<String> initialIds = const [],
  String title = 'Lorebooks for this chat',
}) async {
  final selected = <String>{
    for (final id in initialIds)
      if (id.trim().isNotEmpty) id.trim(),
  };

  return showModalBottomSheet<List<String>>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setSheetState) {
          final maxHeight = MediaQuery.sizeOf(context).height * 0.75;
          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeight),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Only books you pick here apply to this chat. '
                          'Nothing is “on for every chat.” Each character’s '
                          'own embedded lorebook still applies when they speak.',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  if (allBooks.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        'No lorebooks in your library yet. Create or import '
                        'them under Settings → World Info & lore.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    )
                  else
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          CheckboxListTile(
                            value: selected.isEmpty,
                            title: const Text('None'),
                            subtitle: const Text('No library lorebooks for this chat'),
                            controlAffinity: ListTileControlAffinity.leading,
                            onChanged: (_) {
                              setSheetState(selected.clear);
                            },
                          ),
                          for (final book in allBooks)
                            CheckboxListTile(
                              value: selected.contains(book.id),
                              title: Text(book.displayName),
                              subtitle: Text(
                                '${book.enabledEntryCount} entries on',
                              ),
                              controlAffinity: ListTileControlAffinity.leading,
                              onChanged: (on) {
                                setSheetState(() {
                                  if (on == true) {
                                    selected.add(book.id);
                                  } else {
                                    selected.remove(book.id);
                                  }
                                });
                              },
                            ),
                        ],
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                    child: Row(
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancel'),
                        ),
                        const Spacer(),
                        FilledButton(
                          onPressed: () {
                            Navigator.pop(
                              context,
                              selected.toList(growable: false),
                            );
                          },
                          child: const Text('Done'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

/// Short label for Manage cast / status lines.
String chatLorebookMenuLabel(List<String>? chatLorebookIds) {
  final ids = chatLorebookIds ?? const <String>[];
  if (ids.isEmpty) return 'Lorebooks: none';
  final n = ids.length;
  return 'Lorebooks: $n book${n == 1 ? '' : 's'}';
}
