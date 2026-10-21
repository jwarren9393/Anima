import 'dart:convert';

import '../models/chat_message.dart';
import '../models/living_world.dart';

/// One proposed change to Living World canon (never applied until review).
enum LivingWorldUpdateOp {
  addEvent,
  setFlag,
  setRelationship,
  setActivePlace,
  setPersonLocation,
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

  String get reviewLabel => switch (op) {
        LivingWorldUpdateOp.addEvent => 'Event',
        LivingWorldUpdateOp.setFlag => 'Flag',
        LivingWorldUpdateOp.setRelationship => 'Relationship',
        LivingWorldUpdateOp.setActivePlace => 'Active place',
        LivingWorldUpdateOp.setPersonLocation => 'Who / where',
      };

  String get reviewDetail => summary;

  /// Safe for Phase 5 auto-apply (still schema-validated). Relationships need OK.
  bool get isSafeForAutoApply => switch (op) {
        LivingWorldUpdateOp.addEvent ||
        LivingWorldUpdateOp.setFlag ||
        LivingWorldUpdateOp.setActivePlace ||
        LivingWorldUpdateOp.setPersonLocation =>
          true,
        LivingWorldUpdateOp.setRelationship => false,
      };
}

/// Propose structured canon updates from recent chat; apply only after review.
class LivingWorldUpdateService {
  const LivingWorldUpdateService();

  static const maxTranscriptMessages = 24;
  static const maxProposedUpdates = 12;

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
            '{"updates":[{"op":"addEvent|setFlag|setRelationship|setActivePlace|setPersonLocation",...}]}\n'
            '\n'
            'Rules:\n'
            '- Only propose facts clearly established or decided in the recent chat.\n'
            '- Do NOT invent new people or places. Use only ids from the roster.\n'
            '- Prefer short factual event text (who decided/did what, where).\n'
            '- Flags: stable keys like snake_case; value bool or short string.\n'
            '- Relationships: fromId/toId must be person ids; score -100..100; optional labels[].\n'
            '- setActivePlace: placeId from roster.\n'
            '- setPersonLocation: personId + placeId from roster.\n'
            '- Skip vibes, dialogue flavor, and things already in the notebook.\n'
            '- At most $maxProposedUpdates updates. Empty list is OK: {"updates":[]}.\n'
            '\n'
            'Field shapes:\n'
            'addEvent: {"op":"addEvent","text":"...","at":"optional","placeId":"optional","personIds":["..."]}\n'
            'setFlag: {"op":"setFlag","key":"...","value":true}\n'
            'setRelationship: {"op":"setRelationship","fromId":"...","toId":"...","score":0,"labels":["..."]}\n'
            'setActivePlace: {"op":"setActivePlace","placeId":"..."}\n'
            'setPersonLocation: {"op":"setPersonLocation","personId":"...","placeId":"..."}\n',
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
  LivingWorld applyUpdates(
    LivingWorld world,
    List<LivingWorldCanonUpdate> selected,
  ) {
    if (selected.isEmpty) return world;

    var people = List<WorldPerson>.from(world.people);
    var places = List<WorldPlace>.from(world.places);
    var relationships = List<WorldRelationship>.from(world.relationships);
    var events = List<WorldEvent>.from(world.events);
    var flags = List<WorldFlag>.from(world.flags);
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
            personLocations: {
              ...base.personLocations,
              personId: placeId,
            },
          );
      }
    }

    return LivingWorld(
      id: world.id,
      title: world.title,
      schemaVersion: world.schemaVersion,
      genreNote: world.genreNote,
      people: people,
      places: places,
      relationships: relationships,
      events: events,
      flags: flags,
      liveState: live,
    ).validated();
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
    }

    final parsed = _tryParseObject(text);
    if (parsed != null) return parsed;

    throw const FormatException(
      'Could not find Living World update JSON in the model reply.',
    );
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
  }) {
    final opRaw = '${json['op'] ?? ''}'.trim();
    final op = switch (opRaw) {
      'addEvent' => LivingWorldUpdateOp.addEvent,
      'setFlag' => LivingWorldUpdateOp.setFlag,
      'setRelationship' => LivingWorldUpdateOp.setRelationship,
      'setActivePlace' => LivingWorldUpdateOp.setActivePlace,
      'setPersonLocation' => LivingWorldUpdateOp.setPersonLocation,
      _ => null,
    };
    if (op == null) return null;

    switch (op) {
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
        return LivingWorldCanonUpdate(
          op: op,
          summary: text,
          event: event,
        );

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
        final score = (scoreRaw is int
                ? scoreRaw
                : int.tryParse('$scoreRaw') ?? 0)
            .clamp(-100, 100);
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
    }
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
        ChatRole.assistant => m.speakerName?.trim().isNotEmpty == true
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
        buf.writeln('- ${p.id}: ${p.name}');
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
    return [
      for (final f in world.flags) '- ${f.key}: ${f.value}',
    ].join('\n');
  }

  String _formatRecentEvents(LivingWorld world) {
    if (world.events.isEmpty) return '(none)';
    final tail = world.events.length > 8
        ? world.events.sublist(world.events.length - 8)
        : world.events;
    return [
      for (final e in tail) '- ${e.text}',
    ].join('\n');
  }
}
