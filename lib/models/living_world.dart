/// One playable world notebook (people, places, relationships, events, flags).
///
/// Structured Living World canon — genre-agnostic (no fantasy/dwarf assumptions).
/// Schema version [LivingWorld.currentSchemaVersion] — bump when fields change.
class LivingWorld {
  const LivingWorld({
    required this.id,
    required this.title,
    this.schemaVersion = currentSchemaVersion,
    this.genreNote = '',
    this.people = const [],
    this.places = const [],
    this.relationships = const [],
    this.events = const [],
    this.flags = const [],
    this.liveState,
  });

  static const currentSchemaVersion = 1;

  final String id;
  final String title;

  /// Free-text setting note (optional). Not an enum.
  final String genreNote;
  final int schemaVersion;
  final List<WorldPerson> people;
  final List<WorldPlace> places;
  final List<WorldRelationship> relationships;
  final List<WorldEvent> events;
  final List<WorldFlag> flags;

  /// Optional light live state — door to Phase B (who/where now).
  final WorldLiveState? liveState;

  LivingWorld copyWith({
    String? id,
    String? title,
    int? schemaVersion,
    String? genreNote,
    List<WorldPerson>? people,
    List<WorldPlace>? places,
    List<WorldRelationship>? relationships,
    List<WorldEvent>? events,
    List<WorldFlag>? flags,
    WorldLiveState? liveState,
    bool clearLiveState = false,
  }) {
    return LivingWorld(
      id: id ?? this.id,
      title: title ?? this.title,
      schemaVersion: schemaVersion ?? this.schemaVersion,
      genreNote: genreNote ?? this.genreNote,
      people: people ?? this.people,
      places: places ?? this.places,
      relationships: relationships ?? this.relationships,
      events: events ?? this.events,
      flags: flags ?? this.flags,
      liveState: clearLiveState ? null : (liveState ?? this.liveState),
    );
  }

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'id': id,
        'title': title,
        if (genreNote.trim().isNotEmpty) 'genreNote': genreNote.trim(),
        'people': people.map((p) => p.toJson()).toList(),
        'places': places.map((p) => p.toJson()).toList(),
        'relationships': relationships.map((r) => r.toJson()).toList(),
        'events': events.map((e) => e.toJson()).toList(),
        'flags': flags.map((f) => f.toJson()).toList(),
        if (liveState != null) 'liveState': liveState!.toJson(),
      };

  /// Parse and validate. Throws [FormatException] on hard failures.
  factory LivingWorld.fromJson(Map<String, dynamic> json) {
    final id = '${json['id'] ?? ''}'.trim();
    if (id.isEmpty) {
      throw const FormatException('Living World needs a non-empty id.');
    }
    final title = '${json['title'] ?? ''}'.trim();
    if (title.isEmpty) {
      throw const FormatException('Living World needs a non-empty title.');
    }

    final versionRaw = json['schemaVersion'];
    final version = versionRaw is int
        ? versionRaw
        : int.tryParse('$versionRaw') ?? currentSchemaVersion;
    if (version < 1 || version > currentSchemaVersion) {
      throw FormatException(
        'Unsupported Living World schema version $version '
        '(this app supports 1–$currentSchemaVersion).',
      );
    }

    final people = _mapList(json['people'], WorldPerson.fromJson);
    final places = _mapList(json['places'], WorldPlace.fromJson);
    final relationships =
        _mapList(json['relationships'], WorldRelationship.fromJson);
    final events = _mapList(json['events'], WorldEvent.fromJson);
    final flags = _mapList(json['flags'], WorldFlag.fromJson);

    WorldLiveState? liveState;
    final rawLive = json['liveState'];
    if (rawLive is Map) {
      liveState = WorldLiveState.fromJson(Map<String, dynamic>.from(rawLive));
    }

    final world = LivingWorld(
      id: id,
      title: title,
      schemaVersion: version,
      genreNote: '${json['genreNote'] ?? ''}'.trim(),
      people: people,
      places: places,
      relationships: relationships,
      events: events,
      flags: flags,
      liveState: liveState,
    );
    return world.validated();
  }

  /// Soft-validate ids and clamp scores. Drops broken links quietly.
  LivingWorld validated() {
    final personIds = {for (final p in people) if (p.id.isNotEmpty) p.id};
    final placeIds = {for (final p in places) if (p.id.isNotEmpty) p.id};

    final cleanPeople = [
      for (final p in people)
        if (p.id.isNotEmpty && p.name.trim().isNotEmpty) p,
    ];
    final cleanPlaces = [
      for (final p in places)
        if (p.id.isNotEmpty && p.name.trim().isNotEmpty)
          p.copyWith(
            connectedPlaceIds: [
              for (final id in p.connectedPlaceIds)
                if (placeIds.contains(id) && id != p.id) id,
            ],
          ),
    ];
    final cleanRels = [
      for (final r in relationships)
        if (personIds.contains(r.fromId) && personIds.contains(r.toId))
          r.copyWith(score: r.score.clamp(-100, 100)),
    ];
    final cleanEvents = [
      for (final e in events)
        if (e.id.isNotEmpty && e.text.trim().isNotEmpty)
          e.copyWith(
            placeId: e.placeId != null && placeIds.contains(e.placeId)
                ? e.placeId
                : null,
            personIds: [
              for (final id in e.personIds)
                if (personIds.contains(id)) id,
            ],
          ),
    ];
    final cleanFlags = [
      for (final f in flags)
        if (f.id.isNotEmpty && f.key.trim().isNotEmpty) f,
    ];

    WorldLiveState? live = liveState;
    if (live != null) {
      final active = live.activePlaceId;
      live = live.copyWith(
        clearActivePlace: active != null && !placeIds.contains(active),
        activePlaceId:
            active != null && placeIds.contains(active) ? active : null,
        personLocations: {
          for (final entry in live.personLocations.entries)
            if (personIds.contains(entry.key) && placeIds.contains(entry.value))
              entry.key: entry.value,
        },
      );
      if (live.activePlaceId == null && live.personLocations.isEmpty) {
        live = null;
      }
    }

    return LivingWorld(
      id: id,
      title: title,
      schemaVersion: schemaVersion,
      genreNote: genreNote,
      people: cleanPeople,
      places: cleanPlaces,
      relationships: cleanRels,
      events: cleanEvents,
      flags: cleanFlags,
      liveState: live,
    );
  }

  static String newId() => 'world_${DateTime.now().millisecondsSinceEpoch}';

  /// Empty notebook ready to fill (or use as a stub).
  factory LivingWorld.empty({required String title}) {
    return LivingWorld(
      id: newId(),
      title: title.trim().isEmpty ? 'Untitled world' : title.trim(),
    );
  }
}

class WorldPerson {
  const WorldPerson({
    required this.id,
    required this.name,
    this.summary = '',
    this.personalityNotes = '',
    this.routineHints = '',
    this.characterCardId,
  });

  final String id;
  final String name;
  final String summary;
  final String personalityNotes;

  /// Soft schedule / time-of-day habits (Phase 7) — not a full calendar sim.
  /// Example: "mornings at the pier; evenings at the inn".
  final String routineHints;

  /// Optional link to an Anima character card id.
  final String? characterCardId;

  WorldPerson copyWith({
    String? id,
    String? name,
    String? summary,
    String? personalityNotes,
    String? routineHints,
    String? characterCardId,
    bool clearCharacterCardId = false,
  }) {
    return WorldPerson(
      id: id ?? this.id,
      name: name ?? this.name,
      summary: summary ?? this.summary,
      personalityNotes: personalityNotes ?? this.personalityNotes,
      routineHints: routineHints ?? this.routineHints,
      characterCardId: clearCharacterCardId
          ? null
          : (characterCardId ?? this.characterCardId),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (summary.trim().isNotEmpty) 'summary': summary.trim(),
        if (personalityNotes.trim().isNotEmpty)
          'personalityNotes': personalityNotes.trim(),
        if (routineHints.trim().isNotEmpty)
          'routineHints': routineHints.trim(),
        if (characterCardId != null && characterCardId!.trim().isNotEmpty)
          'characterCardId': characterCardId!.trim(),
      };

  factory WorldPerson.fromJson(Map<String, dynamic> json) {
    final id = '${json['id'] ?? ''}'.trim();
    final name = '${json['name'] ?? ''}'.trim();
    if (id.isEmpty || name.isEmpty) {
      throw const FormatException('World person needs id and name.');
    }
    final card = '${json['characterCardId'] ?? ''}'.trim();
    return WorldPerson(
      id: id,
      name: name,
      summary: '${json['summary'] ?? ''}'.trim(),
      personalityNotes: '${json['personalityNotes'] ?? ''}'.trim(),
      routineHints: '${json['routineHints'] ?? ''}'.trim(),
      characterCardId: card.isEmpty ? null : card,
    );
  }
}

class WorldPlace {
  const WorldPlace({
    required this.id,
    required this.name,
    this.description = '',
    this.connectedPlaceIds = const [],
  });

  final String id;
  final String name;
  final String description;
  final List<String> connectedPlaceIds;

  WorldPlace copyWith({
    String? id,
    String? name,
    String? description,
    List<String>? connectedPlaceIds,
  }) {
    return WorldPlace(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      connectedPlaceIds: connectedPlaceIds ?? this.connectedPlaceIds,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (description.trim().isNotEmpty) 'description': description.trim(),
        if (connectedPlaceIds.isNotEmpty) 'connectedPlaceIds': connectedPlaceIds,
      };

  factory WorldPlace.fromJson(Map<String, dynamic> json) {
    final id = '${json['id'] ?? ''}'.trim();
    final name = '${json['name'] ?? ''}'.trim();
    if (id.isEmpty || name.isEmpty) {
      throw const FormatException('World place needs id and name.');
    }
    final connected = <String>[];
    final raw = json['connectedPlaceIds'];
    if (raw is List) {
      for (final item in raw) {
        final v = '$item'.trim();
        if (v.isNotEmpty) connected.add(v);
      }
    }
    return WorldPlace(
      id: id,
      name: name,
      description: '${json['description'] ?? ''}'.trim(),
      connectedPlaceIds: connected,
    );
  }
}

class WorldRelationship {
  const WorldRelationship({
    required this.fromId,
    required this.toId,
    this.score = 0,
    this.labels = const [],
  });

  final String fromId;
  final String toId;

  /// Sentiment −100…100 (door to live updates in Phase B).
  final int score;
  final List<String> labels;

  WorldRelationship copyWith({
    String? fromId,
    String? toId,
    int? score,
    List<String>? labels,
  }) {
    return WorldRelationship(
      fromId: fromId ?? this.fromId,
      toId: toId ?? this.toId,
      score: score ?? this.score,
      labels: labels ?? this.labels,
    );
  }

  Map<String, dynamic> toJson() => {
        'fromId': fromId,
        'toId': toId,
        'score': score.clamp(-100, 100),
        if (labels.isNotEmpty) 'labels': labels,
      };

  factory WorldRelationship.fromJson(Map<String, dynamic> json) {
    final fromId = '${json['fromId'] ?? ''}'.trim();
    final toId = '${json['toId'] ?? ''}'.trim();
    if (fromId.isEmpty || toId.isEmpty) {
      throw const FormatException('Relationship needs fromId and toId.');
    }
    final scoreRaw = json['score'];
    final score = scoreRaw is int
        ? scoreRaw
        : int.tryParse('$scoreRaw') ?? 0;
    final labels = <String>[];
    final rawLabels = json['labels'];
    if (rawLabels is List) {
      for (final item in rawLabels) {
        final v = '$item'.trim();
        if (v.isNotEmpty) labels.add(v);
      }
    }
    return WorldRelationship(
      fromId: fromId,
      toId: toId,
      score: score.clamp(-100, 100),
      labels: labels,
    );
  }
}

class WorldEvent {
  const WorldEvent({
    required this.id,
    required this.text,
    this.at,
    this.placeId,
    this.personIds = const [],
  });

  final String id;
  final String text;

  /// Free-form turn stamp or ISO-ish time string (optional).
  final String? at;
  final String? placeId;
  final List<String> personIds;

  WorldEvent copyWith({
    String? id,
    String? text,
    String? at,
    bool clearAt = false,
    String? placeId,
    bool clearPlaceId = false,
    List<String>? personIds,
  }) {
    return WorldEvent(
      id: id ?? this.id,
      text: text ?? this.text,
      at: clearAt ? null : (at ?? this.at),
      placeId: clearPlaceId ? null : (placeId ?? this.placeId),
      personIds: personIds ?? this.personIds,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        if (at != null && at!.trim().isNotEmpty) 'at': at!.trim(),
        if (placeId != null && placeId!.trim().isNotEmpty) 'placeId': placeId,
        if (personIds.isNotEmpty) 'personIds': personIds,
      };

  factory WorldEvent.fromJson(Map<String, dynamic> json) {
    final id = '${json['id'] ?? ''}'.trim();
    final text = '${json['text'] ?? ''}'.trim();
    if (id.isEmpty || text.isEmpty) {
      throw const FormatException('World event needs id and text.');
    }
    final at = '${json['at'] ?? ''}'.trim();
    final placeId = '${json['placeId'] ?? ''}'.trim();
    final personIds = <String>[];
    final raw = json['personIds'];
    if (raw is List) {
      for (final item in raw) {
        final v = '$item'.trim();
        if (v.isNotEmpty) personIds.add(v);
      }
    }
    return WorldEvent(
      id: id,
      text: text,
      at: at.isEmpty ? null : at,
      placeId: placeId.isEmpty ? null : placeId,
      personIds: personIds,
    );
  }
}

class WorldFlag {
  const WorldFlag({
    required this.id,
    required this.key,
    this.value = true,
  });

  final String id;
  final String key;

  /// Bool or short enum/string fact.
  final Object value;

  Map<String, dynamic> toJson() => {
        'id': id,
        'key': key,
        'value': value,
      };

  factory WorldFlag.fromJson(Map<String, dynamic> json) {
    final id = '${json['id'] ?? ''}'.trim();
    final key = '${json['key'] ?? ''}'.trim();
    if (id.isEmpty || key.isEmpty) {
      throw const FormatException('World flag needs id and key.');
    }
    final raw = json['value'];
    final Object value;
    if (raw is bool || raw is num || raw is String) {
      value = raw as Object;
    } else if (raw == null) {
      value = true;
    } else {
      value = '$raw';
    }
    return WorldFlag(id: id, key: key, value: value);
  }
}

/// Optional live scene state — kept for Phase B without requiring it in A.
class WorldLiveState {
  const WorldLiveState({
    this.activePlaceId,
    this.personLocations = const {},
  });

  final String? activePlaceId;

  /// personId → placeId
  final Map<String, String> personLocations;

  WorldLiveState copyWith({
    String? activePlaceId,
    bool clearActivePlace = false,
    Map<String, String>? personLocations,
  }) {
    return WorldLiveState(
      activePlaceId:
          clearActivePlace ? null : (activePlaceId ?? this.activePlaceId),
      personLocations: personLocations ?? this.personLocations,
    );
  }

  Map<String, dynamic> toJson() => {
        if (activePlaceId != null && activePlaceId!.isNotEmpty)
          'activePlaceId': activePlaceId,
        if (personLocations.isNotEmpty) 'personLocations': personLocations,
      };

  factory WorldLiveState.fromJson(Map<String, dynamic> json) {
    final active = '${json['activePlaceId'] ?? ''}'.trim();
    final locations = <String, String>{};
    final raw = json['personLocations'];
    if (raw is Map) {
      for (final entry in raw.entries) {
        final k = '${entry.key}'.trim();
        final v = '${entry.value}'.trim();
        if (k.isNotEmpty && v.isNotEmpty) locations[k] = v;
      }
    }
    return WorldLiveState(
      activePlaceId: active.isEmpty ? null : active,
      personLocations: locations,
    );
  }
}

/// Lightweight list row (no full notebook load).
class LivingWorldSummary {
  const LivingWorldSummary({
    required this.id,
    required this.title,
    this.personCount = 0,
    this.placeCount = 0,
  });

  final String id;
  final String title;
  final int personCount;
  final int placeCount;
}

List<T> _mapList<T>(
  Object? raw,
  T Function(Map<String, dynamic> json) parse,
) {
  if (raw is! List) return const [];
  final out = <T>[];
  for (final item in raw) {
    if (item is! Map) continue;
    try {
      out.add(parse(Map<String, dynamic>.from(item)));
    } on FormatException {
      // Skip malformed rows rather than failing the whole world.
    }
  }
  return out;
}
