import 'package:flutter/material.dart';

import '../models/field_wand_options.dart';

/// Pick how aggressively a workshop create/update merge should add detail.
Future<WorkshopCardMergeDepth?> showWorkshopCardMergeSheet({
  required BuildContext context,
  required bool isUpdate,
}) {
  return showModalBottomSheet<WorkshopCardMergeDepth>(
    context: context,
    showDragHandle: true,
    builder: (context) {
      final theme = Theme.of(context);
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Text(
                isUpdate ? 'Update merge style' : 'Card generation style',
                style: theme.textTheme.titleMedium,
              ),
            ),
            for (final depth in WorkshopCardMergeDepth.values)
              ListTile(
                title: Text(depth.title),
                subtitle: Text(depth.subtitle),
                onTap: () => Navigator.pop(context, depth),
              ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}
