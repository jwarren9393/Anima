import 'package:flutter/material.dart';

import '../models/global_lorebook.dart';

/// Result from the per-chat World Info picker.
class ChatLorebookPickResult {
  const ChatLorebookPickResult.appDefault()
      : useAppDefault = true,
        selectedIds = const [];

  const ChatLorebookPickResult.custom(this.selectedIds) : useAppDefault = false;

  /// When true, the chat uses every globally enabled lorebook (Settings default).
  final bool useAppDefault;

  /// Active when [useAppDefault] is false — may be empty (no global lore).
  final List<String> selectedIds;
}

/// Choose which global lorebooks apply to one chat thread.
///
/// Returns `null` when cancelled.
Future<ChatLorebookPickResult?> pickChatLorebooks(
  BuildContext context, {
  required List<GlobalLorebook> allBooks,
  required List<String>? chatLorebookIds,
}) async {
  var useAppDefault = chatLorebookIds == null;
  final selected = <String>{
    if (chatLorebookIds != null)
      ...chatLorebookIds
    else
      for (final b in allBooks)
        if (b.enabled) b.id,
  };

  return showModalBottomSheet<ChatLorebookPickResult>(
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
                          'World Info for this chat',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Pick which global lorebooks apply here. Each '
                          'character’s own embedded lorebook still applies when '
                          'they speak. Use Chat lore (⋮ menu) for facts that '
                          'belong only to this thread.',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                  SwitchListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                    title: const Text('Use Settings default'),
                    subtitle: const Text(
                      'All lorebooks enabled under Settings → World Info & lore.',
                    ),
                    value: useAppDefault,
                    onChanged: (v) {
                      setSheetState(() {
                        useAppDefault = v;
                        if (v) {
                          selected
                            ..clear()
                            ..addAll(
                              allBooks.where((b) => b.enabled).map((b) => b.id),
                            );
                        }
                      });
                    },
                  ),
                  if (!useAppDefault) ...[
                    const Divider(height: 1),
                    if (allBooks.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(
                          'No global lorebooks yet. Create or import them under '
                          'Settings → World Info & lore.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      )
                    else
                      Flexible(
                        child: ListView(
                          shrinkWrap: true,
                          children: [
                            for (final book in allBooks)
                              CheckboxListTile(
                                value: selected.contains(book.id),
                                title: Text(book.displayName),
                                subtitle: Text(
                                  '${book.enabledEntryCount} entries'
                                  '${book.enabled ? '' : ' · off in Settings'}',
                                ),
                                controlAffinity:
                                    ListTileControlAffinity.leading,
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
                  ],
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
                              useAppDefault
                                  ? const ChatLorebookPickResult.appDefault()
                                  : ChatLorebookPickResult.custom(
                                      selected.toList(growable: false),
                                    ),
                            );
                          },
                          child: const Text('Save'),
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

/// Short label for the chat ⋮ menu.
String chatLorebookMenuLabel(List<String>? chatLorebookIds) {
  if (chatLorebookIds == null) return 'World Info: default';
  if (chatLorebookIds.isEmpty) return 'World Info: none';
  final n = chatLorebookIds.length;
  return 'World Info: $n book${n == 1 ? '' : 's'}';
}
