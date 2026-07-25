import 'package:flutter/material.dart';

import '../models/saved_opening_scene.dart';
import '../screens/opening_scenes_screen.dart';
import '../services/opening_scene_service.dart';
import '../services/world_workshop_service.dart';

/// Result from the optional opening-scene sheet when starting a chat.
class OpeningScenePick {
  const OpeningScenePick(this.text);

  /// Narrator/setup prose. Empty when the user skips.
  final String text;
}

/// Optional sheet to add narrator-style opening prose before the first reply.
///
/// Returns `null` when cancelled, or an [OpeningScenePick] (text may be empty when
/// skipped).
Future<OpeningScenePick?> pickOpeningScene(
  BuildContext context, {
  String initial = '',
  String? subtitle,
  List<SavedOpeningScene> savedScenes = const [],
  OpeningSceneService? openingSceneService,
  WorldWorkshopService? workshopService,
}) async {
  return showModalBottomSheet<OpeningScenePick>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) {
      final controller = TextEditingController(text: initial.trim());
      return Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SafeArea(
          child: StatefulBuilder(
            builder: (context, setSheetState) {
              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Opening scene',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle ??
                          'Optional narrator setup shown once at the top of the chat. '
                          'It is not the character’s first line and is not sent every turn.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                    ),
                    if (savedScenes.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Text(
                        'Saved opening scenes',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 8),
                      ...savedScenes.take(6).map((scene) {
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            dense: true,
                            title: Text(scene.title),
                            subtitle: Text(scene.preview),
                            onTap: () {
                              controller.text = scene.text;
                              setSheetState(() {});
                            },
                          ),
                        );
                      }),
                      if (savedScenes.length > 6)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            '+ ${savedScenes.length - 6} more in the library',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ),
                    ],
                    if (openingSceneService != null &&
                        workshopService != null) ...[
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () async {
                            final picked =
                                await Navigator.of(context).push<SavedOpeningScene>(
                              MaterialPageRoute(
                                builder: (_) => OpeningScenesScreen(
                                  openingSceneService: openingSceneService,
                                  workshopService: workshopService,
                                  pickMode: true,
                                ),
                              ),
                            );
                            if (picked == null) return;
                            controller.text = picked.text;
                            setSheetState(() {});
                          },
                          icon: const Icon(Icons.auto_stories_outlined),
                          label: const Text('Browse opening scene library'),
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    TextField(
                      controller: controller,
                      minLines: 4,
                      maxLines: 10,
                      autofocus:
                          initial.trim().isEmpty && savedScenes.isEmpty,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        hintText:
                            'e.g. Rain drums on the tavern roof. Lantern light pools on '
                            'empty mugs while the city waits…',
                        border: OutlineInputBorder(),
                        alignLabelWithHint: true,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancel'),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () => Navigator.pop(
                            context,
                            const OpeningScenePick(''),
                          ),
                          child: const Text('Skip'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: () => Navigator.pop(
                            context,
                            OpeningScenePick(controller.text.trim()),
                          ),
                          child: const Text('Use'),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      );
    },
  );
}
