import '../models/living_world.dart';
import '../models/living_world_tick_settings.dart';
import 'living_world_update_service.dart';

/// Result of planning one near-scene tick (Phase 8) — ops not yet applied.
class LivingWorldTickPlan {
  const LivingWorldTickPlan({
    required this.ops,
    required this.placeIdsInRadius,
    required this.peopleTouched,
    this.seedPlaceId,
  });

  final List<LivingWorldCanonUpdate> ops;
  final Set<String> placeIdsInRadius;
  final Set<String> peopleTouched;
  final String? seedPlaceId;

  bool get isEmpty => ops.isEmpty;

  static const empty = LivingWorldTickPlan(
    ops: [],
    placeIdsInRadius: {},
    peopleTouched: {},
  );
}

/// Story-local near-scene simulation — tiny ticks around the active place.
///
/// Rules-first (no API required). Outputs only validated typed ops; never dumps
/// full person card prose into events or prompts. Off-screen people may get a
/// short ambient event line or a soft who/where nudge from [routineHints].
class LivingWorldSimulator {
  const LivingWorldSimulator();

  static const defaultMaxPeople = 6;
  static const defaultMaxOps = 8;
  static const defaultRadiusHops = 1;
  static const defaultLastEventCount = 8;

  /// Hard ceiling even if settings ask for more (API / spam budget).
  static const hardMaxOps = 12;
  static const hardMaxPeople = 12;

  /// Places within [radiusHops] of [seedPlaceId], walking [connectedPlaceIds]
  /// in both directions (links may be one-way in notebooks).
  Set<String> placesInRadius(
    LivingWorld world, {
    required String seedPlaceId,
    int radiusHops = defaultRadiusHops,
  }) {
    final hops = radiusHops.clamp(0, 2);
    final placeIds = {for (final p in world.places) if (p.id.isNotEmpty) p.id};
    if (!placeIds.contains(seedPlaceId)) return {};

    // Undirected adjacency from possibly one-way connectedPlaceIds.
    final neighbors = <String, Set<String>>{
      for (final id in placeIds) id: <String>{},
    };
    for (final place in world.places) {
      for (final other in place.connectedPlaceIds) {
        if (!placeIds.contains(other) || other == place.id) continue;
        neighbors[place.id]!.add(other);
        neighbors[other]!.add(place.id);
      }
    }

    final out = <String>{seedPlaceId};
    var frontier = <String>{seedPlaceId};
    for (var i = 0; i < hops; i++) {
      final next = <String>{};
      for (final id in frontier) {
        next.addAll(neighbors[id] ?? const {});
      }
      next.removeAll(out);
      if (next.isEmpty) break;
      out.addAll(next);
      frontier = next;
    }
    return out;
  }

  /// Resolve the scene center: active place, else densest location, else first.
  String? resolveSeedPlaceId(LivingWorld world) {
    final live = world.liveState;
    final active = live?.activePlaceId?.trim();
    if (active != null &&
        active.isNotEmpty &&
        world.places.any((p) => p.id == active)) {
      return active;
    }

    final locs = live?.personLocations ?? const <String, String>{};
    if (locs.isNotEmpty) {
      final counts = <String, int>{};
      for (final placeId in locs.values) {
        counts[placeId] = (counts[placeId] ?? 0) + 1;
      }
      final ranked = counts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      if (ranked.isNotEmpty) return ranked.first.key;
    }

    if (world.places.isNotEmpty) return world.places.first.id;
    return null;
  }

  /// Plan a near-scene tick. Empty when unbound-style worlds have no places /
  /// no seed, or nothing useful to do under caps.
  LivingWorldTickPlan planTick(
    LivingWorld world, {
    LivingWorldTickSettings settings = LivingWorldTickSettings.defaults,
    int? maxPeople,
    int? maxOps,
    int? radiusHops,
    int? lastEventCount,
    DateTime? now,
  }) {
    final capped = settings.clamped();
    final peopleCap =
        (maxPeople ?? capped.maxPeople).clamp(1, hardMaxPeople);
    final opsCap = (maxOps ?? capped.maxOps).clamp(1, hardMaxOps);
    final hops = (radiusHops ?? capped.radiusHops).clamp(0, 2);
    final eventWindow =
        (lastEventCount ?? capped.lastEventCount).clamp(2, 20);

    final seed = resolveSeedPlaceId(world);
    if (seed == null) return LivingWorldTickPlan.empty;

    final radius = placesInRadius(
      world,
      seedPlaceId: seed,
      radiusHops: hops,
    );
    if (radius.isEmpty) return LivingWorldTickPlan.empty;

    final placesById = {for (final p in world.places) p.id: p};
    final peopleById = {for (final p in world.people) p.id: p};
    final live = world.liveState;
    final recent = world.events.length <= eventWindow
        ? world.events
        : world.events.sublist(world.events.length - eventWindow);

    // People already featured in the very latest events — skip ambient spam.
    final recentlyActive = <String>{};
    final tail = recent.length <= 3
        ? recent
        : recent.sublist(recent.length - 3);
    for (final e in tail) {
      recentlyActive.addAll(e.personIds);
    }

    final scored = <({String id, int score})>[];
    for (final person in world.people) {
      var score = 0;
      final at = live?.personLocations[person.id];
      if (at != null && radius.contains(at)) {
        score += 40;
        if (at == seed) score += 20;
      }
      for (final e in recent) {
        if (e.personIds.contains(person.id)) {
          score += 15;
          final ep = e.placeId;
          if (ep != null && radius.contains(ep)) score += 10;
        }
      }
      if (person.routineHints.trim().isNotEmpty) score += 12;
      if (score > 0) scored.add((id: person.id, score: score));
    }
    scored.sort((a, b) => b.score.compareTo(a.score));

    final selectedIds = <String>[
      for (final row in scored.take(peopleCap)) row.id,
    ];
    if (selectedIds.isEmpty) {
      return LivingWorldTickPlan(
        ops: const [],
        placeIdsInRadius: radius,
        peopleTouched: {},
        seedPlaceId: seed,
      );
    }

    final stamp = now ?? DateTime.now();
    final ops = <LivingWorldCanonUpdate>[];
    final touched = <String>{};

    // Soft who/where: if routineHints name a connected place and they are not
    // already there / not at the active scene, nudge them toward that place.
    for (final personId in selectedIds) {
      if (ops.length >= opsCap) break;
      final person = peopleById[personId];
      if (person == null) continue;
      final hintPlace = _placeNamedInHints(
        person.routineHints,
        placesById,
        preferIds: radius,
      );
      if (hintPlace == null || !radius.contains(hintPlace)) continue;
      final current = live?.personLocations[personId];
      if (current == hintPlace) continue;
      // Don't yank someone off the active scene mid-tick.
      if (current == seed) continue;
      ops.add(
        LivingWorldCanonUpdate(
          op: LivingWorldUpdateOp.setPersonLocation,
          summary: '${person.name} → ${placesById[hintPlace]?.name ?? hintPlace}',
          personId: personId,
          placeId: hintPlace,
        ),
      );
      touched.add(personId);
    }

    // Short ambient events for near-scene (often off-active) people.
    for (final personId in selectedIds) {
      if (ops.length >= opsCap) break;
      final person = peopleById[personId];
      if (person == null) continue;
      if (recentlyActive.contains(personId) && touched.contains(personId)) {
        continue;
      }
      if (recentlyActive.contains(personId) &&
          live?.personLocations[personId] == seed) {
        // On-scene and already in recent events — leave them to chat extract.
        continue;
      }

      final at = live?.personLocations[personId];
      final placeId = (at != null && radius.contains(at))
          ? at
          : seed;
      final placeName = placesById[placeId]?.name ?? 'nearby';
      final line = _ambientEventLine(person, placeName);
      if (_recentEventLooksLike(recent, personId, line)) continue;

      final event = WorldEvent(
        id: 'e_tick_${stamp.microsecondsSinceEpoch}_$personId',
        text: line,
        at: 'tick-${stamp.millisecondsSinceEpoch}',
        placeId: placeId,
        personIds: [personId],
      );
      ops.add(
        LivingWorldCanonUpdate(
          op: LivingWorldUpdateOp.addEvent,
          summary: line,
          event: event,
        ),
      );
      touched.add(personId);
    }

    // Cap people touched to the plan's selected set (ops may already be capped).
    final cappedOps = ops.take(opsCap).toList();
    final peopleFromOps = <String>{};
    for (final op in cappedOps) {
      if (op.personId != null) peopleFromOps.add(op.personId!);
      final ids = op.event?.personIds;
      if (ids != null) peopleFromOps.addAll(ids);
    }

    return LivingWorldTickPlan(
      ops: cappedOps,
      placeIdsInRadius: radius,
      peopleTouched: peopleFromOps,
      seedPlaceId: seed,
    );
  }

  /// Near-scene subset for any future AI-assisted tick prompt — names + ids +
  /// short routine only (never full summary / personality dumps).
  String formatNearSceneRoster(LivingWorld world, LivingWorldTickPlan plan) {
    if (plan.placeIdsInRadius.isEmpty) return '(no near-scene places)';
    final placesById = {for (final p in world.places) p.id: p};
    final peopleById = {for (final p in world.people) p.id: p};
    final live = world.liveState;

    final placeLines = [
      for (final id in plan.placeIdsInRadius)
        if (placesById[id] != null)
          '- ${placesById[id]!.name} ($id)'
              '${id == plan.seedPlaceId ? ' [active]' : ''}',
    ];

    final personLines = <String>[];
    final ids = plan.peopleTouched.isNotEmpty
        ? plan.peopleTouched
        : {
            for (final p in world.people)
              if (live?.personLocations[p.id] != null &&
                  plan.placeIdsInRadius
                      .contains(live!.personLocations[p.id]))
                p.id,
          };
    for (final id in ids) {
      final p = peopleById[id];
      if (p == null) continue;
      final at = live?.personLocations[id];
      final atName = at == null ? '?' : (placesById[at]?.name ?? at);
      final routine = p.routineHints.trim();
      final routineBit = routine.isEmpty
          ? ''
          : ' routine: ${_truncate(routine, 60)}';
      personLines.add('- ${p.name} ($id) @ $atName$routineBit');
    }

    return 'Places:\n${placeLines.join('\n')}\n'
        'People:\n${personLines.isEmpty ? '(none)' : personLines.join('\n')}';
  }

  String? _placeNamedInHints(
    String hints,
    Map<String, WorldPlace> placesById, {
    required Set<String> preferIds,
  }) {
    final lower = hints.toLowerCase();
    if (lower.trim().isEmpty) return null;

    // Prefer places inside the radius whose name appears in the hint.
    WorldPlace? best;
    var bestLen = 0;
    for (final id in preferIds) {
      final place = placesById[id];
      if (place == null) continue;
      final name = place.name.trim();
      if (name.length < 3) continue;
      if (!lower.contains(name.toLowerCase())) continue;
      if (name.length > bestLen) {
        best = place;
        bestLen = name.length;
      }
    }
    if (best != null) return best.id;

    // Fall back to any place name mentioned.
    for (final place in placesById.values) {
      final name = place.name.trim();
      if (name.length < 3) continue;
      if (lower.contains(name.toLowerCase())) return place.id;
    }
    return null;
  }

  String _ambientEventLine(WorldPerson person, String placeName) {
    final routine = person.routineHints.trim();
    if (routine.isNotEmpty) {
      final clause = routine.split(RegExp(r'[;.]')).first.trim();
      if (clause.isNotEmpty) {
        return '${person.name} continues nearby (${_truncate(clause, 72)}).';
      }
    }
    return '${person.name} stays occupied near $placeName.';
  }

  bool _recentEventLooksLike(
    List<WorldEvent> recent,
    String personId,
    String line,
  ) {
    final needle = line.toLowerCase();
    for (final e in recent) {
      if (!e.personIds.contains(personId)) continue;
      final t = e.text.toLowerCase();
      if (t == needle) return true;
      if (t.contains('continues nearby') || t.contains('stays occupied near')) {
        return true;
      }
    }
    return false;
  }

  static String _truncate(String text, int max) {
    final t = text.trim();
    if (t.length <= max) return t;
    return '${t.substring(0, max - 1).trimRight()}…';
  }
}
