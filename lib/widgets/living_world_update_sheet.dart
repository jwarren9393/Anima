import 'package:flutter/material.dart';

import '../services/living_world_update_service.dart';

/// Review AI-proposed Living World canon updates before anything is saved.
///
/// Returns the selected updates, or `null` if cancelled / empty.
Future<List<LivingWorldCanonUpdate>?> showLivingWorldUpdateSheet({
  required BuildContext context,
  required List<LivingWorldCanonUpdate> updates,
  String title = 'Update Living World',
  String? subtitle,
  String applyLabel = 'Apply selected',
}) {
  if (updates.isEmpty) return Future.value(null);

  return showModalBottomSheet<List<LivingWorldCanonUpdate>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _LivingWorldUpdateSheet(
      title: title,
      subtitle: subtitle ??
          'Nothing is saved until you apply. Unselected rows are discarded.',
      updates: updates,
      applyLabel: applyLabel,
    ),
  );
}

class _LivingWorldUpdateSheet extends StatefulWidget {
  const _LivingWorldUpdateSheet({
    required this.title,
    required this.subtitle,
    required this.updates,
    required this.applyLabel,
  });

  final String title;
  final String subtitle;
  final List<LivingWorldCanonUpdate> updates;
  final String applyLabel;

  @override
  State<_LivingWorldUpdateSheet> createState() =>
      _LivingWorldUpdateSheetState();
}

class _LivingWorldUpdateSheetState extends State<_LivingWorldUpdateSheet> {
  late final Set<int> _selected = {
    for (var i = 0; i < widget.updates.length; i++) i,
  };

  void _selectAll() => setState(() {
        _selected
          ..clear()
          ..addAll(List.generate(widget.updates.length, (i) => i));
      });

  void _selectNone() => setState(_selected.clear);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedCount = _selected.length;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.8;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 8,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.title, style: theme.textTheme.titleLarge),
              const SizedBox(height: 6),
              Text(widget.subtitle, style: theme.textTheme.bodySmall),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '$selectedCount of ${widget.updates.length} selected',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.tertiary,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _selected.length == widget.updates.length
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
                  itemCount: widget.updates.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final update = widget.updates[index];
                    final selected = _selected.contains(index);
                    return Card(
                      child: CheckboxListTile(
                        value: selected,
                        onChanged: (on) => setState(() {
                          if (on == true) {
                            _selected.add(index);
                          } else {
                            _selected.remove(index);
                          }
                        }),
                        title: Text(update.reviewLabel),
                        subtitle: Text(update.reviewDetail),
                        controlAffinity: ListTileControlAffinity.leading,
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
                      onPressed: selectedCount == 0
                          ? null
                          : () {
                              final picked = [
                                for (final i in _selected.toList()..sort())
                                  widget.updates[i],
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
      ),
    );
  }
}
