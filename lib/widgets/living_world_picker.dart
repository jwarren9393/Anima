import 'package:flutter/material.dart';

import '../models/living_world.dart';

/// Result from the per-chat Living World picker.
class LivingWorldPickResult {
  const LivingWorldPickResult.off()
      : worldId = null,
        createEmpty = false,
        createSample = false,
        importFile = false;

  const LivingWorldPickResult.bind(this.worldId)
      : createEmpty = false,
        createSample = false,
        importFile = false;

  const LivingWorldPickResult.createEmpty()
      : worldId = null,
        createEmpty = true,
        createSample = false,
        importFile = false;

  const LivingWorldPickResult.createSample()
      : worldId = null,
        createEmpty = false,
        createSample = true,
        importFile = false;

  const LivingWorldPickResult.importFile()
      : worldId = null,
        createEmpty = false,
        createSample = false,
        importFile = true;

  final String? worldId;
  final bool createEmpty;
  final bool createSample;
  final bool importFile;

  bool get clearBinding =>
      worldId == null && !createEmpty && !createSample && !importFile;
}

/// Bind this chat to a Living World notebook (or turn Living World off).
///
/// Returns `null` when cancelled.
Future<LivingWorldPickResult?> pickLivingWorld(
  BuildContext context, {
  required List<LivingWorldSummary> worlds,
  required String? currentWorldId,
}) async {
  return showModalBottomSheet<LivingWorldPickResult>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) {
      final maxHeight = MediaQuery.sizeOf(context).height * 0.75;
      final scheme = Theme.of(context).colorScheme;
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Living World for this chat',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Optional. When bound, Anima retrieves a small pack of '
                      'world facts into solo replies. Off by default — classic '
                      'Anima stays unchanged. Lorebooks and Memory summary still '
                      'work as usual.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    ListTile(
                      leading: Icon(
                        (currentWorldId == null || currentWorldId.isEmpty)
                            ? Icons.check_circle
                            : Icons.circle_outlined,
                      ),
                      title: const Text('Off (no Living World)'),
                      subtitle: const Text('Default — classic chat only'),
                      onTap: () {
                        Navigator.pop(
                          context,
                          const LivingWorldPickResult.off(),
                        );
                      },
                    ),
                    const Divider(height: 1),
                    if (worlds.isEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                        child: Text(
                          'No worlds yet. Create an empty notebook, a small '
                          'sample town, or import a world JSON file.',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                        ),
                      )
                    else
                      for (final world in worlds)
                        ListTile(
                          leading: Icon(
                            currentWorldId == world.id
                                ? Icons.check_circle
                                : Icons.circle_outlined,
                          ),
                          title: Text(world.title),
                          subtitle: Text(
                            '${world.personCount} people · '
                            '${world.placeCount} places',
                          ),
                          onTap: () {
                            Navigator.pop(
                              context,
                              LivingWorldPickResult.bind(world.id),
                            );
                          },
                        ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.note_add_outlined),
                      title: const Text('Create empty world…'),
                      onTap: () {
                        Navigator.pop(
                          context,
                          const LivingWorldPickResult.createEmpty(),
                        );
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.holiday_village_outlined),
                      title: const Text('Create sample harbor town…'),
                      subtitle: const Text(
                        'Tiny demo world so you can try retrieval',
                      ),
                      onTap: () {
                        Navigator.pop(
                          context,
                          const LivingWorldPickResult.createSample(),
                        );
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.upload_file_outlined),
                      title: const Text('Import world JSON…'),
                      onTap: () {
                        Navigator.pop(
                          context,
                          const LivingWorldPickResult.importFile(),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// Small demo world for Phase 1 playtests (genre-neutral harbor town).
LivingWorld buildSampleHarborWorld() {
  return LivingWorld(
    id: LivingWorld.newId(),
    title: 'Sample Harbor',
    genreNote: 'Quiet coastal town — demo Living World notebook',
    people: const [
      WorldPerson(
        id: 'p_mira',
        name: 'Mira',
        summary: 'Harbor clerk who keeps the pier ledger.',
        personalityNotes: 'Dry humor; remembers favors.',
      ),
      WorldPerson(
        id: 'p_edric',
        name: 'Edric',
        summary: 'Boat repair lead on the south dock.',
        personalityNotes: 'Blunt; loyal to the pier crew.',
      ),
      WorldPerson(
        id: 'p_lena',
        name: 'Lena',
        summary: 'Runs the night market stall by the lanterns.',
        personalityNotes: 'Curious; trades gossip carefully.',
      ),
    ],
    places: const [
      WorldPlace(
        id: 'pl_pier',
        name: 'South Pier',
        description: 'Working docks, salt air, repair sheds.',
        connectedPlaceIds: ['pl_market', 'pl_inn'],
      ),
      WorldPlace(
        id: 'pl_market',
        name: 'Night Market',
        description: 'Lantern stalls after sunset.',
        connectedPlaceIds: ['pl_pier', 'pl_inn'],
      ),
      WorldPlace(
        id: 'pl_inn',
        name: 'Harbor Inn',
        description: 'Common room and rented upstairs rooms.',
        connectedPlaceIds: ['pl_pier', 'pl_market'],
      ),
    ],
    relationships: const [
      WorldRelationship(
        fromId: 'p_mira',
        toId: 'p_edric',
        score: 40,
        labels: ['coworker', 'trust'],
      ),
      WorldRelationship(
        fromId: 'p_edric',
        toId: 'p_mira',
        score: 35,
        labels: ['coworker'],
      ),
      WorldRelationship(
        fromId: 'p_lena',
        toId: 'p_mira',
        score: 15,
        labels: ['acquaintance'],
      ),
    ],
    events: const [
      WorldEvent(
        id: 'e1',
        text: 'Mira logged a missing crate on the South Pier ledger.',
        at: 'turn-1',
        placeId: 'pl_pier',
        personIds: ['p_mira'],
      ),
      WorldEvent(
        id: 'e2',
        text: 'Edric promised to check the crate seals at dawn.',
        at: 'turn-2',
        placeId: 'pl_pier',
        personIds: ['p_edric', 'p_mira'],
      ),
      WorldEvent(
        id: 'e3',
        text: 'Lena heard market talk about a sealed letter for Mira.',
        at: 'turn-3',
        placeId: 'pl_market',
        personIds: ['p_lena', 'p_mira'],
      ),
    ],
    flags: const [
      WorldFlag(id: 'f1', key: 'mira_knows_crate_missing', value: true),
      WorldFlag(id: 'f2', key: 'edric_promised_dawn_check', value: true),
      WorldFlag(id: 'f3', key: 'letter_rumor_at_market', value: true),
    ],
    liveState: const WorldLiveState(
      activePlaceId: 'pl_pier',
      personLocations: {
        'p_mira': 'pl_pier',
        'p_edric': 'pl_pier',
        'p_lena': 'pl_market',
      },
    ),
  );
}

String livingWorldMenuLabel(String? worldId, String? worldTitle) {
  if (worldId == null || worldId.trim().isEmpty) {
    return 'Living World: Off';
  }
  final title = (worldTitle ?? '').trim();
  if (title.isEmpty) return 'Living World: bound';
  return 'Living World: $title';
}
