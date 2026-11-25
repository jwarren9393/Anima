import 'package:flutter/material.dart';

import '../models/anima_presets.dart';

/// Button that opens a preset list (name + description) and applies one.
class PresetButton extends StatelessWidget {
  const PresetButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.playlist_add_check, size: 20),
        label: Text(label),
      ),
    );
  }
}

/// Bottom sheet: pick a text preset (shows full description).
Future<TextPreset?> pickTextPreset({
  required BuildContext context,
  required String title,
  required List<TextPreset> presets,
}) {
  return showModalBottomSheet<TextPreset>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) {
      return SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Text(title, style: Theme.of(context).textTheme.titleMedium),
            ),
            for (final preset in presets)
              ListTile(
                title: Text(preset.name),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(preset.description),
                ),
                isThreeLine: true,
                onTap: () => Navigator.pop(context, preset),
              ),
            const SizedBox(height: 12),
          ],
        ),
      );
    },
  );
}

/// Bottom sheet: pick a sampling preset.
Future<SamplingPreset?> pickSamplingPreset({
  required BuildContext context,
}) {
  return showModalBottomSheet<SamplingPreset>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) {
      return SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Text(
                'Generation presets',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'Loads all knobs at once. You can still edit numbers after. '
                'Remember to Save.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            for (final preset in AnimaPresets.sampling)
              ListTile(
                title: Text(preset.name),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(preset.description),
                ),
                isThreeLine: true,
                onTap: () => Navigator.pop(context, preset),
              ),
            const SizedBox(height: 12),
          ],
        ),
      );
    },
  );
}

/// Bottom sheet: pick a context-size preset.
Future<ContextPreset?> pickContextPreset({
  required BuildContext context,
}) {
  return showModalBottomSheet<ContextPreset>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) {
      return SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Text(
                'Context size presets',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'How many tokens of recent chat the AI sees each turn. Save afterward.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            for (final preset in AnimaPresets.contextSize)
              ListTile(
                title: Text(preset.name),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(preset.description),
                ),
                isThreeLine: true,
                onTap: () => Navigator.pop(context, preset),
              ),
            const SizedBox(height: 12),
          ],
        ),
      );
    },
  );
}
