import '../models/chat_message.dart';
import '../models/living_world.dart';

/// Selects a small Living World pack for prompt injection (no embeddings).
///
/// Phase 3 cast-scale: score people/places by speaker, card link, name
/// mentions, active/scene place, and relationships — then keep only the top
/// scraps inside a token budget. Large notebooks (dozens of people) stay mostly
/// off-prompt; only relevant cast members are injected.
class LivingWorldRetriever {
  const LivingWorldRetriever();

  /// Default budget for the injected pack (~chars / 4 ≈ tokens).
  static const defaultTokenBudget = 1200;

  /// How many recent messages to scan for name mentions.
  static const defaultScanDepth = 12;

  /// Hard caps so a 50-person world never dumps into the prompt.
  static const maxPeople = 8;
  static const maxPlaces = 5;
  static const maxRelationships = 8;
  static const maxEvents = 10;
  static const maxFlags = 8;

  LivingWorldPack retrieve({
    required LivingWorld world,
    required List<ChatMessage> recentMessages,
    String speakerName = '',
    String userName = '',
    /// Anima character card id for the speaker (boosts linked world people).
    String speakerCharacterId = '',
    /// Extra names to treat as scene cast (group chats).
    List<String> castNames = const [],
    int tokenBudget = defaultTokenBudget,
    int scanDepth = defaultScanDepth,
  }) {
    final budget = tokenBudget.clamp(200, 8000);
    final haystack = _buildHaystack(
      messages: recentMessages,
      scanDepth: scanDepth,
      speakerName: speakerName,
      userName: userName,
      castNames: castNames,
    );

    final peopleById = {for (final p in world.people) p.id: p};
    final placesById = {for (final p in world.places) p.id: p};
    final live = world.liveState;
    final activePlaceId = live?.activePlaceId;

    // --- Score places ---
    final placeScores = <String, int>{};
    for (final place in world.places) {
      var score = 0;
      if (activePlaceId != null && place.id == activePlaceId) score += 80;
      if (_nameInHaystack(place.name, haystack)) score += 50;
      if (score > 0) placeScores[place.id] = score;
    }

    // One-hop connections from already-scored places (weaker).
    for (final placeId in List<String>.from(placeScores.keys)) {
      final place = placesById[placeId];
      if (place == null) continue;
      for (final id in place.connectedPlaceIds) {
        if (placeScores.containsKey(id)) continue;
        if (!placesById.containsKey(id)) continue;
        placeScores[id] = 20;
      }
    }

    // --- Score people ---
    final personScores = <String, int>{};
    for (final person in world.people) {
      var score = 0;
      if (_namesMatch(person.name, speakerName)) score += 100;
      final cardId = person.characterCardId?.trim() ?? '';
      if (cardId.isNotEmpty &&
          speakerCharacterId.trim().isNotEmpty &&
          cardId == speakerCharacterId.trim()) {
        score += 90;
      }
      if (_nameInHaystack(person.name, haystack)) score += 50;
      for (final castName in castNames) {
        if (_namesMatch(person.name, castName)) {
          score += 35;
          break;
        }
      }
      final atPlace = live?.personLocations[person.id];
      // Only the active scene place boosts people — one-hop places stay in the
      // places list without pulling every neighbor into the cast pack.
      if (atPlace != null &&
          activePlaceId != null &&
          atPlace == activePlaceId) {
        score += 40;
      } else if (atPlace != null &&
          placeScores.containsKey(atPlace) &&
          (placeScores[atPlace] ?? 0) >= 50) {
        // Mentioned places (not mere connections) can pull someone in lightly.
        score += 25;
      }
      if (score > 0) personScores[person.id] = score;
    }

    // Soft-pull relationship neighbors of *strongly* relevant people only
    // (mentioned / speaker / card). Place-only presence does not expand the
    // whole acquaintance graph — that would defeat cast scale.
    final coreIds = personScores.entries
        .where((e) => e.value >= 50)
        .map((e) => e.key)
        .toSet();

    if (coreIds.isNotEmpty) {
      for (final rel in world.relationships) {
        final fromCore = coreIds.contains(rel.fromId);
        final toCore = coreIds.contains(rel.toId);
        if (!fromCore && !toCore) continue;
        final otherId = fromCore ? rel.toId : rel.fromId;
        if (personScores.containsKey(otherId)) {
          personScores[otherId] = personScores[otherId]! + 10;
          continue;
        }
        if (!peopleById.containsKey(otherId)) continue;
        final absScore = rel.score.abs();
        personScores[otherId] = 22 + (absScore ~/ 20).clamp(0, 8);
      }
    }

    // Rank and cap.
    final rankedPeople = _rankByScore(personScores)
        .where(peopleById.containsKey)
        .take(maxPeople)
        .map((id) => peopleById[id]!)
        .toList();
    final rankedPlaces = _rankByScore(placeScores)
        .where(placesById.containsKey)
        .take(maxPlaces)
        .map((id) => placesById[id]!)
        .toList();

    // Always prefer active place at the front when present.
    if (activePlaceId != null && placesById.containsKey(activePlaceId)) {
      rankedPlaces.removeWhere((p) => p.id == activePlaceId);
      rankedPlaces.insert(0, placesById[activePlaceId]!);
      if (rankedPlaces.length > maxPlaces) {
        rankedPlaces.removeRange(maxPlaces, rankedPlaces.length);
      }
    }

    final personIds = {for (final p in rankedPeople) p.id};
    final placeIds = {for (final p in rankedPlaces) p.id};

    // Relationships among selected people; prefer ones touching core/speaker.
    final scoredRels = <({WorldRelationship rel, int score})>[];
    for (final rel in world.relationships) {
      if (!personIds.contains(rel.fromId) || !personIds.contains(rel.toId)) {
        continue;
      }
      var score = 10 + rel.score.abs() ~/ 10;
      if (coreIds.contains(rel.fromId) || coreIds.contains(rel.toId)) {
        score += 20;
      }
      if (_personIsSpeaker(peopleById[rel.fromId], speakerName,
              speakerCharacterId) ||
          _personIsSpeaker(
              peopleById[rel.toId], speakerName, speakerCharacterId)) {
        score += 30;
      }
      scoredRels.add((rel: rel, score: score));
    }
    scoredRels.sort((a, b) => b.score.compareTo(a.score));
    final relationships = [
      for (final row in scoredRels.take(maxRelationships)) row.rel,
    ];

    // Events: score by overlap with selected cast/places + recency.
    final eventRows = <({WorldEvent event, int score})>[];
    final eventCount = world.events.length;
    for (var i = 0; i < eventCount; i++) {
      final event = world.events[i];
      final recency = i; // higher index = more recent if appended chronologically
      var score = recency; // slight recency bias among equals
      final hitPerson = event.personIds.any(personIds.contains);
      final hitPlace =
          event.placeId != null && placeIds.contains(event.placeId);
      final hitText = _anyNameInText(
        event.text,
        [
          ...rankedPeople.map((p) => p.name),
          ...rankedPlaces.map((p) => p.name),
        ],
      );
      if (hitPerson) score += 40;
      if (hitPlace) score += 30;
      if (hitText) score += 20;
      if (!hitPerson && !hitPlace && !hitText) continue;
      eventRows.add((event: event, score: score));
    }
    eventRows.sort((a, b) => b.score.compareTo(a.score));
    final events = [
      for (final row in eventRows.take(maxEvents)) row.event,
    ];

    final flags = <WorldFlag>[];
    for (final flag in world.flags) {
      final keyHay = flag.key.toLowerCase();
      var hit = false;
      for (final person in rankedPeople) {
        if (keyHay.contains(person.name.toLowerCase()) ||
            _nameInHaystack(person.name, keyHay)) {
          hit = true;
          break;
        }
      }
      if (!hit) {
        for (final place in rankedPlaces) {
          if (keyHay.contains(place.name.toLowerCase())) {
            hit = true;
            break;
          }
        }
      }
      if (!hit && haystack.contains(keyHay)) hit = true;
      if (hit) flags.add(flag);
      if (flags.length >= maxFlags) break;
    }

    // If nothing matched, still give a tiny world header + active place.
    if (rankedPeople.isEmpty &&
        rankedPlaces.isEmpty &&
        events.isEmpty &&
        flags.isEmpty) {
      return LivingWorldPack(
        worldTitle: world.title,
        genreNote: world.genreNote,
        people: const [],
        places: activePlaceId != null && placesById.containsKey(activePlaceId)
            ? [placesById[activePlaceId]!]
            : const [],
        relationships: const [],
        events: const [],
        flags: const [],
        liveState: live,
        speakingPersonId: _findSpeakingPersonId(
          world.people,
          speakerName: speakerName,
          speakerCharacterId: speakerCharacterId,
        ),
      ).fitBudget(budget);
    }

    // Prefer mentioning the speaking person first in the pack order.
    final speakingId = _findSpeakingPersonId(
      rankedPeople,
      speakerName: speakerName,
      speakerCharacterId: speakerCharacterId,
    );
    if (speakingId != null) {
      final idx = rankedPeople.indexWhere((p) => p.id == speakingId);
      if (idx > 0) {
        final speaker = rankedPeople.removeAt(idx);
        rankedPeople.insert(0, speaker);
      }
    }

    return LivingWorldPack(
      worldTitle: world.title,
      genreNote: world.genreNote,
      people: rankedPeople,
      places: rankedPlaces,
      relationships: relationships,
      events: events,
      flags: flags,
      liveState: live,
      speakingPersonId: speakingId,
    ).fitBudget(budget);
  }

  /// Prompt block for an early system message. Empty when pack is useless.
  String formatForPrompt(LivingWorldPack pack) {
    final body = pack.renderBody();
    if (body.trim().isEmpty) return '';
    return 'Living World memory (authoritative canon — do not invent or '
        'overwrite these tracked facts; roleplay from them):\n$body';
  }

  String _buildHaystack({
    required List<ChatMessage> messages,
    required int scanDepth,
    required String speakerName,
    required String userName,
    required List<String> castNames,
  }) {
    final depth = scanDepth.clamp(1, 40);
    final start = messages.length > depth ? messages.length - depth : 0;
    final buf = StringBuffer();
    if (speakerName.trim().isNotEmpty) buf.writeln(speakerName);
    if (userName.trim().isNotEmpty) buf.writeln(userName);
    for (final name in castNames) {
      if (name.trim().isNotEmpty) buf.writeln(name);
    }
    for (var i = start; i < messages.length; i++) {
      final m = messages[i];
      buf.writeln(m.speakerName ?? '');
      buf.writeln(m.text);
    }
    return buf.toString().toLowerCase();
  }

  List<String> _rankByScore(Map<String, int> scores) {
    final entries = scores.entries.toList()
      ..sort((a, b) {
        final byScore = b.value.compareTo(a.value);
        if (byScore != 0) return byScore;
        return a.key.compareTo(b.key);
      });
    return [for (final e in entries) e.key];
  }

  bool _personIsSpeaker(
    WorldPerson? person,
    String speakerName,
    String speakerCharacterId,
  ) {
    if (person == null) return false;
    if (_namesMatch(person.name, speakerName)) return true;
    final card = person.characterCardId?.trim() ?? '';
    return card.isNotEmpty &&
        speakerCharacterId.trim().isNotEmpty &&
        card == speakerCharacterId.trim();
  }

  String? _findSpeakingPersonId(
    List<WorldPerson> people, {
    required String speakerName,
    required String speakerCharacterId,
  }) {
    for (final person in people) {
      final card = person.characterCardId?.trim() ?? '';
      if (card.isNotEmpty &&
          speakerCharacterId.trim().isNotEmpty &&
          card == speakerCharacterId.trim()) {
        return person.id;
      }
    }
    for (final person in people) {
      if (_namesMatch(person.name, speakerName)) return person.id;
    }
    return null;
  }

  bool _nameInHaystack(String name, String haystackLower) {
    final n = name.trim().toLowerCase();
    if (n.length < 2) return false;
    return haystackLower.contains(n);
  }

  bool _namesMatch(String a, String b) {
    final left = a.trim().toLowerCase();
    final right = b.trim().toLowerCase();
    if (left.isEmpty || right.isEmpty) return false;
    return left == right || left.contains(right) || right.contains(left);
  }

  bool _anyNameInText(String text, List<String> names) {
    final lower = text.toLowerCase();
    for (final name in names) {
      if (_nameInHaystack(name, lower)) return true;
    }
    return false;
  }
}

/// Retrieved scraps ready to format (and trim to budget).
class LivingWorldPack {
  const LivingWorldPack({
    required this.worldTitle,
    this.genreNote = '',
    this.people = const [],
    this.places = const [],
    this.relationships = const [],
    this.events = const [],
    this.flags = const [],
    this.liveState,
    this.speakingPersonId,
  });

  final String worldTitle;
  final String genreNote;
  final List<WorldPerson> people;
  final List<WorldPlace> places;
  final List<WorldRelationship> relationships;
  final List<WorldEvent> events;
  final List<WorldFlag> flags;
  final WorldLiveState? liveState;

  /// World person id for the current speaker when known (prompt marks them).
  final String? speakingPersonId;

  bool get isEmpty =>
      people.isEmpty &&
      places.isEmpty &&
      relationships.isEmpty &&
      events.isEmpty &&
      flags.isEmpty &&
      (liveState == null ||
          ((liveState!.activePlaceId == null ||
                  liveState!.activePlaceId!.isEmpty) &&
              liveState!.personLocations.isEmpty));

  String renderBody() {
    final buf = StringBuffer();
    buf.writeln('World: $worldTitle');
    if (genreNote.trim().isNotEmpty) {
      buf.writeln('Setting note: ${genreNote.trim()}');
    }

    if (liveState != null) {
      final active = liveState!.activePlaceId;
      if (active != null && active.isNotEmpty) {
        final placeName = _lookupName(places, active) ??
            _lookupNameFromLiveOnly(active);
        buf.writeln(
          'Active place id: $active'
          '${placeName != null ? ' ($placeName)' : ''}',
        );
      }
      if (liveState!.personLocations.isNotEmpty) {
        // Only list who/where for people already in this pack (cast scale).
        final relevant = liveState!.personLocations.entries.where(
          (e) => people.any((p) => p.id == e.key),
        );
        if (relevant.isNotEmpty) {
          buf.writeln('Who is where (tracked, relevant):');
          for (final entry in relevant) {
            final personName = _lookupPersonName(people, entry.key);
            final placeName = _lookupName(places, entry.value);
            buf.writeln(
              '- ${personName ?? entry.key} @ ${placeName ?? entry.value}',
            );
          }
        }
      }
    }

    if (places.isNotEmpty) {
      buf.writeln('Places:');
      for (final place in places) {
        buf.write('- ${place.name}');
        if (place.description.trim().isNotEmpty) {
          buf.write(': ${place.description.trim()}');
        }
        buf.writeln();
      }
    }

    if (people.isNotEmpty) {
      buf.writeln('People (relevant only — many more exist off-scene):');
      for (final person in people) {
        buf.write('- ${person.name}');
        if (speakingPersonId != null && person.id == speakingPersonId) {
          buf.write(' [speaking]');
        }
        if (person.characterCardId != null &&
            person.characterCardId!.trim().isNotEmpty) {
          buf.write(' [linked card]');
        }
        final bits = <String>[
          if (person.summary.trim().isNotEmpty) person.summary.trim(),
          if (person.personalityNotes.trim().isNotEmpty)
            person.personalityNotes.trim(),
          if (person.routineHints.trim().isNotEmpty)
            'routine: ${person.routineHints.trim()}',
        ];
        if (bits.isNotEmpty) buf.write(': ${bits.join(' · ')}');
        buf.writeln();
      }
    }

    if (relationships.isNotEmpty) {
      buf.writeln('Relationships:');
      for (final rel in relationships) {
        final from = _nameOrId(people, rel.fromId);
        final to = _nameOrId(people, rel.toId);
        final labels =
            rel.labels.isEmpty ? '' : ' (${rel.labels.join(', ')})';
        buf.writeln('- $from → $to: ${rel.score}$labels');
      }
    }

    if (events.isNotEmpty) {
      buf.writeln('Events:');
      for (final event in events) {
        final when = (event.at ?? '').trim();
        buf.write('- ');
        if (when.isNotEmpty) buf.write('[$when] ');
        buf.writeln(event.text.trim());
      }
    }

    if (flags.isNotEmpty) {
      buf.writeln('Flags:');
      for (final flag in flags) {
        buf.writeln('- ${flag.key}: ${flag.value}');
      }
    }

    return buf.toString().trimRight();
  }

  String? _lookupNameFromLiveOnly(String id) {
    // Places list may already include it; helper kept for clarity.
    return _lookupName(places, id);
  }

  /// Drop lower-priority rows until roughly under [tokenBudget].
  /// Lists are expected highest-priority first; we trim from the end.
  LivingWorldPack fitBudget(int tokenBudget) {
    var pack = this;
    while (_estimateTokens(pack.renderBody()) > tokenBudget) {
      if (pack.events.length > 3) {
        pack = pack._copyWith(events: pack.events.sublist(0, pack.events.length - 1));
        continue;
      }
      if (pack.flags.length > 2) {
        pack = pack._copyWith(flags: pack.flags.sublist(0, pack.flags.length - 1));
        continue;
      }
      if (pack.relationships.length > 2) {
        pack = pack._copyWith(
          relationships:
              pack.relationships.sublist(0, pack.relationships.length - 1),
        );
        continue;
      }
      if (pack.people.length > 2) {
        // People are highest-priority first (speaker at front); trim the tail.
        pack = pack._copyWith(
          people: pack.people.sublist(0, pack.people.length - 1),
        );
        continue;
      }
      if (pack.places.length > 1) {
        pack = pack._copyWith(
          places: pack.places.sublist(0, pack.places.length - 1),
        );
        continue;
      }
      break;
    }
    return pack;
  }

  LivingWorldPack _copyWith({
    List<WorldPerson>? people,
    List<WorldPlace>? places,
    List<WorldRelationship>? relationships,
    List<WorldEvent>? events,
    List<WorldFlag>? flags,
  }) {
    return LivingWorldPack(
      worldTitle: worldTitle,
      genreNote: genreNote,
      people: people ?? this.people,
      places: places ?? this.places,
      relationships: relationships ?? this.relationships,
      events: events ?? this.events,
      flags: flags ?? this.flags,
      liveState: liveState,
      speakingPersonId: speakingPersonId,
    );
  }

  static int _estimateTokens(String text) =>
      text.isEmpty ? 0 : (text.length / 4).ceil();

  static String _nameOrId(List<WorldPerson> people, String id) {
    return _lookupPersonName(people, id) ?? id;
  }

  static String? _lookupPersonName(List<WorldPerson> people, String id) {
    for (final p in people) {
      if (p.id == id) return p.name;
    }
    return null;
  }

  static String? _lookupName(List<WorldPlace> places, String id) {
    for (final p in places) {
      if (p.id == id) return p.name;
    }
    return null;
  }
}
