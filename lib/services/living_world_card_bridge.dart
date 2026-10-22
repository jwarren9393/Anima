import '../models/character.dart';
import '../models/chat_session.dart';
import '../models/living_world.dart';
import '../models/persona.dart';

/// Phase 13 — turn Living World notebook people into Anima cards / bound chats.
///
/// Pure helpers (no network). AI drafting reuses [WorldWorkshopBuilder] plain-
/// English export + the usual review sheet in the UI.
class LivingWorldCardBridge {
  const LivingWorldCardBridge();

  /// Plain-English brief for Character & persona build prompts.
  String buildPersonBrief({
    required LivingWorld world,
    required WorldPerson person,
  }) {
    final buf = StringBuffer();
    buf.writeln('Living World notebook: ${world.title.trim()}');
    final genre = world.genreNote.trim();
    if (genre.isNotEmpty) {
      buf.writeln('Genre / tone: $genre');
    }
    buf.writeln();
    buf.writeln('Person id: ${person.id}');
    buf.writeln('Name: ${person.name.trim()}');
    final summary = person.summary.trim();
    if (summary.isNotEmpty) {
      buf.writeln('Summary: $summary');
    }
    final notes = person.personalityNotes.trim();
    if (notes.isNotEmpty) {
      buf.writeln('Personality notes: $notes');
    }
    final routine = person.routineHints.trim();
    if (routine.isNotEmpty) {
      buf.writeln('Routine hints: $routine');
    }
    if (person.inventory.isNotEmpty) {
      final items = [
        for (final item in person.inventory)
          if (item.trim().isNotEmpty) item.trim(),
      ];
      if (items.isNotEmpty) {
        buf.writeln('Inventory: ${items.join(', ')}');
      }
    }

    final placeId = world.liveState?.personLocations[person.id]?.trim();
    if (placeId != null && placeId.isNotEmpty) {
      final place = _placeById(world, placeId);
      buf.writeln(
        place == null
            ? 'Current place id: $placeId'
            : 'Current place: ${place.name.trim()} — ${place.description.trim()}',
      );
    }

    final links = <String>[];
    for (final rel in world.relationships) {
      if (rel.fromId != person.id && rel.toId != person.id) {
        continue;
      }
      final otherId = rel.fromId == person.id ? rel.toId : rel.fromId;
      final other = _personById(world, otherId);
      final otherName = other?.name.trim().isNotEmpty == true
          ? other!.name.trim()
          : otherId;
      final score = rel.score == 0 ? '' : ' (score ${rel.score})';
      final labels = rel.labels.isEmpty ? 'linked' : rel.labels.join(', ');
      links.add('$labels$score with $otherName');
    }
    if (links.isNotEmpty) {
      buf.writeln('Relationships:');
      for (final line in links.take(12)) {
        buf.writeln('- $line');
      }
    }

    return buf.toString().trim();
  }

  /// Maps notebook fields onto a playable character without calling the API.
  Character seedCharacterFromPerson(
    WorldPerson person, {
    required String id,
  }) {
    final name = person.name.trim().isEmpty ? 'Unnamed' : person.name.trim();
    final summary = person.summary.trim();
    final notes = person.personalityNotes.trim();
    final routine = person.routineHints.trim();
    final items = [
      for (final item in person.inventory)
        if (item.trim().isNotEmpty) item.trim(),
    ];

    final descriptionParts = <String>[
      if (summary.isNotEmpty) summary,
      if (routine.isNotEmpty) 'Routine: $routine',
      if (items.isNotEmpty) 'Carries: ${items.join(', ')}',
    ];

    return Character(
      id: id,
      name: name,
      description: descriptionParts.join('\n\n'),
      personality: notes,
      firstMes: summary.isEmpty
          ? '*I notice {{user}} nearby.*'
          : '*I regard {{user}}.*\n\n"${_firstSentence(summary)}"',
      creator: 'Anima Living World',
      creatorNotes: 'Drafted from Living World person ${person.id}',
    );
  }

  /// Maps notebook fields onto a {{user}} persona without calling the API.
  Persona seedPersonaFromPerson(
    WorldPerson person, {
    required String id,
  }) {
    final name = person.name.trim().isEmpty ? 'User' : person.name.trim();
    final summary = person.summary.trim();
    final notes = person.personalityNotes.trim();
    final routine = person.routineHints.trim();
    final items = [
      for (final item in person.inventory)
        if (item.trim().isNotEmpty) item.trim(),
    ];

    final backgroundParts = <String>[
      if (summary.isNotEmpty) summary,
      if (routine.isNotEmpty) 'Routine: $routine',
      if (items.isNotEmpty) 'Carries: ${items.join(', ')}',
    ];

    return Persona(
      id: id,
      name: name,
      description: summary.isEmpty ? notes : summary,
      personality: notes,
      background: backgroundParts.join('\n\n'),
    );
  }

  /// Sets [WorldPerson.characterCardId] for [personId]; no-op if missing.
  LivingWorld linkPersonToCharacter(
    LivingWorld world, {
    required String personId,
    required String characterId,
  }) {
    final id = personId.trim();
    final cardId = characterId.trim();
    if (id.isEmpty || cardId.isEmpty) return world;

    var changed = false;
    final people = <WorldPerson>[];
    for (final person in world.people) {
      if (person.id == id) {
        changed = true;
        people.add(person.copyWith(characterCardId: cardId));
      } else {
        people.add(person);
      }
    }
    if (!changed) return world;
    return world.copyWith(people: people);
  }

  /// Attaches a Living World bind to an existing session.
  ChatSession bindSessionToWorld(ChatSession session, String worldId) {
    final id = worldId.trim();
    if (id.isEmpty) return session;
    return session.copyWith(worldId: id);
  }

  WorldPerson? _personById(LivingWorld world, String id) {
    for (final person in world.people) {
      if (person.id == id) return person;
    }
    return null;
  }

  WorldPlace? _placeById(LivingWorld world, String id) {
    for (final place in world.places) {
      if (place.id == id) return place;
    }
    return null;
  }

  String _firstSentence(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return trimmed;
    final match = RegExp(r'^[^.!?]+[.!?]?' ).firstMatch(trimmed);
    final sentence = (match?.group(0) ?? trimmed).trim();
    if (sentence.length <= 160) return sentence;
    return '${sentence.substring(0, 157).trimRight()}…';
  }
}
