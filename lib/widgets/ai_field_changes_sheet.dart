import 'package:flutter/material.dart';

import '../services/ai_field_changes.dart';

/// Bottom sheet: review AI-proposed field changes before applying.
///
/// Returns the selected changes when the user taps Apply, `null` on Cancel.
Future<List<AiFieldChange>?> showAiFieldChangesSheet({
  required BuildContext context,
  required String title,
  required List<AiFieldChange> changes,
  String? subtitle,
  String applyLabel = 'Apply selected',
}) {
  if (changes.isEmpty) return Future.value(null);

  return showModalBottomSheet<List<AiFieldChange>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _AiFieldChangesSheet(
      title: title,
      subtitle: subtitle,
      changes: changes,
      applyLabel: applyLabel,
    ),
  );
}

class _AiFieldChangesSheet extends StatefulWidget {
  const _AiFieldChangesSheet({
    required this.title,
    required this.changes,
    required this.applyLabel,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final List<AiFieldChange> changes;
  final String applyLabel;

  @override
  State<_AiFieldChangesSheet> createState() => _AiFieldChangesSheetState();
}

class _AiFieldChangesSheetState extends State<_AiFieldChangesSheet> {
  late final Set<int> _selected =
      {for (var i = 0; i < widget.changes.length; i++) i};

  void _selectAll() => setState(() {
        _selected
          ..clear()
          ..addAll(List.generate(widget.changes.length, (i) => i));
      });

  void _selectNone() => setState(_selected.clear);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedCount = _selected.length;

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
            Text(widget.title, style: theme.textTheme.titleLarge),
            if (widget.subtitle != null) ...[
              const SizedBox(height: 6),
              Text(widget.subtitle!, style: theme.textTheme.bodySmall),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '$selectedCount of ${widget.changes.length} selected',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.tertiary,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _selected.length == widget.changes.length
                      ? null
                      : _selectAll,
                  child: const Text('All'),
                ),
                TextButton(
                  onPressed: _selected.isEmpty ? null : _selectNone,
                  child: const Text('None'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: widget.changes.length,
                separatorBuilder: (_, index) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final change = widget.changes[index];
                  return _ChangeTile(
                    change: change,
                    selected: _selected.contains(index),
                    onSelected: (on) => setState(() {
                      if (on) {
                        _selected.add(index);
                      } else {
                        _selected.remove(index);
                      }
                    }),
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
                    onPressed: selectedCount == 0
                        ? null
                        : () {
                            final picked = [
                              for (final i in _selected) widget.changes[i],
                            ];
                            Navigator.pop(context, picked);
                          },
                    child: Text(widget.applyLabel),
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

class _ChangeTile extends StatefulWidget {
  const _ChangeTile({
    required this.change,
    required this.selected,
    required this.onSelected,
  });

  final AiFieldChange change;
  final bool selected;
  final ValueChanged<bool> onSelected;

  @override
  State<_ChangeTile> createState() => _ChangeTileState();
}

class _ChangeTileState extends State<_ChangeTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final change = widget.change;
    final preview = change.isAddition
        ? change.after
        : change.isRemoval
            ? change.before
            : change.after;

    final previewLine = preview
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .take(2)
        .join(' · ');

    return Card(
      child: InkWell(
        onTap: () => setState(() => _expanded = !_expanded),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Checkbox(
                    value: widget.selected,
                    onChanged: (on) {
                      if (on != null) widget.onSelected(on);
                    },
                  ),
                  Expanded(
                    child: Text(
                      change.label,
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                  ),
                ],
              ),
              if (!_expanded && previewLine.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.only(left: 48),
                  child: Text(
                    previewLine,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
              if (_expanded) ...[
                Padding(
                  padding: const EdgeInsets.only(left: 48),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!change.isAddition) ...[
                        const SizedBox(height: 4),
                        Text('Before', style: theme.textTheme.labelSmall),
                        const SizedBox(height: 4),
                        SelectableText(
                          change.before.isEmpty ? '(empty)' : change.before,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      if (!change.isRemoval) ...[
                        const SizedBox(height: 8),
                        Text('After', style: theme.textTheme.labelSmall),
                        const SizedBox(height: 4),
                        SelectableText(
                          change.after.isEmpty ? '(empty)' : change.after,
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
