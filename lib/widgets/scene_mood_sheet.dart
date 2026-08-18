import 'package:flutter/material.dart';

import '../models/scene_mood_presets.dart';

/// Pick which scene moods are active for this chat (merged into Author's Note).
Future<List<String>?> showSceneMoodSheet({
  required BuildContext context,
  required List<String> activeIds,
}) {
  return showModalBottomSheet<List<String>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _SceneMoodSheet(initialActive: activeIds),
  );
}

class _SceneMoodSheet extends StatefulWidget {
  const _SceneMoodSheet({required this.initialActive});

  final List<String> initialActive;

  @override
  State<_SceneMoodSheet> createState() => _SceneMoodSheetState();
}

class _SceneMoodSheetState extends State<_SceneMoodSheet> {
  late final Set<String> _active = {...widget.initialActive};

  void _toggle(String id, bool on) {
    setState(() {
      if (on) {
        _active.add(id);
      } else {
        _active.remove(id);
      }
    });
  }

  void _clearAll() => setState(_active.clear);

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
            Text('Scene moods', style: theme.textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(
              'Toggle moods for this chat only. Active moods inject into every '
              'reply (like Author\'s Note). Turn off when the scene ends.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  '${_active.length} active',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.tertiary,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: _active.isEmpty ? null : _clearAll,
                  child: const Text('Clear all'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: SceneMoodPresets.all.length,
                separatorBuilder: (_, index) => const SizedBox(height: 4),
                itemBuilder: (context, index) {
                  final preset = SceneMoodPresets.all[index];
                  final on = _active.contains(preset.id);
                  return SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: on,
                    onChanged: (value) => _toggle(preset.id, value),
                    title: Text(preset.name),
                    subtitle: Text(preset.description),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
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
                    onPressed: () =>
                        Navigator.pop(context, _active.toList()..sort()),
                    child: const Text('Done'),
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
