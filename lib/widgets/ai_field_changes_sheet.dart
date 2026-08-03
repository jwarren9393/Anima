import 'package:flutter/material.dart';

import '../services/ai_field_changes.dart';

/// Bottom sheet: review AI-proposed field changes before applying.
///
/// Returns `true` when the user taps Apply, `false` on Cancel, `null` if dismissed.
Future<bool?> showAiFieldChangesSheet({
  required BuildContext context,
  required String title,
  required List<AiFieldChange> changes,
  String? subtitle,
  String applyLabel = 'Apply changes',
}) {
  if (changes.isEmpty) return Future.value(false);

  return showModalBottomSheet<bool>(
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

class _AiFieldChangesSheet extends StatelessWidget {
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
            Text(title, style: theme.textTheme.titleLarge),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(subtitle!, style: theme.textTheme.bodySmall),
            ],
            const SizedBox(height: 8),
            Text(
              '${changes.length} field${changes.length == 1 ? '' : 's'} changed',
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.tertiary,
              ),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: changes.length,
                separatorBuilder: (_, index) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final change = changes[index];
                  return _ChangeTile(change: change);
                },
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: Text(applyLabel),
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
  const _ChangeTile({required this.change});

  final AiFieldChange change;

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
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
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
                const SizedBox(height: 4),
                Text(
                  previewLine,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              ],
              if (_expanded) ...[
                if (!change.isAddition) ...[
                  const SizedBox(height: 8),
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
            ],
          ),
        ),
      ),
    );
  }
}
