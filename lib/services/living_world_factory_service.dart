import 'dart:convert';

import '../models/living_world.dart';

/// One compile step in the Living World factory (not Creation Center chat).
enum LivingWorldFactoryPass {
  outline,
  places,
  people,
  relationships,
  seedCanon,
}

extension LivingWorldFactoryPassLabel on LivingWorldFactoryPass {
  String get label => switch (this) {
    LivingWorldFactoryPass.outline => 'Outline',
    LivingWorldFactoryPass.places => 'Places',
    LivingWorldFactoryPass.people => 'People',
    LivingWorldFactoryPass.relationships => 'Relationships',
    LivingWorldFactoryPass.seedCanon => 'Events & continuity',
  };

  String get progressVerb => switch (this) {
    LivingWorldFactoryPass.outline => 'Sketching the world…',
    LivingWorldFactoryPass.places => 'Drafting places…',
    LivingWorldFactoryPass.people => 'Drafting people…',
    LivingWorldFactoryPass.relationships => 'Linking relationships…',
    LivingWorldFactoryPass.seedCanon => 'Seeding events & continuity…',
  };
}

/// People are drafted in small batches so NanoGPT does not truncate mid-JSON.
const int kLivingWorldFactoryPeopleBatchSize = 8;

/// Inputs for a multi-pass world compile.
class LivingWorldFactoryRequest {
  const LivingWorldFactoryRequest({
    required this.brainstorm,
    this.targetPlaceCount = 8,
    this.targetPersonCount = 24,
  });

  /// Free-text pitch from the owner (setting, tone, cast size hints, etc.).
  final String brainstorm;

  final int targetPlaceCount;
  final int targetPersonCount;

  int get clampedPlaces => targetPlaceCount.clamp(3, 20);
  int get clampedPeople => targetPersonCount.clamp(6, 50);

  /// One-way seed from Creation Center workshop prose (does not sync back).
  ///
  /// [characterLines] are short "Name — summary" snippets from linked cards.
  /// [personaLine] is an optional "Name — summary" for the linked player persona.
  static String brainstormFromWorkshop({
    required String title,
    String worldSummary = '',
    List<String> characterLines = const [],
    String personaLine = '',
  }) {
    final buf = StringBuffer();
    final t = title.trim();
    if (t.isNotEmpty) buf.writeln('Workshop title: $t');
    final summary = worldSummary.trim();
    if (summary.isNotEmpty) {
      if (buf.isNotEmpty) buf.writeln();
      buf.writeln(summary);
    }
    final persona = personaLine.trim();
    if (persona.isNotEmpty) {
      if (buf.isNotEmpty) buf.writeln();
      buf.writeln('Linked player persona (seed hint only):');
      buf.writeln('- $persona');
    }
    final cast = [
      for (final line in characterLines)
        if (line.trim().isNotEmpty) line.trim(),
    ];
    if (cast.isNotEmpty) {
      if (buf.isNotEmpty) buf.writeln();
      buf.writeln('Linked character cards (seed cast hints only):');
      for (final line in cast.take(24)) {
        buf.writeln('- $line');
      }
    }
    return buf.toString().trim();
  }
}

/// Progress snapshot while the factory runs.
class LivingWorldFactoryProgress {
  const LivingWorldFactoryProgress({
    required this.pass,
    required this.passIndex,
    required this.passCount,
    required this.world,
    this.status = '',
  });

  final LivingWorldFactoryPass pass;
  final int passIndex;
  final int passCount;
  final LivingWorld world;
  final String status;
}

/// Multi-pass compile: brainstorm → places → people → relationships → seed canon.
///
/// Each pass is a separate JSON completion. The app owns the notebook file;
/// the model never writes disk directly. Creation Center is not involved.
class LivingWorldFactoryService {
  const LivingWorldFactoryService();

  static const passOrder = <LivingWorldFactoryPass>[
    LivingWorldFactoryPass.outline,
    LivingWorldFactoryPass.places,
    LivingWorldFactoryPass.people,
    LivingWorldFactoryPass.relationships,
    LivingWorldFactoryPass.seedCanon,
  ];

  /// Build the NanoGPT messages for one factory pass.
  ///
  /// [peopleBatchNames] — when set on the people pass, only flesh out these
  /// names (used for multi-call batches so replies stay short enough).
  List<Map<String, String>> buildPassMessages({
    required LivingWorldFactoryPass pass,
    required LivingWorldFactoryRequest request,
    required LivingWorld world,
    List<String>? peopleBatchNames,
  }) {
    final system = _systemFor(
      pass,
      request,
      peopleBatchNames: peopleBatchNames,
    );
    final user = _userFor(
      pass,
      request,
      world,
      peopleBatchNames: peopleBatchNames,
    );
    return [
      {'role': 'system', 'content': system},
      {'role': 'user', 'content': user},
    ];
  }

  /// Parse one pass response and merge into [world]. Invalid rows are dropped.
  LivingWorld applyPass({
    required LivingWorldFactoryPass pass,
    required LivingWorld world,
    required String rawResponse,
    LivingWorldFactoryRequest? request,
  }) {
    final map = _decodeJsonObject(rawResponse);
    return switch (pass) {
      LivingWorldFactoryPass.outline => _applyOutline(
        world,
        map,
        request: request,
      ),
      LivingWorldFactoryPass.places => _applyPlaces(world, map),
      LivingWorldFactoryPass.people => _applyPeople(world, map),
      LivingWorldFactoryPass.relationships => _applyRelationships(world, map),
      LivingWorldFactoryPass.seedCanon => _applySeedCanon(world, map),
    }.validated();
  }

  /// Run all passes via [completePass]. Saves nothing — caller persists.
  Future<LivingWorld> compile({
    required LivingWorldFactoryRequest request,
    required Future<String> Function(
      LivingWorldFactoryPass pass,
      List<Map<String, String>> messages,
    )
    completePass,
    void Function(LivingWorldFactoryProgress progress)? onProgress,
    LivingWorld? seed,
  }) async {
    var world =
        seed ?? LivingWorld.empty(title: _guessTitle(request.brainstorm));
    final total = passOrder.length;
    for (var i = 0; i < passOrder.length; i++) {
      final pass = passOrder[i];
      if (pass == LivingWorldFactoryPass.people) {
        world = await _compilePeopleInBatches(
          request: request,
          world: world,
          passIndex: i + 1,
          passCount: total,
          completePass: completePass,
          onProgress: onProgress,
        );
        continue;
      }
      onProgress?.call(
        LivingWorldFactoryProgress(
          pass: pass,
          passIndex: i + 1,
          passCount: total,
          world: world,
          status:
              'Step ${i + 1} of $total — ${pass.progressVerb} '
              '(each step can take a few minutes)',
        ),
      );
      final messages = buildPassMessages(
        pass: pass,
        request: request,
        world: world,
      );
      final raw = await completePass(pass, messages);
      try {
        world = applyPass(
          pass: pass,
          world: world,
          rawResponse: raw,
          request: request,
        );
      } on FormatException catch (e) {
        throw FormatException(
          'World factory step "${pass.label}" got a cut-off or invalid reply '
          'from NanoGPT. Try Build world again (or fewer people/places).\n\n$e',
        );
      }
      onProgress?.call(
        LivingWorldFactoryProgress(
          pass: pass,
          passIndex: i + 1,
          passCount: total,
          world: world,
          status:
              '${pass.label} done · '
              '${world.people.length} people · '
              '${world.places.length} places',
        ),
      );
    }
    return world.validated();
  }

  /// Flesh out people in chunks of [kLivingWorldFactoryPeopleBatchSize].
  Future<LivingWorld> _compilePeopleInBatches({
    required LivingWorldFactoryRequest request,
    required LivingWorld world,
    required int passIndex,
    required int passCount,
    required Future<String> Function(
      LivingWorldFactoryPass pass,
      List<Map<String, String>> messages,
    )
    completePass,
    void Function(LivingWorldFactoryProgress progress)? onProgress,
  }) async {
    final target = request.clampedPeople;
    var names = [
      for (final p in world.people)
        if (p.name.trim().isNotEmpty) p.name.trim(),
    ];
    if (names.length > target) {
      names = names.take(target).toList();
    }

    // Prefer named batches from the outline. If outline gave none, invent in
    // anonymous batches of up to kLivingWorldFactoryPeopleBatchSize.
    final batchPlans = <List<String>?>[];
    if (names.isNotEmpty) {
      for (
        var i = 0;
        i < names.length;
        i += kLivingWorldFactoryPeopleBatchSize
      ) {
        final end = (i + kLivingWorldFactoryPeopleBatchSize < names.length)
            ? i + kLivingWorldFactoryPeopleBatchSize
            : names.length;
        batchPlans.add(names.sublist(i, end));
      }
    } else {
      var left = target;
      while (left > 0) {
        final n = left > kLivingWorldFactoryPeopleBatchSize
            ? kLivingWorldFactoryPeopleBatchSize
            : left;
        batchPlans.add(null); // null = invent N new people
        left -= n;
      }
    }

    var next = world;
    for (var b = 0; b < batchPlans.length; b++) {
      final batch = batchPlans[b];
      final batchCount =
          batch?.length ??
          (b == batchPlans.length - 1
              ? (target - next.people.length).clamp(
                  1,
                  kLivingWorldFactoryPeopleBatchSize,
                )
              : kLivingWorldFactoryPeopleBatchSize);
      onProgress?.call(
        LivingWorldFactoryProgress(
          pass: LivingWorldFactoryPass.people,
          passIndex: passIndex,
          passCount: passCount,
          world: next,
          status:
              'Step $passIndex of $passCount — drafting people '
              'batch ${b + 1} of ${batchPlans.length} '
              '(~$batchCount)…',
        ),
      );
      // Temporary request override so the "fill about N" prompt matches batch.
      final batchRequest = LivingWorldFactoryRequest(
        brainstorm: request.brainstorm,
        targetPlaceCount: request.targetPlaceCount,
        targetPersonCount: batchCount,
      );
      final messages = buildPassMessages(
        pass: LivingWorldFactoryPass.people,
        request: batchRequest,
        world: next,
        peopleBatchNames: batch,
      );
      final raw = await completePass(LivingWorldFactoryPass.people, messages);
      try {
        next = applyPass(
          pass: LivingWorldFactoryPass.people,
          world: next,
          rawResponse: raw,
          request: request,
        );
      } on FormatException catch (e) {
        throw FormatException(
          'World factory people batch ${b + 1}/${batchPlans.length} got a '
          'cut-off or invalid reply. Try Build world again.\n\n$e',
        );
      }
    }
    onProgress?.call(
      LivingWorldFactoryProgress(
        pass: LivingWorldFactoryPass.people,
        passIndex: passIndex,
        passCount: passCount,
        world: next,
        status:
            'People done · ${next.people.length} people · '
            '${next.places.length} places',
      ),
    );
    return next;
  }

  String _systemFor(
    LivingWorldFactoryPass pass,
    LivingWorldFactoryRequest request, {
    List<String>? peopleBatchNames,
  }) {
    const shared =
        'You author structured Living World notebook data for Anima.\n'
        'Return ONLY one JSON object (no markdown fences, no prose).\n'
        'Genre-agnostic: do not assume fantasy, dwarves, RPG combat, or maps.\n'
        'Adults-only fiction is fine; do not sanitize or moralize.\n'
        'Use short stable ids like pl_harbor, p_mira (snake_case, unique).\n';

    return switch (pass) {
      LivingWorldFactoryPass.outline =>
        '$shared'
            'Shape:\n'
            '{"title":"...","genreNote":"...","placeNames":["..."],'
            '"personNames":["..."],"themes":["..."]}\n'
            'Aim for about ${request.clampedPlaces} place names and '
            '${request.clampedPeople} person names (unique, playable).\n'
            'title + genreNote describe the whole setting in plain language.',
      LivingWorldFactoryPass.places =>
        '$shared'
            'Shape:\n'
            '{"places":[{"id":"pl_...","name":"...","description":"...",'
            '"connectedPlaceIds":["pl_..."]}]}\n'
            'Fill about ${request.clampedPlaces} places. Connect neighbors '
            'with connectedPlaceIds (ids must refer to places in this list). '
            'Descriptions: 1–2 sentences each.',
      LivingWorldFactoryPass.people =>
        '$shared'
            'Shape:\n'
            '{"people":[{"id":"p_...","name":"...","summary":"...",'
            '"personalityNotes":"...","routineHints":"optional soft schedule",'
            '"inventory":["optional short item names"]}]}\n'
            '${peopleBatchNames != null && peopleBatchNames.isNotEmpty ? 'Flesh out ONLY these ${peopleBatchNames.length} people (same names): ${peopleBatchNames.join(", ")}.\n' : 'Fill about ${request.clampedPeople} named people.\n'}'
            'Keep each field SHORT (summary ≤ 25 words; personalityNotes ≤ 15 words; '
            'routineHints one short phrase or omit; inventory 0–2 short items). '
            'Do not invent places here. Return complete valid JSON only.',
      LivingWorldFactoryPass.relationships =>
        '$shared'
            'Shape:\n'
            '{"relationships":[{"fromId":"p_...","toId":"p_...","score":0,'
            '"labels":["..."]}]}\n'
            'Only use person ids from the roster. score is -100..100. '
            'Prefer meaningful links (trust, rivalry, family, duty) — roughly '
            '1–3 edges per important person, not a complete graph.',
      LivingWorldFactoryPass.seedCanon =>
        '$shared'
            'Shape:\n'
            '{"events":[{"id":"e_...","text":"...","at":"optional",'
            '"placeId":"optional","personIds":["..."]}],'
            '"flags":[{"id":"f_...","key":"snake_case","value":true}],'
            '"threads":[{"id":"th_...","title":"...","summary":"...",'
            '"status":"open","personIds":["..."],"placeId":"optional",'
            '"witnessIds":["..."]}],'
            '"promises":[{"id":"pr_...","text":"...","fromId":"p_...",'
            '"toId":"p_...","status":"open","placeId":"optional"}],'
            '"secrets":[{"id":"sec_...","text":"...","status":"open",'
            '"subjectIds":["..."],"witnessIds":["..."],"placeId":"optional"}],'
            '"liveState":{"activePlaceId":"pl_...","personLocations":'
            '{"p_...":"pl_..."}}}\n'
            'Seed 3–8 starting events, a few flags, and 1–4 open continuity '
            'objects (threads / promises / secrets) that make play interesting. '
            'Only use existing person/place ids. liveState is optional but useful.',
    };
  }

  String _userFor(
    LivingWorldFactoryPass pass,
    LivingWorldFactoryRequest request,
    LivingWorld world, {
    List<String>? peopleBatchNames,
  }) {
    final pitch = request.brainstorm.trim();
    final buf = StringBuffer();
    buf.writeln('## Owner brainstorm');
    buf.writeln(
      pitch.isEmpty ? '(no pitch — invent a vivid town-scale setting)' : pitch,
    );
    buf.writeln();
    buf.writeln('## Current notebook');
    buf.writeln(_formatNotebook(world));
    if (peopleBatchNames != null && peopleBatchNames.isNotEmpty) {
      buf.writeln();
      buf.writeln('## This people batch (required)');
      for (final name in peopleBatchNames) {
        buf.writeln('- $name');
      }
      buf.writeln(
        'Return a "people" array with exactly these names fleshed out. '
        'Do not add extra people in this reply.',
      );
    }
    buf.writeln();
    buf.writeln('Complete the ${pass.label} pass as JSON only.');
    return buf.toString();
  }

  LivingWorld _applyOutline(
    LivingWorld world,
    Map<String, dynamic> map, {
    LivingWorldFactoryRequest? request,
  }) {
    final title = '${map['title'] ?? ''}'.trim();
    final genreNote = '${map['genreNote'] ?? ''}'.trim();
    final placeNames = _stringList(map['placeNames']);
    final personNames = _stringList(map['personNames']);

    // Pre-seed stub rows so later passes have names to flesh out if the model
    // under-delivers — still validated / capped.
    final maxPlaces = request?.clampedPlaces ?? 8;
    final maxPeople = request?.clampedPeople ?? 24;
    final stubPlaces = <WorldPlace>[
      for (final name in placeNames.take(maxPlaces))
        if (name.trim().isNotEmpty)
          WorldPlace(id: _slugId('pl', name), name: name.trim()),
    ];
    final stubPeople = <WorldPerson>[
      for (final name in personNames.take(maxPeople))
        if (name.trim().isNotEmpty)
          WorldPerson(id: _slugId('p', name), name: name.trim()),
    ];

    return world.copyWith(
      title: title.isNotEmpty ? title : world.title,
      genreNote: genreNote.isNotEmpty ? genreNote : world.genreNote,
      places: stubPlaces.isNotEmpty ? stubPlaces : world.places,
      people: stubPeople.isNotEmpty ? stubPeople : world.people,
    );
  }

  LivingWorld _applyPlaces(LivingWorld world, Map<String, dynamic> map) {
    final parsed = <WorldPlace>[];
    final raw = map['places'];
    if (raw is List) {
      for (final item in raw) {
        if (item is! Map) continue;
        try {
          final place = WorldPlace.fromJson(Map<String, dynamic>.from(item));
          parsed.add(
            place.id.trim().isEmpty
                ? place.copyWith(id: _slugId('pl', place.name))
                : place,
          );
        } on FormatException {
          // Skip bad rows.
        }
      }
    }
    if (parsed.isEmpty) return world;

    // Merge by id (or name): factory pass replaces stubs with richer rows.
    final byId = {for (final p in world.places) p.id: p};
    for (final place in parsed) {
      byId[place.id] = place;
    }
    // Also replace stubs that share a name but different id.
    final byName = <String, String>{};
    for (final p in byId.values) {
      byName[p.name.trim().toLowerCase()] = p.id;
    }
    for (final place in parsed) {
      final key = place.name.trim().toLowerCase();
      final existingId = byName[key];
      if (existingId != null && existingId != place.id) {
        byId.remove(existingId);
        byId[place.id] = place;
        byName[key] = place.id;
      }
    }
    return world.copyWith(places: byId.values.toList());
  }

  LivingWorld _applyPeople(LivingWorld world, Map<String, dynamic> map) {
    final parsed = <WorldPerson>[];
    final raw = map['people'];
    if (raw is List) {
      for (final item in raw) {
        if (item is! Map) continue;
        try {
          final person = WorldPerson.fromJson(Map<String, dynamic>.from(item));
          parsed.add(
            person.id.trim().isEmpty
                ? person.copyWith(id: _slugId('p', person.name))
                : person,
          );
        } on FormatException {
          // Skip bad rows.
        }
      }
    }
    if (parsed.isEmpty) return world;

    final byId = {for (final p in world.people) p.id: p};
    for (final person in parsed) {
      byId[person.id] = person;
    }
    final byName = <String, String>{};
    for (final p in byId.values) {
      byName[p.name.trim().toLowerCase()] = p.id;
    }
    for (final person in parsed) {
      final key = person.name.trim().toLowerCase();
      final existingId = byName[key];
      if (existingId != null && existingId != person.id) {
        byId.remove(existingId);
        byId[person.id] = person;
        byName[key] = person.id;
      }
    }
    return world.copyWith(people: byId.values.toList());
  }

  LivingWorld _applyRelationships(LivingWorld world, Map<String, dynamic> map) {
    final personIds = {for (final p in world.people) p.id};
    final parsed = <WorldRelationship>[];
    final raw = map['relationships'];
    if (raw is List) {
      for (final item in raw) {
        if (item is! Map) continue;
        try {
          final rel = WorldRelationship.fromJson(
            Map<String, dynamic>.from(item),
          );
          if (!personIds.contains(rel.fromId) ||
              !personIds.contains(rel.toId)) {
            continue;
          }
          if (rel.fromId == rel.toId) continue;
          parsed.add(rel.copyWith(score: rel.score.clamp(-100, 100)));
        } on FormatException {
          // Skip.
        }
      }
    }
    if (parsed.isEmpty) return world;

    // Upsert by from+to pair.
    String keyOf(WorldRelationship r) => '${r.fromId}->${r.toId}';
    final byKey = {for (final r in world.relationships) keyOf(r): r};
    for (final r in parsed) {
      byKey[keyOf(r)] = r;
    }
    return world.copyWith(relationships: byKey.values.toList());
  }

  LivingWorld _applySeedCanon(LivingWorld world, Map<String, dynamic> map) {
    final personIds = {for (final p in world.people) p.id};
    final placeIds = {for (final p in world.places) p.id};

    final events = <WorldEvent>[...world.events];
    final rawEvents = map['events'];
    if (rawEvents is List) {
      for (final item in rawEvents) {
        if (item is! Map) continue;
        try {
          var event = WorldEvent.fromJson(Map<String, dynamic>.from(item));
          if (event.id.trim().isEmpty) {
            event = event.copyWith(id: _slugId('e', event.text));
          }
          if (event.placeId != null && !placeIds.contains(event.placeId)) {
            event = event.copyWith(clearPlaceId: true);
          }
          event = event.copyWith(
            personIds: [
              for (final id in event.personIds)
                if (personIds.contains(id)) id,
            ],
          );
          if (events.any((e) => e.id == event.id)) continue;
          events.add(event);
        } on FormatException {
          // Skip.
        }
      }
    }

    final flags = <WorldFlag>[...world.flags];
    final rawFlags = map['flags'];
    if (rawFlags is List) {
      for (final item in rawFlags) {
        if (item is! Map) continue;
        try {
          var flag = WorldFlag.fromJson(Map<String, dynamic>.from(item));
          if (flag.id.trim().isEmpty) {
            flag = WorldFlag(
              id: _slugId('f', flag.key),
              key: flag.key,
              value: flag.value,
            );
          }
          final idx = flags.indexWhere(
            (f) => f.key == flag.key || f.id == flag.id,
          );
          if (idx >= 0) {
            flags[idx] = flag;
          } else {
            flags.add(flag);
          }
        } on FormatException {
          // Skip.
        }
      }
    }

    final threads = <WorldThread>[...world.threads];
    final rawThreads = map['threads'];
    if (rawThreads is List) {
      for (final item in rawThreads) {
        if (item is! Map) continue;
        try {
          var thread = WorldThread.fromJson(Map<String, dynamic>.from(item));
          if (thread.id.trim().isEmpty) {
            thread = thread.copyWith(id: _slugId('th', thread.title));
          }
          if (thread.placeId != null && !placeIds.contains(thread.placeId)) {
            thread = thread.copyWith(clearPlaceId: true);
          }
          thread = thread.copyWith(
            personIds: [
              for (final id in thread.personIds)
                if (personIds.contains(id)) id,
            ],
            witnessIds: [
              for (final id in thread.witnessIds)
                if (personIds.contains(id)) id,
            ],
          );
          final idx = threads.indexWhere((t) => t.id == thread.id);
          if (idx >= 0) {
            threads[idx] = thread;
          } else {
            threads.add(thread);
          }
        } on FormatException {
          // Skip.
        }
      }
    }

    final promises = <WorldPromise>[...world.promises];
    final rawPromises = map['promises'];
    if (rawPromises is List) {
      for (final item in rawPromises) {
        if (item is! Map) continue;
        try {
          var promise = WorldPromise.fromJson(Map<String, dynamic>.from(item));
          if (!personIds.contains(promise.fromId) ||
              !personIds.contains(promise.toId)) {
            continue;
          }
          if (promise.id.trim().isEmpty) {
            promise = promise.copyWith(id: _slugId('pr', promise.text));
          }
          if (promise.placeId != null && !placeIds.contains(promise.placeId)) {
            promise = promise.copyWith(clearPlaceId: true);
          }
          final idx = promises.indexWhere((p) => p.id == promise.id);
          if (idx >= 0) {
            promises[idx] = promise;
          } else {
            promises.add(promise);
          }
        } on FormatException {
          // Skip.
        }
      }
    }

    final secrets = <WorldSecret>[...world.secrets];
    final rawSecrets = map['secrets'];
    if (rawSecrets is List) {
      for (final item in rawSecrets) {
        if (item is! Map) continue;
        try {
          var secret = WorldSecret.fromJson(Map<String, dynamic>.from(item));
          if (secret.id.trim().isEmpty) {
            secret = secret.copyWith(id: _slugId('sec', secret.text));
          }
          if (secret.placeId != null && !placeIds.contains(secret.placeId)) {
            secret = secret.copyWith(clearPlaceId: true);
          }
          secret = secret.copyWith(
            subjectIds: [
              for (final id in secret.subjectIds)
                if (personIds.contains(id)) id,
            ],
            witnessIds: [
              for (final id in secret.witnessIds)
                if (personIds.contains(id)) id,
            ],
          );
          final idx = secrets.indexWhere((s) => s.id == secret.id);
          if (idx >= 0) {
            secrets[idx] = secret;
          } else {
            secrets.add(secret);
          }
        } on FormatException {
          // Skip.
        }
      }
    }

    WorldLiveState? live = world.liveState;
    final rawLive = map['liveState'];
    if (rawLive is Map) {
      try {
        final parsed = WorldLiveState.fromJson(
          Map<String, dynamic>.from(rawLive),
        );
        live = parsed;
      } on FormatException {
        // Keep previous.
      }
    }

    return world.copyWith(
      events: events,
      flags: flags,
      threads: threads,
      promises: promises,
      secrets: secrets,
      liveState: live,
    );
  }

  Map<String, dynamic> _decodeJsonObject(String raw) {
    var text = raw.trim();
    if (text.startsWith('```')) {
      final lines = text.split('\n');
      if (lines.isNotEmpty) lines.removeAt(0);
      if (lines.isNotEmpty && lines.last.trim().startsWith('```')) {
        lines.removeLast();
      }
      text = lines.join('\n').trim();
    }
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start >= 0 && end > start) {
      final slice = text.substring(start, end + 1);
      try {
        final decoded = jsonDecode(slice);
        if (decoded is Map) {
          return Map<String, dynamic>.from(decoded);
        }
      } on FormatException {
        // Fall through to salvage incomplete arrays (truncated replies).
      }
    }

    for (final key in const [
      'people',
      'places',
      'relationships',
      'events',
      'flags',
      'threads',
      'promises',
      'secrets',
    ]) {
      final salvaged = _salvageNamedArray(text, key);
      if (salvaged != null) return salvaged;
    }

    throw const FormatException(
      'Factory pass reply was cut off or not valid JSON.',
    );
  }

  /// Pull complete `{...}` objects from a truncated `"key": [ ...` array.
  Map<String, dynamic>? _salvageNamedArray(String text, String key) {
    final marker = '"$key"';
    final keyIdx = text.indexOf(marker);
    if (keyIdx < 0) return null;
    final bracket = text.indexOf('[', keyIdx + marker.length);
    if (bracket < 0) return null;

    final items = <dynamic>[];
    var i = bracket + 1;
    while (i < text.length) {
      while (i < text.length && ' \n\r\t,'.contains(text[i])) {
        i++;
      }
      if (i >= text.length || text[i] == ']') break;
      if (text[i] != '{') break;
      final objEnd = _findMatchingBrace(text, i);
      if (objEnd < 0) break; // truncated mid-object — keep what we have
      try {
        items.add(jsonDecode(text.substring(i, objEnd + 1)));
      } on FormatException {
        break;
      }
      i = objEnd + 1;
    }
    if (items.isEmpty) return null;
    return {key: items};
  }

  /// Index of the `}` that closes the `{` at [openIndex], or -1 if truncated.
  int _findMatchingBrace(String text, int openIndex) {
    var depth = 0;
    var inString = false;
    var escape = false;
    for (var i = openIndex; i < text.length; i++) {
      final ch = text[i];
      if (inString) {
        if (escape) {
          escape = false;
        } else if (ch == '\\') {
          escape = true;
        } else if (ch == '"') {
          inString = false;
        }
        continue;
      }
      if (ch == '"') {
        inString = true;
        continue;
      }
      if (ch == '{') {
        depth++;
      } else if (ch == '}') {
        depth--;
        if (depth == 0) return i;
      }
    }
    return -1;
  }

  List<String> _stringList(Object? raw) {
    if (raw is! List) return const [];
    return [
      for (final item in raw)
        if ('$item'.trim().isNotEmpty) '$item'.trim(),
    ];
  }

  String _formatNotebook(LivingWorld world) {
    final buf = StringBuffer();
    buf.writeln('id: ${world.id}');
    buf.writeln('title: ${world.title}');
    if (world.genreNote.trim().isNotEmpty) {
      buf.writeln('genreNote: ${world.genreNote.trim()}');
    }
    buf.writeln('places (${world.places.length}):');
    for (final p in world.places.take(40)) {
      buf.writeln(
        '- ${p.id}: ${p.name}'
        '${p.description.trim().isEmpty ? '' : ' — ${p.description.trim()}'}',
      );
    }
    buf.writeln('people (${world.people.length}):');
    for (final p in world.people.take(60)) {
      buf.writeln(
        '- ${p.id}: ${p.name}'
        '${p.summary.trim().isEmpty ? '' : ' — ${p.summary.trim()}'}',
      );
    }
    if (world.relationships.isNotEmpty) {
      buf.writeln('relationships (${world.relationships.length}):');
      for (final r in world.relationships.take(40)) {
        buf.writeln('- ${r.fromId} → ${r.toId}: ${r.score}');
      }
    }
    if (world.events.isNotEmpty) {
      buf.writeln('events (${world.events.length}):');
      for (final e in world.events.take(12)) {
        buf.writeln('- ${e.id}: ${e.text}');
      }
    }
    return buf.toString().trimRight();
  }

  static String _slugId(String prefix, String name) {
    final slug = name
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    final stem = slug.isEmpty
        ? DateTime.now().microsecondsSinceEpoch.toString()
        : (slug.length > 32 ? slug.substring(0, 32) : slug);
    return '${prefix}_$stem';
  }

  static String _guessTitle(String brainstorm) {
    final line = brainstorm.trim().split(RegExp(r'[\n.]')).first.trim();
    if (line.isEmpty) return 'New world';
    if (line.length <= 48) return line;
    return '${line.substring(0, 45)}…';
  }
}
