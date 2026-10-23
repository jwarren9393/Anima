import 'dart:convert';

import '../models/chat_message.dart';
import '../models/living_world.dart';
import 'living_world_systems_service.dart';

/// One proposed change to Living World canon (never applied until review).
enum LivingWorldUpdateOp {
  addEvent,
  setFlag,
  setRelationship,
  setActivePlace,
  setPersonLocation,
  upsertThread,
  closeThread,
  upsertPromise,
  closePromise,
  upsertSecret,
  closeSecret,
  setInventory,

  /// New or refreshed notebook person introduced in chat (review-only).
  upsertPerson,
}

/// A single proposed canon edit, validated against the current world.
class LivingWorldCanonUpdate {
  const LivingWorldCanonUpdate({
    required this.op,
    required this.summary,
    this.event,
    this.flag,
    this.relationship,
    this.activePlaceId,
    this.personId,
    this.placeId,
    this.thread,
    this.promise,
    this.secret,
    this.inventoryItems,
    this.targetId,
    this.person,
  });

  final LivingWorldUpdateOp op;

  /// Short human label for the review sheet.
  final String summary;

  final WorldEvent? event;
  final WorldFlag? flag;
  final WorldRelationship? relationship;
  final String? activePlaceId;
  final String? personId;
  final String? placeId;
  final WorldThread? thread;
  final WorldPromise? promise;
  final WorldSecret? secret;
  final List<String>? inventoryItems;

  /// Id for close* ops (thread / promise / secret).
  final String? targetId;

  /// Payload for [LivingWorldUpdateOp.upsertPerson].
  final WorldPerson? person;

  String get reviewLabel => switch (op) {
    LivingWorldUpdateOp.addEvent => 'Event',
    LivingWorldUpdateOp.setFlag => 'Flag',
    LivingWorldUpdateOp.setRelationship => 'Relationship',
    LivingWorldUpdateOp.setActivePlace => 'Active place',
    LivingWorldUpdateOp.setPersonLocation => 'Who / where',
    LivingWorldUpdateOp.upsertThread => 'Thread',
    LivingWorldUpdateOp.closeThread => 'Close thread',
    LivingWorldUpdateOp.upsertPromise => 'Promise',
    LivingWorldUpdateOp.closePromise => 'Close promise',
    LivingWorldUpdateOp.upsertSecret => 'Secret',
    LivingWorldUpdateOp.closeSecret => 'Close secret',
    LivingWorldUpdateOp.setInventory => 'Inventory',
    LivingWorldUpdateOp.upsertPerson => 'New person',
  };

  String get reviewDetail => summary;

  /// Safe for Phase 5 auto-apply (still schema-validated).
  /// Relationships and new people need Review pending.
  bool get isSafeForAutoApply => switch (op) {
    LivingWorldUpdateOp.addEvent ||
    LivingWorldUpdateOp.setFlag ||
    LivingWorldUpdateOp.setActivePlace ||
    LivingWorldUpdateOp.setPersonLocation ||
    LivingWorldUpdateOp.upsertThread ||
    LivingWorldUpdateOp.closeThread ||
    LivingWorldUpdateOp.upsertPromise ||
    LivingWorldUpdateOp.closePromise ||
    LivingWorldUpdateOp.upsertSecret ||
    LivingWorldUpdateOp.closeSecret ||
    LivingWorldUpdateOp.setInventory => true,
    LivingWorldUpdateOp.setRelationship ||
    LivingWorldUpdateOp.upsertPerson => false,
  };

  /// Fingerprint for pending-queue dedupe (op + summary).
  String get pendingKey => '${op.name}|${summary.trim().toLowerCase()}';

  /// Full payload for disk-backed pending review (Phase 11).
  Map<String, dynamic> toJson() => {
    'op': op.name,
    'summary': summary,
    if (event != null) 'event': event!.toJson(),
    if (flag != null) 'flag': flag!.toJson(),
    if (relationship != null) 'relationship': relationship!.toJson(),
    if (activePlaceId != null && activePlaceId!.trim().isNotEmpty)
      'activePlaceId': activePlaceId!.trim(),
    if (personId != null && personId!.trim().isNotEmpty)
      'personId': personId!.trim(),
    if (placeId != null && placeId!.trim().isNotEmpty)
      'placeId': placeId!.trim(),
    if (thread != null) 'thread': thread!.toJson(),
    if (promise != null) 'promise': promise!.toJson(),
    if (secret != null) 'secret': secret!.toJson(),
    if (inventoryItems != null) 'inventoryItems': inventoryItems,
    if (targetId != null && targetId!.trim().isNotEmpty)
      'targetId': targetId!.trim(),
    if (person != null) 'person': person!.toJson(),
  };

  factory LivingWorldCanonUpdate.fromJson(Map<String, dynamic> json) {
    final opName = '${json['op'] ?? ''}'.trim();
    final op = LivingWorldUpdateOp.values.firstWhere(
      (o) => o.name == opName,
      orElse: () => LivingWorldUpdateOp.addEvent,
    );
    final summary = '${json['summary'] ?? ''}'.trim();
    WorldEvent? event;
    final rawEvent = json['event'];
    if (rawEvent is Map) {
      event = WorldEvent.fromJson(Map<String, dynamic>.from(rawEvent));
    }
    WorldFlag? flag;
    final rawFlag = json['flag'];
    if (rawFlag is Map) {
      flag = WorldFlag.fromJson(Map<String, dynamic>.from(rawFlag));
    }
    WorldRelationship? relationship;
    final rawRel = json['relationship'];
    if (rawRel is Map) {
      relationship = WorldRelationship.fromJson(
        Map<String, dynamic>.from(rawRel),
      );
    }
    WorldThread? thread;
    final rawThread = json['thread'];
    if (rawThread is Map) {
      thread = WorldThread.fromJson(Map<String, dynamic>.from(rawThread));
    }
    WorldPromise? promise;
    final rawPromise = json['promise'];
    if (rawPromise is Map) {
      promise = WorldPromise.fromJson(Map<String, dynamic>.from(rawPromise));
    }
    WorldSecret? secret;
    final rawSecret = json['secret'];
    if (rawSecret is Map) {
      secret = WorldSecret.fromJson(Map<String, dynamic>.from(rawSecret));
    }
    WorldPerson? person;
    final rawPerson = json['person'];
    if (rawPerson is Map) {
      try {
        person = WorldPerson.fromJson(Map<String, dynamic>.from(rawPerson));
      } on FormatException {
        person = null;
      }
    }
    List<String>? inventoryItems;
    final rawInv = json['inventoryItems'];
    if (rawInv is List) {
      inventoryItems = [
        for (final item in rawInv)
          if ('$item'.trim().isNotEmpty) '$item'.trim(),
      ];
    }
    final activePlaceId = '${json['activePlaceId'] ?? ''}'.trim();
    final personId = '${json['personId'] ?? ''}'.trim();
    final placeId = '${json['placeId'] ?? ''}'.trim();
    final targetId = '${json['targetId'] ?? ''}'.trim();
    return LivingWorldCanonUpdate(
      op: op,
      summary: summary.isEmpty ? op.name : summary,
      event: event,
      flag: flag,
      relationship: relationship,
      activePlaceId: activePlaceId.isEmpty ? null : activePlaceId,
      personId: personId.isEmpty ? null : personId,
      placeId: placeId.isEmpty ? null : placeId,
      thread: thread,
      promise: promise,
      secret: secret,
      inventoryItems: inventoryItems,
      targetId: targetId.isEmpty ? null : targetId,
      person: person,
    );
  }
}

/// Propose structured canon updates from recent chat; apply only after review.
class LivingWorldUpdateService {
  const LivingWorldUpdateService({
    this.systems = const LivingWorldSystemsService(),
  });

  final LivingWorldSystemsService systems;

  static const maxTranscriptMessages = 24;
  static const maxProposedUpdates = 12;
  static const maxInventoryItems = 12;

  /// Messages for a one-shot NanoGPT propose call (JSON only).
  List<Map<String, String>> buildProposeMessages({
    required LivingWorld world,
    required List<ChatMessage> recentMessages,
    String userName = '',
    String speakerName = '',
  }) {
    final transcript = _formatTranscript(recentMessages);
    final roster = _formatRoster(world);

    return [
      {
        'role': 'system',
        'content':
            'You extract durable Living World canon updates from a roleplay chat.\n'
            'Return ONLY one JSON object (no markdown, no prose) shaped like:\n'
            '{"updates":[{"op":"addEvent|setFlag|setRelationship|setActivePlace|'
            'setPersonLocation|upsertThread|closeThread|upsertPromise|closePromise|'
            'upsertSecret|closeSecret|setInventory|upsertPerson",...}]}\n'
            '\n'
            'Rules:\n'
            '- Only propose facts clearly established or decided in the recent chat.\n'
            '- For events/flags/relationships/places/locations/continuity/inventory: '
            'use only person/place ids from the roster (do not invent place ids).\n'
            '- upsertPerson: when chat clearly INTRODUCES or NAMES someone new '
            'with a role (e.g. a lady presented at dinner who is not on the roster), '
            'propose one upsertPerson with their name + a short summary. '
            'Do not invent random extras who were never named.\n'
            '- Prefer short factual event text (who decided/did what, where).\n'
            '- Flags: stable keys like snake_case; value bool or short string.\n'
            '  Prefer recipe-style keys when they fit: knows_<person>, '
            'banished_from_<place>, <personId>_deceased.\n'
            '- Relationships: fromId/toId must be person ids; score -100..100; optional labels[].\n'
            '  Labels may include aid / betrayal / promise when the chat clearly shows that.\n'
            '- setActivePlace: placeId from roster.\n'
            '- setPersonLocation: personId + placeId from roster.\n'
            '- Threads / promises / secrets: open long-run loops. Upsert to create/update; '
            'close* when the loop is resolved in chat. Reuse existing ids from Open continuity '
            'when updating/closing — do not duplicate open items.\n'
            '- setInventory: replace one person\'s item list (short names only, max '
            '$maxInventoryItems).\n'
            '- Skip vibes, dialogue flavor, and things already in the notebook.\n'
            '- At most $maxProposedUpdates updates. Empty list is OK: {"updates":[]}.\n'
            '\n'
            'Field shapes:\n'
            'addEvent: {"op":"addEvent","text":"...","at":"optional","placeId":"optional","personIds":["..."]}\n'
            'setFlag: {"op":"setFlag","key":"...","value":true}\n'
            'setRelationship: {"op":"setRelationship","fromId":"...","toId":"...","score":0,"labels":["..."]}\n'
            'setActivePlace: {"op":"setActivePlace","placeId":"..."}\n'
            'setPersonLocation: {"op":"setPersonLocation","personId":"...","placeId":"..."}\n'
            'upsertThread: {"op":"upsertThread","id":"optional","title":"...","summary":"...",'
            '"status":"open|closed","personIds":["..."],"placeId":"optional","witnessIds":["..."]}\n'
            'closeThread: {"op":"closeThread","id":"th_..."}\n'
            'upsertPromise: {"op":"upsertPromise","id":"optional","text":"...","fromId":"...","toId":"...",'
            '"status":"open|closed","placeId":"optional"}\n'
            'closePromise: {"op":"closePromise","id":"pr_..."}\n'
            'upsertSecret: {"op":"upsertSecret","id":"optional","text":"...","status":"open|closed",'
            '"subjectIds":["..."],"witnessIds":["..."],"placeId":"optional"}\n'
            'closeSecret: {"op":"closeSecret","id":"sec_..."}\n'
            'setInventory: {"op":"setInventory","personId":"...","items":["..."]}\n'
            'upsertPerson: {"op":"upsertPerson","id":"optional p_...","name":"...",'
            '"summary":"short role","personalityNotes":"optional"}\n',
      },
      {
        'role': 'user',
        'content':
            'World: ${world.title}\n'
            '${world.genreNote.trim().isEmpty ? '' : 'Setting: ${world.genreNote.trim()}\n'}'
            'Player ({{user}}): ${userName.isEmpty ? 'User' : userName}\n'
            '${speakerName.trim().isEmpty ? '' : 'Speaking character: $speakerName\n'}'
            '\n'
            '## Roster (ids you may use)\n'
            '$roster\n'
            '\n'
            '## Existing flags (do not duplicate unless value changed)\n'
            '${_formatFlags(world)}\n'
            '\n'
            '## Open continuity (reuse ids; do not duplicate)\n'
            '${_formatOpenContinuity(world)}\n'
            '\n'
            '## Recent events (do not repeat)\n'
            '${_formatRecentEvents(world)}\n'
            '\n'
            '## Recent chat\n'
            '$transcript\n'
            '\n'
            'Propose canon updates now as JSON only.',
      },
    ];
  }

  /// Parse model output into validated updates. Invalid rows are dropped.
  List<LivingWorldCanonUpdate> parseProposal(
    String raw, {
    required LivingWorld world,
  }) {
    final map = extractJsonObject(raw);
    final list = map['updates'];
    if (list is! List) {
      throw const FormatException(
        'Living World update JSON needs an "updates" array.',
      );
    }

    final personIds = {for (final p in world.people) p.id};
    final placeIds = {for (final p in world.places) p.id};
    final out = <LivingWorldCanonUpdate>[];

    for (final item in list) {
      if (item is! Map) continue;
      if (out.length >= maxProposedUpdates) break;
      final update = _parseOne(
        Map<String, dynamic>.from(item),
        personIds: personIds,
        placeIds: placeIds,
        people: world.people,
        places: world.places,
        world: world,
      );
      if (update != null) out.add(update);
    }
    return out;
  }

  /// Split proposals into auto-safe vs needs-review (Phase 5 autoSafe policy).
  ({List<LivingWorldCanonUpdate> safe, List<LivingWorldCanonUpdate> risky})
  partitionForAutoSafe(List<LivingWorldCanonUpdate> updates) {
    final safe = <LivingWorldCanonUpdate>[];
    final risky = <LivingWorldCanonUpdate>[];
    for (final u in updates) {
      if (u.isSafeForAutoApply) {
        safe.add(u);
      } else {
        risky.add(u);
      }
    }
    return (safe: safe, risky: risky);
  }

  /// Apply selected updates onto [world]. Does not save to disk.
  ///
  /// After validated ops land, Phase 7 light systems may nudge relationships
  /// and set recipe flags from newly added events (still clamped / id-checked).
  LivingWorld applyUpdates(
    LivingWorld world,
    List<LivingWorldCanonUpdate> selected, {
    bool runSystems = true,
  }) {
    if (selected.isEmpty) return world;

    var people = List<WorldPerson>.from(world.people);
    var places = List<WorldPlace>.from(world.places);
    var relationships = List<WorldRelationship>.from(world.relationships);
    var events = List<WorldEvent>.from(world.events);
    var flags = List<WorldFlag>.from(world.flags);
    var threads = List<WorldThread>.from(world.threads);
    var promises = List<WorldPromise>.from(world.promises);
    var secrets = List<WorldSecret>.from(world.secrets);
    var live = world.liveState;

    for (final update in selected) {
      switch (update.op) {
        case LivingWorldUpdateOp.addEvent:
          final event = update.event;
          if (event == null) continue;
          events = [...events, event];
        case LivingWorldUpdateOp.setFlag:
          final flag = update.flag;
          if (flag == null) continue;
          final idx = flags.indexWhere(
            (f) => f.key.toLowerCase() == flag.key.toLowerCase(),
          );
          if (idx >= 0) {
            flags = List<WorldFlag>.from(flags)..[idx] = flag;
          } else {
            flags = [...flags, flag];
          }
        case LivingWorldUpdateOp.setRelationship:
          final rel = update.relationship;
          if (rel == null) continue;
          final idx = relationships.indexWhere(
            (r) => r.fromId == rel.fromId && r.toId == rel.toId,
          );
          if (idx >= 0) {
            relationships = List<WorldRelationship>.from(relationships)
              ..[idx] = rel;
          } else {
            relationships = [...relationships, rel];
          }
        case LivingWorldUpdateOp.setActivePlace:
          final placeId = update.activePlaceId;
          if (placeId == null || placeId.isEmpty) continue;
          live = (live ?? const WorldLiveState()).copyWith(
            activePlaceId: placeId,
          );
        case LivingWorldUpdateOp.setPersonLocation:
          final personId = update.personId;
          final placeId = update.placeId;
          if (personId == null || placeId == null) continue;
          final base = live ?? const WorldLiveState();
          live = base.copyWith(
            personLocations: {...base.personLocations, personId: placeId},
          );
        case LivingWorldUpdateOp.upsertThread:
          final thread = update.thread;
          if (thread == null) continue;
          final idx = threads.indexWhere((t) => t.id == thread.id);
          if (idx >= 0) {
            threads = List<WorldThread>.from(threads)..[idx] = thread;
          } else {
            threads = [...threads, thread];
          }
        case LivingWorldUpdateOp.closeThread:
          final id = update.targetId;
          if (id == null) continue;
          final idx = threads.indexWhere((t) => t.id == id);
          if (idx < 0) continue;
          threads = List<WorldThread>.from(threads)
            ..[idx] = threads[idx].copyWith(
              status: WorldContinuityStatus.closed,
            );
        case LivingWorldUpdateOp.upsertPromise:
          final promise = update.promise;
          if (promise == null) continue;
          final idx = promises.indexWhere((p) => p.id == promise.id);
          if (idx >= 0) {
            promises = List<WorldPromise>.from(promises)..[idx] = promise;
          } else {
            promises = [...promises, promise];
          }
        case LivingWorldUpdateOp.closePromise:
          final id = update.targetId;
          if (id == null) continue;
          final idx = promises.indexWhere((p) => p.id == id);
          if (idx < 0) continue;
          promises = List<WorldPromise>.from(promises)
            ..[idx] = promises[idx].copyWith(
              status: WorldContinuityStatus.closed,
            );
        case LivingWorldUpdateOp.upsertSecret:
          final secret = update.secret;
          if (secret == null) continue;
          final idx = secrets.indexWhere((s) => s.id == secret.id);
          if (idx >= 0) {
            secrets = List<WorldSecret>.from(secrets)..[idx] = secret;
          } else {
            secrets = [...secrets, secret];
          }
        case LivingWorldUpdateOp.closeSecret:
          final id = update.targetId;
          if (id == null) continue;
          final idx = secrets.indexWhere((s) => s.id == id);
          if (idx < 0) continue;
          secrets = List<WorldSecret>.from(secrets)
            ..[idx] = secrets[idx].copyWith(
              status: WorldContinuityStatus.closed,
            );
        case LivingWorldUpdateOp.setInventory:
          final personId = update.personId;
          final items = update.inventoryItems;
          if (personId == null || items == null) continue;
          final idx = people.indexWhere((p) => p.id == personId);
          if (idx < 0) continue;
          people = List<WorldPerson>.from(people)
            ..[idx] = people[idx].copyWith(inventory: items);
        case LivingWorldUpdateOp.upsertPerson:
          final person = update.person;
          if (person == null) continue;
          final byId = people.indexWhere((p) => p.id == person.id);
          if (byId >= 0) {
            final existing = people[byId];
            people = List<WorldPerson>.from(people)
              ..[byId] = existing.copyWith(
                name: person.name,
                summary: person.summary.trim().isNotEmpty
                    ? person.summary
                    : existing.summary,
                personalityNotes: person.personalityNotes.trim().isNotEmpty
                    ? person.personalityNotes
                    : existing.personalityNotes,
              );
            continue;
          }
          final nameKey = person.name.trim().toLowerCase();
          final byName = people.indexWhere(
            (p) => p.name.trim().toLowerCase() == nameKey,
          );
          if (byName >= 0) {
            final existing = people[byName];
            people = List<WorldPerson>.from(people)
              ..[byName] = existing.copyWith(
                summary: person.summary.trim().isNotEmpty
                    ? person.summary
                    : existing.summary,
                personalityNotes: person.personalityNotes.trim().isNotEmpty
                    ? person.personalityNotes
                    : existing.personalityNotes,
              );
          } else {
            people = [...people, person];
          }
      }
    }

    final after = LivingWorld(
      id: world.id,
      title: world.title,
      schemaVersion: world.schemaVersion,
      genreNote: world.genreNote,
      people: people,
      places: places,
      relationships: relationships,
      events: events,
      flags: flags,
      threads: threads,
      promises: promises,
      secrets: secrets,
      liveState: live,
    ).validated();

    if (!runSystems) return after;
    return systems.enrichAfterApply(
      before: world,
      after: after,
      applied: selected,
    );
  }

  /// Pull a JSON object from model text (fences or balanced braces).
  static Map<String, dynamic> extractJsonObject(String raw) {
    final text = raw.trim();
    if (text.isEmpty) {
      throw const FormatException('Empty Living World update reply.');
    }

    final fence = RegExp(r'```(?:json)?\s*([\s\S]*?)```', caseSensitive: false);
    for (final match in fence.allMatches(text)) {
      final fenced = match.group(1)?.trim() ?? '';
      final parsed = _tryParseObject(fenced);
      if (parsed != null) return parsed;
      final salvaged = _salvageUpdatesObject(fenced);
      if (salvaged != null) return salvaged;
    }

    final parsed = _tryParseObject(text);
    if (parsed != null) return parsed;
    final salvaged = _salvageUpdatesObject(text);
    if (salvaged != null) return salvaged;

    throw const FormatException(
      'Could not find Living World update JSON in the model reply. '
      'The model returned prose or cut-off JSON — try Update world from chat again.',
    );
  }

  /// When the model truncates mid-array, keep complete update objects.
  static Map<String, dynamic>? _salvageUpdatesObject(String text) {
    final marker = '"updates"';
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
      if (objEnd < 0) break;
      try {
        items.add(jsonDecode(text.substring(i, objEnd + 1)));
      } catch (_) {
        break;
      }
      i = objEnd + 1;
    }
    if (items.isEmpty) return null;
    return {'updates': items};
  }

  static int _findMatchingBrace(String text, int openIndex) {
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

  static Map<String, dynamic>? _tryParseObject(String text) {
    final slice = _balancedObject(text);
    if (slice == null) return null;
    try {
      final decoded = jsonDecode(slice);
      if (decoded is! Map) return null;
      return Map<String, dynamic>.from(decoded);
    } catch (_) {
      return null;
    }
  }

  static String? _balancedObject(String text) {
    final start = text.indexOf('{');
    if (start < 0) return null;
    var depth = 0;
    var inString = false;
    var escape = false;
    for (var i = start; i < text.length; i++) {
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
      if (ch == '{') depth++;
      if (ch == '}') {
        depth--;
        if (depth == 0) return text.substring(start, i + 1);
      }
    }
    return null;
  }

  LivingWorldCanonUpdate? _parseOne(
    Map<String, dynamic> json, {
    required Set<String> personIds,
    required Set<String> placeIds,
    required List<WorldPerson> people,
    required List<WorldPlace> places,
    required LivingWorld world,
  }) {
    final opRaw = '${json['op'] ?? ''}'.trim();
    final op = switch (opRaw) {
      'addEvent' => LivingWorldUpdateOp.addEvent,
      'setFlag' => LivingWorldUpdateOp.setFlag,
      'setRelationship' => LivingWorldUpdateOp.setRelationship,
      'setActivePlace' => LivingWorldUpdateOp.setActivePlace,
      'setPersonLocation' => LivingWorldUpdateOp.setPersonLocation,
      'upsertThread' => LivingWorldUpdateOp.upsertThread,
      'closeThread' => LivingWorldUpdateOp.closeThread,
      'upsertPromise' => LivingWorldUpdateOp.upsertPromise,
      'closePromise' => LivingWorldUpdateOp.closePromise,
      'upsertSecret' => LivingWorldUpdateOp.upsertSecret,
      'closeSecret' => LivingWorldUpdateOp.closeSecret,
      'setInventory' => LivingWorldUpdateOp.setInventory,
      'upsertPerson' => LivingWorldUpdateOp.upsertPerson,
      _ => null,
    };
    if (op == null) return null;

    switch (op) {
      case LivingWorldUpdateOp.upsertPerson:
        final name = '${json['name'] ?? ''}'.trim();
        if (name.isEmpty) return null;
        final nameKey = name.toLowerCase();
        // Already on the roster under this name — skip (no duplicate noise).
        for (final p in people) {
          if (p.name.trim().toLowerCase() == nameKey) return null;
        }
        var id = '${json['id'] ?? ''}'.trim();
        if (id.isEmpty) {
          id = _slugPersonId(name);
        }
        // Reject colliding with a different person's id.
        if (personIds.contains(id)) return null;
        final summary = '${json['summary'] ?? ''}'.trim();
        final personalityNotes = '${json['personalityNotes'] ?? ''}'.trim();
        final person = WorldPerson(
          id: id,
          name: name,
          summary: summary.length > 200 ? summary.substring(0, 200) : summary,
          personalityNotes: personalityNotes.length > 120
              ? personalityNotes.substring(0, 120)
              : personalityNotes,
        );
        final label = summary.isEmpty ? name : '$name — $summary';
        return LivingWorldCanonUpdate(
          op: op,
          summary: label.length > 120 ? '${label.substring(0, 117)}…' : label,
          person: person,
        );

      case LivingWorldUpdateOp.addEvent:
        final text = '${json['text'] ?? ''}'.trim();
        if (text.isEmpty) return null;
        final placeId = '${json['placeId'] ?? ''}'.trim();
        if (placeId.isNotEmpty && !placeIds.contains(placeId)) return null;
        final personIdsOut = <String>[];
        final rawPeople = json['personIds'];
        var hadPersonIds = false;
        if (rawPeople is List) {
          for (final item in rawPeople) {
            final id = '$item'.trim();
            if (id.isEmpty) continue;
            hadPersonIds = true;
            if (personIds.contains(id)) personIdsOut.add(id);
          }
        }
        // Reject when the model only named people that are not in the roster.
        if (hadPersonIds && personIdsOut.isEmpty) return null;
        final at = '${json['at'] ?? ''}'.trim();
        final event = WorldEvent(
          id: 'e_${DateTime.now().microsecondsSinceEpoch}_${outHash(text)}',
          text: text,
          at: at.isEmpty ? null : at,
          placeId: placeId.isEmpty ? null : placeId,
          personIds: personIdsOut,
        );
        return LivingWorldCanonUpdate(op: op, summary: text, event: event);

      case LivingWorldUpdateOp.setFlag:
        final key = '${json['key'] ?? ''}'.trim();
        if (key.isEmpty) return null;
        final rawValue = json['value'];
        final Object value;
        if (rawValue is bool || rawValue is num || rawValue is String) {
          value = rawValue as Object;
        } else if (rawValue == null) {
          value = true;
        } else {
          value = '$rawValue';
        }
        final flag = WorldFlag(
          id: 'f_${key.toLowerCase().replaceAll(RegExp(r"[^\w]+"), "_")}',
          key: key,
          value: value,
        );
        return LivingWorldCanonUpdate(
          op: op,
          summary: '$key = $value',
          flag: flag,
        );

      case LivingWorldUpdateOp.setRelationship:
        final fromId = '${json['fromId'] ?? ''}'.trim();
        final toId = '${json['toId'] ?? ''}'.trim();
        if (!personIds.contains(fromId) || !personIds.contains(toId)) {
          return null;
        }
        final scoreRaw = json['score'];
        final score =
            (scoreRaw is int ? scoreRaw : int.tryParse('$scoreRaw') ?? 0).clamp(
              -100,
              100,
            );
        final labels = <String>[];
        final rawLabels = json['labels'];
        if (rawLabels is List) {
          for (final item in rawLabels) {
            final v = '$item'.trim();
            if (v.isNotEmpty) labels.add(v);
          }
        }
        final fromName = _nameOf(people, fromId);
        final toName = _nameOf(people, toId);
        final labelBit = labels.isEmpty ? '' : ' (${labels.join(', ')})';
        return LivingWorldCanonUpdate(
          op: op,
          summary: '$fromName → $toName: $score$labelBit',
          relationship: WorldRelationship(
            fromId: fromId,
            toId: toId,
            score: score,
            labels: labels,
          ),
        );

      case LivingWorldUpdateOp.setActivePlace:
        final placeId = '${json['placeId'] ?? ''}'.trim();
        if (!placeIds.contains(placeId)) return null;
        return LivingWorldCanonUpdate(
          op: op,
          summary: 'Active place → ${_nameOfPlace(places, placeId)}',
          activePlaceId: placeId,
        );

      case LivingWorldUpdateOp.setPersonLocation:
        final personId = '${json['personId'] ?? ''}'.trim();
        final placeId = '${json['placeId'] ?? ''}'.trim();
        if (!personIds.contains(personId) || !placeIds.contains(placeId)) {
          return null;
        }
        return LivingWorldCanonUpdate(
          op: op,
          summary:
              '${_nameOf(people, personId)} @ ${_nameOfPlace(places, placeId)}',
          personId: personId,
          placeId: placeId,
        );

      case LivingWorldUpdateOp.upsertThread:
        return _parseUpsertThread(
          json,
          personIds: personIds,
          placeIds: placeIds,
          world: world,
        );

      case LivingWorldUpdateOp.closeThread:
        final id = '${json['id'] ?? ''}'.trim();
        if (id.isEmpty || !world.threads.any((t) => t.id == id)) return null;
        final title = world.threads.firstWhere((t) => t.id == id).title;
        return LivingWorldCanonUpdate(
          op: op,
          summary: 'Close thread: $title',
          targetId: id,
        );

      case LivingWorldUpdateOp.upsertPromise:
        return _parseUpsertPromise(
          json,
          personIds: personIds,
          placeIds: placeIds,
          people: people,
          world: world,
        );

      case LivingWorldUpdateOp.closePromise:
        final id = '${json['id'] ?? ''}'.trim();
        if (id.isEmpty || !world.promises.any((p) => p.id == id)) return null;
        final text = world.promises.firstWhere((p) => p.id == id).text;
        return LivingWorldCanonUpdate(
          op: op,
          summary: 'Close promise: $text',
          targetId: id,
        );

      case LivingWorldUpdateOp.upsertSecret:
        return _parseUpsertSecret(
          json,
          personIds: personIds,
          placeIds: placeIds,
          world: world,
        );

      case LivingWorldUpdateOp.closeSecret:
        final id = '${json['id'] ?? ''}'.trim();
        if (id.isEmpty || !world.secrets.any((s) => s.id == id)) return null;
        final text = world.secrets.firstWhere((s) => s.id == id).text;
        return LivingWorldCanonUpdate(
          op: op,
          summary: 'Close secret: $text',
          targetId: id,
        );

      case LivingWorldUpdateOp.setInventory:
        final personId = '${json['personId'] ?? ''}'.trim();
        if (!personIds.contains(personId)) return null;
        final items = <String>[];
        final rawItems = json['items'];
        if (rawItems is List) {
          for (final item in rawItems) {
            final v = '$item'.trim();
            if (v.isEmpty) continue;
            items.add(v);
            if (items.length >= maxInventoryItems) break;
          }
        }
        return LivingWorldCanonUpdate(
          op: op,
          summary:
              '${_nameOf(people, personId)} inventory: ${items.isEmpty ? '(empty)' : items.join(', ')}',
          personId: personId,
          inventoryItems: items,
        );
    }
  }

  LivingWorldCanonUpdate? _parseUpsertThread(
    Map<String, dynamic> json, {
    required Set<String> personIds,
    required Set<String> placeIds,
    required LivingWorld world,
  }) {
    final title = '${json['title'] ?? ''}'.trim();
    if (title.isEmpty) return null;
    var id = '${json['id'] ?? ''}'.trim();
    if (id.isEmpty) {
      // Reuse existing open thread with same title (case-insensitive).
      for (final t in world.threads) {
        if (t.isOpen && t.title.toLowerCase() == title.toLowerCase()) {
          id = t.id;
          break;
        }
      }
    }
    if (id.isEmpty) {
      id = 'th_${DateTime.now().microsecondsSinceEpoch}_${outHash(title)}';
    }
    final placeId = '${json['placeId'] ?? ''}'.trim();
    if (placeId.isNotEmpty && !placeIds.contains(placeId)) return null;
    final personIdsOut = _filterIds(json['personIds'], personIds);
    final witnessIds = _filterIds(json['witnessIds'], personIds);
    final status = WorldContinuityStatus.parse(json['status']);
    final summary = '${json['summary'] ?? ''}'.trim();
    final thread = WorldThread(
      id: id,
      title: title,
      summary: summary,
      status: status,
      personIds: personIdsOut,
      placeId: placeId.isEmpty ? null : placeId,
      witnessIds: witnessIds,
    );
    return LivingWorldCanonUpdate(
      op: LivingWorldUpdateOp.upsertThread,
      summary: '${status.wire} thread: $title',
      thread: thread,
    );
  }

  LivingWorldCanonUpdate? _parseUpsertPromise(
    Map<String, dynamic> json, {
    required Set<String> personIds,
    required Set<String> placeIds,
    required List<WorldPerson> people,
    required LivingWorld world,
  }) {
    final text = '${json['text'] ?? ''}'.trim();
    final fromId = '${json['fromId'] ?? ''}'.trim();
    final toId = '${json['toId'] ?? ''}'.trim();
    if (text.isEmpty ||
        !personIds.contains(fromId) ||
        !personIds.contains(toId)) {
      return null;
    }
    var id = '${json['id'] ?? ''}'.trim();
    if (id.isEmpty) {
      for (final p in world.promises) {
        if (p.isOpen &&
            p.fromId == fromId &&
            p.toId == toId &&
            p.text.toLowerCase() == text.toLowerCase()) {
          id = p.id;
          break;
        }
      }
    }
    if (id.isEmpty) {
      id = 'pr_${DateTime.now().microsecondsSinceEpoch}_${outHash(text)}';
    }
    final placeId = '${json['placeId'] ?? ''}'.trim();
    if (placeId.isNotEmpty && !placeIds.contains(placeId)) return null;
    final status = WorldContinuityStatus.parse(json['status']);
    final promise = WorldPromise(
      id: id,
      text: text,
      fromId: fromId,
      toId: toId,
      status: status,
      placeId: placeId.isEmpty ? null : placeId,
    );
    return LivingWorldCanonUpdate(
      op: LivingWorldUpdateOp.upsertPromise,
      summary:
          '${status.wire} promise: ${_nameOf(people, fromId)} → ${_nameOf(people, toId)}: $text',
      promise: promise,
    );
  }

  LivingWorldCanonUpdate? _parseUpsertSecret(
    Map<String, dynamic> json, {
    required Set<String> personIds,
    required Set<String> placeIds,
    required LivingWorld world,
  }) {
    final text = '${json['text'] ?? ''}'.trim();
    if (text.isEmpty) return null;
    var id = '${json['id'] ?? ''}'.trim();
    if (id.isEmpty) {
      for (final s in world.secrets) {
        if (s.isOpen && s.text.toLowerCase() == text.toLowerCase()) {
          id = s.id;
          break;
        }
      }
    }
    if (id.isEmpty) {
      id = 'sec_${DateTime.now().microsecondsSinceEpoch}_${outHash(text)}';
    }
    final placeId = '${json['placeId'] ?? ''}'.trim();
    if (placeId.isNotEmpty && !placeIds.contains(placeId)) return null;
    final status = WorldContinuityStatus.parse(json['status']);
    final secret = WorldSecret(
      id: id,
      text: text,
      status: status,
      subjectIds: _filterIds(json['subjectIds'], personIds),
      witnessIds: _filterIds(json['witnessIds'], personIds),
      placeId: placeId.isEmpty ? null : placeId,
    );
    return LivingWorldCanonUpdate(
      op: LivingWorldUpdateOp.upsertSecret,
      summary: '${status.wire} secret: $text',
      secret: secret,
    );
  }

  static List<String> _filterIds(Object? raw, Set<String> allowed) {
    if (raw is! List) return const [];
    final out = <String>[];
    for (final item in raw) {
      final id = '$item'.trim();
      if (id.isNotEmpty && allowed.contains(id)) out.add(id);
    }
    return out;
  }

  static String _nameOf(List<WorldPerson> people, String id) {
    for (final p in people) {
      if (p.id == id) return p.name;
    }
    return id;
  }

  static String _nameOfPlace(List<WorldPlace> places, String id) {
    for (final p in places) {
      if (p.id == id) return p.name;
    }
    return id;
  }

  static int outHash(String text) => text.hashCode & 0xffff;

  static String _slugPersonId(String name) {
    final slug = name
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    final stem = slug.isEmpty
        ? DateTime.now().microsecondsSinceEpoch.toString()
        : (slug.length > 32 ? slug.substring(0, 32) : slug);
    return 'p_$stem';
  }

  String _formatTranscript(List<ChatMessage> messages) {
    if (messages.isEmpty) return '(no recent messages)';
    final start = messages.length > maxTranscriptMessages
        ? messages.length - maxTranscriptMessages
        : 0;
    final buf = StringBuffer();
    for (var i = start; i < messages.length; i++) {
      final m = messages[i];
      final who = switch (m.role) {
        ChatRole.user => 'User',
        ChatRole.assistant =>
          m.speakerName?.trim().isNotEmpty == true
              ? m.speakerName!.trim()
              : 'Assistant',
        ChatRole.narrator => 'Narrator',
        ChatRole.director => 'Director',
        ChatRole.groupBeat => 'Group',
      };
      final text = m.text.trim();
      if (text.isEmpty) continue;
      buf.writeln('$who: $text');
    }
    final out = buf.toString().trim();
    return out.isEmpty ? '(no recent messages)' : out;
  }

  String _formatRoster(LivingWorld world) {
    final buf = StringBuffer();
    buf.writeln('People:');
    if (world.people.isEmpty) {
      buf.writeln('- (none)');
    } else {
      for (final p in world.people) {
        final inv = p.inventory.isEmpty
            ? ''
            : ' [items: ${p.inventory.join(', ')}]';
        buf.writeln('- ${p.id}: ${p.name}$inv');
      }
    }
    buf.writeln('Places:');
    if (world.places.isEmpty) {
      buf.writeln('- (none)');
    } else {
      for (final p in world.places) {
        buf.writeln('- ${p.id}: ${p.name}');
      }
    }
    return buf.toString().trimRight();
  }

  String _formatFlags(LivingWorld world) {
    if (world.flags.isEmpty) return '(none)';
    return [for (final f in world.flags) '- ${f.key}: ${f.value}'].join('\n');
  }

  String _formatOpenContinuity(LivingWorld world) {
    final buf = StringBuffer();
    final openThreads = world.threads.where((t) => t.isOpen).toList();
    final openPromises = world.promises.where((p) => p.isOpen).toList();
    final openSecrets = world.secrets.where((s) => s.isOpen).toList();
    if (openThreads.isEmpty && openPromises.isEmpty && openSecrets.isEmpty) {
      return '(none)';
    }
    if (openThreads.isNotEmpty) {
      buf.writeln('Threads:');
      for (final t in openThreads) {
        buf.writeln('- ${t.id}: ${t.title}');
      }
    }
    if (openPromises.isNotEmpty) {
      buf.writeln('Promises:');
      for (final p in openPromises) {
        buf.writeln('- ${p.id}: ${p.text} (${p.fromId}→${p.toId})');
      }
    }
    if (openSecrets.isNotEmpty) {
      buf.writeln('Secrets:');
      for (final s in openSecrets) {
        buf.writeln('- ${s.id}: ${s.text}');
      }
    }
    return buf.toString().trimRight();
  }

  String _formatRecentEvents(LivingWorld world) {
    if (world.events.isEmpty) return '(none)';
    final tail = world.events.length > 8
        ? world.events.sublist(world.events.length - 8)
        : world.events;
    return [for (final e in tail) '- ${e.text}'].join('\n');
  }
}
