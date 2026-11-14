import 'package:flutter/material.dart';

import '../models/lorebook.dart';
import '../models/lorebook_gap_suggestion.dart';

/// Review AI-drafted lore entries for workshop gaps before lorebook export.
///
/// Returns selected [LorebookEntry] values when the user confirms, `null` if
/// dismissed or cancelled.
Future<List<LorebookEntry>?> showLorebookGapFillSheet({
  required BuildContext context,
  required List<LorebookGapSuggestion> suggestions,
}) {
  if (suggestions.isEmpty) return Future.value(const []);

  return showModalBottomSheet<List<LorebookEntry>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _LorebookGapFillSheet(suggestions: suggestions),
  );
}

class _LorebookGapFillSheet extends StatefulWidget {
  const _LorebookGapFillSheet({required this.suggestions});

  final List<LorebookGapSuggestion> suggestions;

  @override
  State<_LorebookGapFillSheet> createState() => _LorebookGapFillSheetState();
}

class _LorebookGapFillSheetState extends State<_LorebookGapFillSheet> {
  late final Set<String> _selectedIds;
  final Set<String> _expandedIds = {};

  @override
  void initState() {
    super.initState();
    _selectedIds = {for (final s in widget.suggestions) s.id};
  }

  int get _selectedCount => _selectedIds.length;

  void _toggleExpanded(String id) {
    setState(() {
      if (_expandedIds.contains(id)) {
        _expandedIds.remove(id);
      } else {
        _expandedIds.add(id);
      }
    });
  }

  void _apply() {
    final selected = <LorebookEntry>[];
    for (final suggestion in widget.suggestions) {
      if (_selectedIds.contains(suggestion.id)) {
        selected.add(suggestion.entry);
      }
    }
    Navigator.pop(context, selected);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 8,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Review gap-fill entries', style: theme.textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(
              'Each suggestion is one World Info entry. Uncheck any you do not '
              'want — the rest are merged into the lorebook when you create it.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Text(
              '$_selectedCount of ${widget.suggestions.length} selected',
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.tertiary,
              ),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: widget.suggestions.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final suggestion = widget.suggestions[index];
                  final expanded = _expandedIds.contains(suggestion.id);
                  final checked = _selectedIds.contains(suggestion.id);
                  final entry = suggestion.entry;

                  return Card(
                    child: InkWell(
                      onTap: () => _toggleExpanded(suggestion.id),
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(4, 8, 12, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Checkbox(
                                  value: checked,
                                  onChanged: (value) {
                                    setState(() {
                                      if (value == true) {
                                        _selectedIds.add(suggestion.id);
                                      } else {
                                        _selectedIds.remove(suggestion.id);
                                      }
                                    });
                                  },
                                ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        entry.displayLabel,
                                        style: theme.textTheme.titleSmall,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        suggestion.gap,
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                          color: theme
                                              .colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                      if (!expanded &&
                                          entry.keys.isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          'Keywords: ${entry.keys.join(', ')}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: theme.textTheme.bodySmall,
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                Icon(
                                  expanded
                                      ? Icons.expand_less
                                      : Icons.expand_more,
                                  size: 20,
                                ),
                              ],
                            ),
                            if (expanded) ...[
                              const SizedBox(height: 8),
                              if (entry.keys.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(left: 12),
                                  child: Text(
                                    'Keywords: ${entry.keys.join(', ')}',
                                    style: theme.textTheme.labelSmall,
                                  ),
                                ),
                              const SizedBox(height: 6),
                              Padding(
                                padding: const EdgeInsets.only(left: 12),
                                child: SelectableText(
                                  entry.content.trim().isEmpty
                                      ? '(empty)'
                                      : entry.content.trim(),
                                  style: theme.textTheme.bodySmall,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _apply,
                    child: Text(
                      _selectedCount == 0
                          ? 'Create without extras'
                          : 'Create with $_selectedCount',
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
