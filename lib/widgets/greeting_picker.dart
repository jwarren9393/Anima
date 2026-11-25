import 'package:flutter/material.dart';

import '../models/character.dart';
import '../services/prompt_builder.dart';

/// Picks which opening greeting to use when a character has more than one.
///
/// Returns the index into [Character.allGreetings], or `null` if cancelled.
/// When there is only one greeting (or none), returns `0` without showing UI.
Future<int?> pickGreetingIndex(
  BuildContext context, {
  required Character character,
  required String userName,
}) async {
  final builder = const PromptBuilder();
  final greetings = character.allGreetings
      .map(
        (g) => builder.expandGreeting(
          greeting: g,
          character: character,
          userName: userName,
        ),
      )
      .where((g) => g.trim().isNotEmpty)
      .toList();

  if (greetings.length <= 1) return 0;

  return showModalBottomSheet<int>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) {
      return SafeArea(
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.55,
          minChildSize: 0.35,
          maxChildSize: 0.9,
          builder: (context, scrollController) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Choose opening',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${character.name} has ${greetings.length} greetings. '
                        'You can still swipe later.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                    itemCount: greetings.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final text = greetings[index];
                      final preview = text.length > 220
                          ? '${text.substring(0, 220)}…'
                          : text;
                      return ListTile(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: Theme.of(context)
                                .colorScheme
                                .outline
                                .withValues(alpha: 0.35),
                          ),
                        ),
                        title: Text(
                          index == 0 ? 'Primary greeting' : 'Greeting ${index + 1}',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(preview),
                        ),
                        isThreeLine: preview.length > 80,
                        onTap: () => Navigator.pop(context, index),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      );
    },
  );
}
