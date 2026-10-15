import '../models/chat_message.dart';
import '../models/living_world.dart';

/// Selects a small Living World pack for prompt injection (no embeddings).
///
/// Relevance: name mentions in recent chat + speaker/user names, active place,
/// linked relationships/events/flags — capped by a rough token budget.
class LivingWorldRetriever {
  const LivingWorldRetriever();

  /// Default budget for the injected pack (~chars / 4 ≈ tokens).
  static const defaultTokenBudget = 1200;

  /// How many recent messages to scan for name mentions.
  static const defaultScanDepth = 12;

  LivingWorldPack retrieve({
    required LivingWorld world,
    required List<ChatMessage> recentMessages,
    String speakerName = '',
    String userName = '',
    int tokenBudget = defaultTokenBudget,
    int scanDepth = defaultScanDepth,
  }) {
    final budget = tokenBudget.clamp(200, 8000);
    final haystack = _buildHaystack(
      messages: recentMessages,
      scanDepth: scanDepth,
      speakerName: speakerName,
      userName: userName,
    );

    final peopleById = {for (final p in world.people) p.id: p};
    final placesById = {for (final p in world.places) p.id: p};

    final matchedPeople = <WorldPerson>[];
    for (final person in world.people) {
      if (_nameInHaystack(person.name, haystack)) {
        matchedPeople.add(person);
      }
    }

    // Always try to include a person who matches the speaking character card name.
    if (speakerName.trim().isNotEmpty) {
      for (final person in world.people) {
        if (_namesMatch(person.name, speakerName) &&
            !matchedPeople.any((p) => p.id == person.id)) {
          matchedPeople.add(person);
        }
      }
    }

    final matchedPlaces = <WorldPlace>[];
    for (final place in world.places) {
      if (_nameInHaystack(place.name, haystack)) {
        matchedPlaces.add(place);
      }
    }

    final live = world.liveState;
    if (live?.activePlaceId != null) {
      final active = placesById[live!.activePlaceId];
      if (active != null && !matchedPlaces.any((p) => p.id == active.id)) {
        matchedPlaces.insert(0, active);
      }
    }

    // Connected places (one hop) for matched places.
    final placeIds = {for (final p in matchedPlaces) p.id};
    for (final place in List<WorldPlace>.from(matchedPlaces)) {
      for (final id in place.connectedPlaceIds) {
        if (placeIds.contains(id)) continue;
        final connected = placesById[id];
        if (connected == null) continue;
        matchedPlaces.add(connected);
        placeIds.add(id);
      }
    }

    final personIds = {for (final p in matchedPeople) p.id};

    final relationships = <WorldRelationship>[];
    for (final rel in world.relationships) {
      if (personIds.contains(rel.fromId) || personIds.contains(rel.toId)) {
        relationships.add(rel);
        // Pull the other side into the cast briefly.
        for (final otherId in [rel.fromId, rel.toId]) {
          if (personIds.contains(otherId)) continue;
          final other = peopleById[otherId];
          if (other == null) continue;
          matchedPeople.add(other);
          personIds.add(otherId);
        }
      }
    }

    final events = <WorldEvent>[];
    for (final event in world.events.reversed) {
      final hitPerson = event.personIds.any(personIds.contains);
      final hitPlace =
          event.placeId != null && placeIds.contains(event.placeId);
      final hitText = _anyNameInText(
        event.text,
        [
          ...matchedPeople.map((p) => p.name),
          ...matchedPlaces.map((p) => p.name),
        ],
      );
      if (hitPerson || hitPlace || hitText) {
        events.add(event);
      }
    }

    final flags = <WorldFlag>[];
    for (final flag in world.flags) {
      final keyHay = flag.key.toLowerCase();
      var hit = false;
      for (final person in matchedPeople) {
        if (keyHay.contains(person.name.toLowerCase()) ||
            _nameInHaystack(person.name, keyHay)) {
          hit = true;
          break;
        }
      }
      if (!hit) {
        for (final place in matchedPlaces) {
          if (keyHay.contains(place.name.toLowerCase())) {
            hit = true;
            break;
          }
        }
      }
      // Also include flags whose key appears in recent chat.
      if (!hit && haystack.contains(keyHay)) hit = true;
      if (hit) flags.add(flag);
    }

    // If nothing matched, still give a tiny world header + active place.
    if (matchedPeople.isEmpty &&
        matchedPlaces.isEmpty &&
        events.isEmpty &&
        flags.isEmpty) {
      return LivingWorldPack(
        worldTitle: world.title,
        genreNote: world.genreNote,
        people: const [],
        places: live?.activePlaceId != null
            ? [
                if (placesById[live!.activePlaceId] != null)
                  placesById[live.activePlaceId]!,
              ]
            : const [],
        relationships: const [],
        events: const [],
        flags: const [],
        liveState: live,
      ).fitBudget(budget);
    }

    return LivingWorldPack(
      worldTitle: world.title,
      genreNote: world.genreNote,
      people: matchedPeople,
      places: matchedPlaces,
      relationships: relationships,
      events: events.take(12).toList(),
      flags: flags,
      liveState: live,
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
  }) {
    final depth = scanDepth.clamp(1, 40);
    final start = messages.length > depth ? messages.length - depth : 0;
    final buf = StringBuffer();
    if (speakerName.trim().isNotEmpty) buf.writeln(speakerName);
    if (userName.trim().isNotEmpty) buf.writeln(userName);
    for (var i = start; i < messages.length; i++) {
      final m = messages[i];
      buf.writeln(m.speakerName ?? '');
      buf.writeln(m.text);
    }
    return buf.toString().toLowerCase();
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
  });

  final String worldTitle;
  final String genreNote;
  final List<WorldPerson> people;
  final List<WorldPlace> places;
  final List<WorldRelationship> relationships;
  final List<WorldEvent> events;
  final List<WorldFlag> flags;
  final WorldLiveState? liveState;

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
        final placeName = _lookupName(places, active);
        buf.writeln(
          'Active place id: $active'
          '${placeName != null ? ' ($placeName)' : ''}',
        );
      }
      if (liveState!.personLocations.isNotEmpty) {
        buf.writeln('Who is where (tracked):');
        for (final entry in liveState!.personLocations.entries) {
          final personName = _lookupPersonName(people, entry.key);
          final placeName = _lookupName(places, entry.value);
          buf.writeln(
            '- ${personName ?? entry.key} @ ${placeName ?? entry.value}',
          );
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
      buf.writeln('People:');
      for (final person in people) {
        buf.write('- ${person.name}');
        final bits = <String>[
          if (person.summary.trim().isNotEmpty) person.summary.trim(),
          if (person.personalityNotes.trim().isNotEmpty)
            person.personalityNotes.trim(),
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

  /// Drop lower-priority rows until roughly under [tokenBudget].
  LivingWorldPack fitBudget(int tokenBudget) {
    var pack = this;
    while (_estimateTokens(pack.renderBody()) > tokenBudget) {
      if (pack.events.length > 3) {
        pack = LivingWorldPack(
          worldTitle: pack.worldTitle,
          genreNote: pack.genreNote,
          people: pack.people,
          places: pack.places,
          relationships: pack.relationships,
          events: pack.events.sublist(0, pack.events.length - 1),
          flags: pack.flags,
          liveState: pack.liveState,
        );
        continue;
      }
      if (pack.flags.length > 2) {
        pack = LivingWorldPack(
          worldTitle: pack.worldTitle,
          genreNote: pack.genreNote,
          people: pack.people,
          places: pack.places,
          relationships: pack.relationships,
          events: pack.events,
          flags: pack.flags.sublist(0, pack.flags.length - 1),
          liveState: pack.liveState,
        );
        continue;
      }
      if (pack.relationships.length > 2) {
        pack = LivingWorldPack(
          worldTitle: pack.worldTitle,
          genreNote: pack.genreNote,
          people: pack.people,
          places: pack.places,
          relationships:
              pack.relationships.sublist(0, pack.relationships.length - 1),
          events: pack.events,
          flags: pack.flags,
          liveState: pack.liveState,
        );
        continue;
      }
      if (pack.people.length > 2) {
        pack = LivingWorldPack(
          worldTitle: pack.worldTitle,
          genreNote: pack.genreNote,
          people: pack.people.sublist(0, pack.people.length - 1),
          places: pack.places,
          relationships: pack.relationships,
          events: pack.events,
          flags: pack.flags,
          liveState: pack.liveState,
        );
        continue;
      }
      if (pack.places.length > 1) {
        pack = LivingWorldPack(
          worldTitle: pack.worldTitle,
          genreNote: pack.genreNote,
          people: pack.people,
          places: pack.places.sublist(0, pack.places.length - 1),
          relationships: pack.relationships,
          events: pack.events,
          flags: pack.flags,
          liveState: pack.liveState,
        );
        continue;
      }
      break;
    }
    return pack;
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
