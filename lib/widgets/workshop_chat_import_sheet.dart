import 'package:flutter/material.dart';

import '../models/chat_session.dart';
import '../models/workshop_chat_import_options.dart';
import '../services/world_workshop_builder.dart';

/// Lets the user choose what to pull from a saved chat before seeding a workshop.
///
/// Returns `null` when cancelled.
Future<WorkshopChatImportOptions?> pickWorkshopChatImportOptions(
  BuildContext context, {
  required ChatSession session,
  required int keepRecentDefault,
  required int linkedLorebookCount,
  required int embeddedLorebookCount,
}) async {
  final builder = WorldWorkshopBuilder();
  final totalMessages = session.messages
      .where((m) => m.text.trim().isNotEmpty)
      .length;
  final hasMemory = session.memorySummary.trim().isNotEmpty;

  var options = WorkshopChatImportOptions(
    keepRecent: keepRecentDefault,
  );

  return showModalBottomSheet<WorkshopChatImportOptions>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setSheetState) {
          void refreshPreview() {
            setSheetState(() {});
          }

          final recent = builder.selectRecentMessagesForImport(
            session,
            keepRecent: options.keepRecent,
            includeRecentMessages: options.includeRecentMessages,
          );
          final summary = options.summaryLine(
            totalMessages: totalMessages,
            recentCount: recent.length,
            hasMemory: hasMemory,
            globalLoreCount: linkedLorebookCount,
            embeddedLoreCount: embeddedLorebookCount,
          );

          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Import options',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      session.title.trim().isEmpty
                          ? 'Choose what to seed this workshop with.'
                          : '“${session.title.trim()}” — $totalMessages messages total.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 12),
                    Material(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest
                          .withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          'Will import: $summary',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Recent messages use the same trim as Summarize: memory '
                      'summary (when set) plus your last $keepRecentDefault '
                      'messages — not the full chat history.',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Memory summary'),
                      subtitle: Text(
                        hasMemory
                            ? 'Older story folded into a compact summary.'
                            : 'This chat has no memory summary yet.',
                      ),
                      value: options.includeMemorySummary && hasMemory,
                      onChanged: hasMemory
                          ? (v) {
                              options = options.copyWith(
                                includeMemorySummary: v,
                              );
                              refreshPreview();
                            }
                          : null,
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('Recent messages (last $keepRecentDefault)'),
                      subtitle: Text(
                        recent.isEmpty
                            ? 'No non-empty messages to include.'
                            : '${recent.length} message${recent.length == 1 ? '' : 's'} from the end of the chat.',
                      ),
                      value: options.includeRecentMessages,
                      onChanged: (v) {
                        options = options.copyWith(includeRecentMessages: v);
                        refreshPreview();
                      },
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Character cards'),
                      subtitle: const Text(
                        'Names, descriptions, and other card fields from the cast.',
                      ),
                      value: options.includeCharacters,
                      onChanged: (v) {
                        options = options.copyWith(includeCharacters: v);
                        refreshPreview();
                      },
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Persona'),
                      subtitle: const Text('Who {{user}} was in this chat.'),
                      value: options.includePersona,
                      onChanged: (v) {
                        options = options.copyWith(includePersona: v);
                        refreshPreview();
                      },
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('World Info lorebooks'),
                      subtitle: Text(
                        linkedLorebookCount == 0
                            ? 'This chat has no lorebooks explicitly linked '
                                '(chat override empty or default).'
                            : '$linkedLorebookCount lorebook'
                                '${linkedLorebookCount == 1 ? '' : 's'} '
                                'linked on this chat only.',
                      ),
                      value: options.includeGlobalLorebooks,
                      onChanged: linkedLorebookCount == 0
                          ? null
                          : (v) {
                              options = options.copyWith(
                                includeGlobalLorebooks: v,
                              );
                              refreshPreview();
                            },
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Embedded character lorebooks'),
                      subtitle: Text(
                        embeddedLorebookCount == 0
                            ? 'No lorebooks embedded on the cast’s cards.'
                            : 'Lore stored on character cards ($embeddedLorebookCount).',
                      ),
                      value: options.includeEmbeddedCharacterLore,
                      onChanged: embeddedLorebookCount == 0
                          ? null
                          : (v) {
                              options = options.copyWith(
                                includeEmbeddedCharacterLore: v,
                              );
                              refreshPreview();
                            },
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Author\'s Note'),
                      value: options.includeAuthorsNote,
                      onChanged: (v) {
                        options = options.copyWith(includeAuthorsNote: v);
                        refreshPreview();
                      },
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancel'),
                        ),
                        const Spacer(),
                        FilledButton(
                          onPressed: () => Navigator.pop(context, options),
                          child: const Text('Import'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );
}
