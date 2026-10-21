import '../models/living_world.dart';
import 'living_world_update_service.dart';

/// One keyword-driven relationship nudge (Phase 7 light systems).
class RelationshipDriftRule {
  const RelationshipDriftRule({
    required this.id,
    required this.keywords,
    required this.delta,
    this.label = '',
  });

  final String id;
  final List<String> keywords;
  final int delta;
  final String label;
}

/// Explicit event-text → flag key recipe (never freeform silent invention).
class FlagRecipe {
  const FlagRecipe({
    required this.id,
    required this.keywords,
    required this.buildKey,
    this.value = true,
  });

  final String id;
  final List<String> keywords;

  /// Build a stable flag key from the event + world, or null to skip.
  final String? Function(WorldEvent event, LivingWorld world) buildKey;
  final Object value;
}

/// Phase 7 light world systems: relationship drift, flag recipes, presence sync.
///
/// All mutations stay schema-validated (ids checked; scores clamped). Nothing
/// invents new people/places.
class LivingWorldSystemsService {
  const LivingWorldSystemsService();

  static const scoreMin = -100;
  static const scoreMax = 100;

  /// Genre-agnostic drift tags — matched against event text (case-insensitive).
  static const driftRules = <RelationshipDriftRule>[
    RelationshipDriftRule(
      id: 'aid',
      keywords: [
        'helped',
        'help ',
        'aided',
        'rescued',
        'saved',
        'supported',
        'backed up',
        'covered for',
      ],
      delta: 8,
      label: 'aid',
    ),
    RelationshipDriftRule(
      id: 'betrayal',
      keywords: [
        'betrayed',
        'betrayal',
        'backstab',
        'sold out',
        'turned on',
        'double-crossed',
      ],
      delta: -20,
      label: 'betrayal',
    ),
    RelationshipDriftRule(
      id: 'promise',
      keywords: [
        'promised',
        'promise',
        'vowed',
        'swore',
        'oath',
        'gave their word',
      ],
      delta: 5,
      label: 'promise',
    ),
    RelationshipDriftRule(
      id: 'deceit',
      keywords: [
        'lied to',
        'deceived',
        'manipulated',
        'tricked',
        'framed',
      ],
      delta: -10,
      label: 'deceit',
    ),
    RelationshipDriftRule(
      id: 'warmth',
      keywords: [
        'thanked',
        'grateful',
        'apologized',
        'forgave',
        'comforted',
      ],
      delta: 4,
      label: 'warmth',
    ),
  ];

  /// Explicit recipes only — keys are derived from known ids, not free prose.
  static final flagRecipes = <FlagRecipe>[
    FlagRecipe(
      id: 'knows',
      keywords: [
        'knows about',
        'learned about',
        'learned that',
        'discovered',
        'found out',
        'was told about',
      ],
      buildKey: (event, world) {
        final person = _primaryPerson(event, world);
        if (person == null) return null;
        return 'knows_${_slug(person.name)}';
      },
    ),
    FlagRecipe(
      id: 'banished',
      keywords: [
        'banished from',
        'exiled from',
        'barred from',
        'forbidden from',
      ],
      buildKey: (event, world) {
        final person = _primaryPerson(event, world);
        final place = _placeForEvent(event, world);
        if (person == null || place == null) return null;
        return 'banished_from_${_slug(place.name)}';
      },
    ),
    FlagRecipe(
      id: 'deceased',
      keywords: [' died', 'is dead', 'was killed', 'was murdered', 'passed away'],
      buildKey: (event, world) {
        final person = _primaryPerson(event, world);
        if (person == null) return null;
        return '${person.id}_deceased';
      },
    ),
  ];

  /// After validated ops land, nudge relationships / set recipe flags from
  /// newly added events. Skips pairs that already got an explicit
  /// [LivingWorldUpdateOp.setRelationship] in the same batch.
  LivingWorld enrichAfterApply({
    required LivingWorld before,
    required LivingWorld after,
    required List<LivingWorldCanonUpdate> applied,
  }) {
    if (applied.isEmpty) return after;

    final newEventIds = <String>{
      for (final u in applied)
        if (u.op == LivingWorldUpdateOp.addEvent && u.event != null)
          u.event!.id,
    };
    if (newEventIds.isEmpty) return after;

    final explicitPairs = <String>{
      for (final u in applied)
        if (u.op == LivingWorldUpdateOp.setRelationship &&
            u.relationship != null)
          _pairKey(u.relationship!.fromId, u.relationship!.toId),
    };

    final newEvents = [
      for (final e in after.events)
        if (newEventIds.contains(e.id)) e,
    ];
    if (newEvents.isEmpty) return after;

    var relationships = List<WorldRelationship>.from(after.relationships);
    var flags = List<WorldFlag>.from(after.flags);

    for (final event in newEvents) {
      relationships = _applyDriftForEvent(
        world: after,
        event: event,
        relationships: relationships,
        skipPairs: explicitPairs,
      );
      flags = _applyFlagRecipesForEvent(
        world: after,
        event: event,
        flags: flags,
      );
    }

    return after
        .copyWith(relationships: relationships, flags: flags)
        .validated();
  }

  /// Match narrator present/arriving names onto people and emit validated
  /// who/where ops (caller applies + saves). Departures use [clearDeparted].
  List<LivingWorldCanonUpdate> presenceOpsFromNarrator({
    required LivingWorld world,
    required Set<String> presentNames,
    required Set<String> arrivingNames,
    String? activePlaceId,
  }) {
    final placeIds = {for (final p in world.places) p.id};
    final active =
        (activePlaceId ?? world.liveState?.activePlaceId ?? '').trim();
    final resolvedActive =
        active.isNotEmpty && placeIds.contains(active) ? active : null;

    final out = <LivingWorldCanonUpdate>[];
    final seenPeople = <String>{};

    void locate(String personId, String placeId, String summary) {
      if (seenPeople.contains(personId)) return;
      if (!placeIds.contains(placeId)) return;
      seenPeople.add(personId);
      out.add(
        LivingWorldCanonUpdate(
          op: LivingWorldUpdateOp.setPersonLocation,
          summary: summary,
          personId: personId,
          placeId: placeId,
        ),
      );
    }

    if (resolvedActive != null &&
        world.liveState?.activePlaceId != resolvedActive) {
      out.add(
        LivingWorldCanonUpdate(
          op: LivingWorldUpdateOp.setActivePlace,
          summary: 'Active place → ${_placeName(world, resolvedActive)}',
          activePlaceId: resolvedActive,
        ),
      );
    }

    if (resolvedActive != null) {
      for (final name in arrivingNames) {
        final person = _matchPerson(world.people, name);
        if (person == null) continue;
        locate(
          person.id,
          resolvedActive,
          '${person.name} arrives @ ${_placeName(world, resolvedActive)}',
        );
      }
      for (final name in presentNames) {
        final person = _matchPerson(world.people, name);
        if (person == null) continue;
        final current = world.liveState?.personLocations[person.id];
        if (current == resolvedActive) continue;
        locate(
          person.id,
          resolvedActive,
          '${person.name} @ ${_placeName(world, resolvedActive)} (scene)',
        );
      }
    }

    return out;
  }

  /// Resolve departed display names → person ids that currently have a location.
  Set<String> resolveDepartedPersonIds({
    required LivingWorld world,
    required Set<String> departedNames,
  }) {
    final out = <String>{};
    for (final name in departedNames) {
      final person = _matchPerson(world.people, name);
      if (person == null) continue;
      if (world.liveState?.personLocations.containsKey(person.id) == true) {
        out.add(person.id);
      }
    }
    return out;
  }

  /// Remove leavers from [WorldLiveState.personLocations] (validated ids only).
  LivingWorld clearDeparted({
    required LivingWorld world,
    required Set<String> departedPersonIds,
  }) {
    if (departedPersonIds.isEmpty || world.liveState == null) return world;
    final personIds = {for (final p in world.people) p.id};
    final clearIds = {
      for (final id in departedPersonIds)
        if (personIds.contains(id)) id,
    };
    if (clearIds.isEmpty) return world;

    final live = world.liveState!;
    final nextLocations = <String, String>{
      for (final e in live.personLocations.entries)
        if (!clearIds.contains(e.key)) e.key: e.value,
    };
    return world
        .copyWith(liveState: live.copyWith(personLocations: nextLocations))
        .validated();
  }

  List<WorldRelationship> _applyDriftForEvent({
    required LivingWorld world,
    required WorldEvent event,
    required List<WorldRelationship> relationships,
    required Set<String> skipPairs,
  }) {
    final ids = [
      for (final id in event.personIds)
        if (world.people.any((p) => p.id == id)) id,
    ];
    if (ids.length < 2) return relationships;

    final text = ' ${event.text.toLowerCase()} ';
    final matched = <RelationshipDriftRule>[];
    for (final rule in driftRules) {
      for (final kw in rule.keywords) {
        if (text.contains(kw.toLowerCase())) {
          matched.add(rule);
          break;
        }
      }
    }
    if (matched.isEmpty) return relationships;

    // Sum deltas if multiple tags hit (still clamped later).
    var delta = 0;
    final labels = <String>{};
    for (final rule in matched) {
      delta += rule.delta;
      if (rule.label.isNotEmpty) labels.add(rule.label);
    }
    if (delta == 0 && labels.isEmpty) return relationships;

    var rels = List<WorldRelationship>.from(relationships);
    for (var i = 0; i < ids.length; i++) {
      for (var j = 0; j < ids.length; j++) {
        if (i == j) continue;
        final fromId = ids[i];
        final toId = ids[j];
        if (skipPairs.contains(_pairKey(fromId, toId))) continue;
        rels = _nudgeRelationship(
          relationships: rels,
          fromId: fromId,
          toId: toId,
          delta: delta,
          extraLabels: labels.toList(),
        );
      }
    }
    return rels;
  }

  List<WorldRelationship> _nudgeRelationship({
    required List<WorldRelationship> relationships,
    required String fromId,
    required String toId,
    required int delta,
    required List<String> extraLabels,
  }) {
    final idx = relationships.indexWhere(
      (r) => r.fromId == fromId && r.toId == toId,
    );
    if (idx >= 0) {
      final cur = relationships[idx];
      final mergedLabels = <String>{
        ...cur.labels,
        ...extraLabels,
      }.toList();
      final next = List<WorldRelationship>.from(relationships);
      next[idx] = cur.copyWith(
        score: (cur.score + delta).clamp(scoreMin, scoreMax),
        labels: mergedLabels,
      );
      return next;
    }
    return [
      ...relationships,
      WorldRelationship(
        fromId: fromId,
        toId: toId,
        score: delta.clamp(scoreMin, scoreMax),
        labels: extraLabels,
      ),
    ];
  }

  List<WorldFlag> _applyFlagRecipesForEvent({
    required LivingWorld world,
    required WorldEvent event,
    required List<WorldFlag> flags,
  }) {
    final text = ' ${event.text.toLowerCase()} ';
    var out = List<WorldFlag>.from(flags);
    for (final recipe in flagRecipes) {
      var hit = false;
      for (final kw in recipe.keywords) {
        if (text.contains(kw.toLowerCase())) {
          hit = true;
          break;
        }
      }
      if (!hit) continue;
      final key = recipe.buildKey(event, world)?.trim() ?? '';
      if (key.isEmpty) continue;
      // Reject keys that somehow aren't id-safe.
      if (!RegExp(r'^[a-z0-9_]+$').hasMatch(key)) continue;
      final flag = WorldFlag(
        id: 'f_$key',
        key: key,
        value: recipe.value,
      );
      final idx = out.indexWhere(
        (f) => f.key.toLowerCase() == key.toLowerCase(),
      );
      if (idx >= 0) {
        out = List<WorldFlag>.from(out)..[idx] = flag;
      } else {
        out = [...out, flag];
      }
    }
    return out;
  }

  static String _pairKey(String a, String b) => '$a>$b';

  static String _slug(String raw) {
    final s = raw
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    return s.isEmpty ? 'unknown' : s;
  }

  static WorldPerson? _primaryPerson(WorldEvent event, LivingWorld world) {
    for (final id in event.personIds) {
      for (final p in world.people) {
        if (p.id == id) return p;
      }
    }
    // Fallback: first person name mentioned in text.
    final lower = event.text.toLowerCase();
    for (final p in world.people) {
      if (lower.contains(p.name.toLowerCase())) return p;
    }
    return null;
  }

  static WorldPlace? _placeForEvent(WorldEvent event, LivingWorld world) {
    final placeId = event.placeId;
    if (placeId != null) {
      for (final p in world.places) {
        if (p.id == placeId) return p;
      }
    }
    final lower = event.text.toLowerCase();
    for (final p in world.places) {
      if (lower.contains(p.name.toLowerCase())) return p;
    }
    return null;
  }

  static WorldPerson? _matchPerson(List<WorldPerson> people, String name) {
    final n = name.trim().toLowerCase();
    if (n.length < 2) return null;
    for (final p in people) {
      final pn = p.name.trim().toLowerCase();
      if (pn == n || pn.contains(n) || n.contains(pn)) return p;
    }
    return null;
  }

  static String _placeName(LivingWorld world, String placeId) {
    for (final p in world.places) {
      if (p.id == placeId) return p.name;
    }
    return placeId;
  }
}
