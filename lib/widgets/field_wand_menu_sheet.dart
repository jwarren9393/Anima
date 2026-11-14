import 'package:flutter/material.dart';

import '../models/field_wand_options.dart';

/// Long-press menu for a field AI wand — expansion level + optional sources.
Future<FieldWandChoice?> showFieldWandMenuSheet({
  required BuildContext context,
  required String fieldLabel,
  List<FieldWandExternalSource> externalSources = const [],
}) {
  final sources =
      externalSources.where((s) => !s.isEmpty).toList(growable: false);

  return showModalBottomSheet<FieldWandChoice>(
    context: context,
    showDragHandle: true,
    builder: (context) {
      final theme = Theme.of(context);

      Widget tile({
        required IconData icon,
        required String title,
        required String subtitle,
        required FieldWandChoice choice,
      }) {
        return ListTile(
          leading: Icon(icon),
          title: Text(title),
          subtitle: Text(subtitle),
          onTap: () => Navigator.pop(context, choice),
        );
      }

      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: Text(
                'AI wand — $fieldLabel',
                style: theme.textTheme.titleMedium,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Text(
                'Tap the wand for a quick expand. Long-press for these options.',
                style: theme.textTheme.bodySmall,
              ),
            ),
            for (final level in FieldWandExpansion.values)
              tile(
                icon: Icons.auto_awesome_outlined,
                title: '${level.menuTitle} (card)',
                subtitle: level.menuSubtitle,
                choice: FieldWandChoice(expansion: level),
              ),
            if (sources.isNotEmpty) const Divider(height: 1),
            for (final source in sources)
              for (final level in [
                FieldWandExpansion.medium,
                FieldWandExpansion.deep,
              ])
                tile(
                  icon: Icons.library_books_outlined,
                  title: '${level.menuTitle} from ${source.label}',
                  subtitle:
                      'Pull relevant missing details from ${source.label.toLowerCase()} '
                      'into this field.',
                  choice: FieldWandChoice(
                    expansion: level,
                    externalSourceId: source.id,
                  ),
                ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}
