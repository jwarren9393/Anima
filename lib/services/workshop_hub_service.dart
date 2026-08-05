import 'dart:convert';

import '../models/character.dart';
import '../models/chat_session.dart';
import '../models/global_lorebook.dart';
import '../models/persona.dart';
import '../models/world_workshop.dart';
import '../models/workshop_chat_import_options.dart';
import '../models/workshop_hub_models.dart';
import 'world_workshop_builder.dart';

/// Creation Center hub operations — play world, status, bundle export, merge.
class WorkshopHubService {
  WorkshopHubService({WorldWorkshopBuilder? builder})
    : _builder = builder ?? WorldWorkshopBuilder();

  final WorldWorkshopBuilder _builder;

  WorkshopHubStatus computeStatus({
    required WorldWorkshop workshop,
    required List<Character> allCharacters,
    required List<ChatSession> workshopChats,
    GlobalLorebook? linkedLorebook,
  }) {
    final linkedIds = workshop.linkedCharacterIds;
    final fromWorkshopChars = allCharacters
        .where(
          (c) => linkedIds.contains(c.id) || c.sourceWorkshopId == workshop.id,
        )
        .length;

    String lorebookState;
    if (workshop.exportedLorebookId == null) {
      lorebookState = workshop.messages.isEmpty ? 'none' : 'draft';
    } else if (linkedLorebook == null) {
      lorebookState = 'missing';
    } else {
      lorebookState = workshop.isLorebookStale ? 'stale' : 'linked';
    }

    return WorkshopHubStatus(
      lorebookState: lorebookState,
      characterCount: fromWorkshopChars,
      personaLinked: workshop.linkedPersonaId != null,
      sourceChatTitle: workshop.importedSource?.chatTitle,
      roleplayChatCount: workshopChats.length,
      messagesSinceLorebookUpdate: workshop.messagesSinceLorebookUpdate,
      isLorebookStale: workshop.isLorebookStale,
      hasWorldSummary: workshop.worldSummary.trim().isNotEmpty,
      canonPinCount: workshop.canonPinMessageIds.length,
      sceneIdeaCount: workshop.sceneIdeas.length,
    );
  }

  /// Rule-based pre-export checklist (no API).
  List<String> localExportChecklist(WorldWorkshop workshop) {
    final items = <String>[];
    if (workshop.messages.isEmpty &&
        (workshop.importedSource?.hasContent != true)) {
      items.add('No workshop chat or imported source yet.');
    }
    if (workshop.exportedLorebookId != null && workshop.isLorebookStale) {
      items.add(
        '${workshop.messagesSinceLorebookUpdate} messages since last lorebook update.',
      );
    }
    if (workshop.canonPinMessageIds.isEmpty && workshop.messages.length > 15) {
      items.add(
        'Consider pinning key facts as canon before a big lorebook export.',
      );
    }
    return items;
  }

  WorldWorkshop linkCharacter(WorldWorkshop workshop, String characterId) {
    final id = characterId.trim();
    if (id.isEmpty) return workshop;
    if (workshop.linkedCharacterIds.contains(id)) return workshop;
    return workshop.copyWith(
      linkedCharacterIds: [...workshop.linkedCharacterIds, id],
    );
  }

  WorldWorkshop unlinkCharacter(WorldWorkshop workshop, String characterId) {
    return workshop.copyWith(
      linkedCharacterIds: [
        for (final id in workshop.linkedCharacterIds)
          if (id != characterId) id,
      ],
    );
  }

  WorldWorkshop toggleCanonPin(WorldWorkshop workshop, String messageId) {
    final id = messageId.trim();
    if (id.isEmpty) return workshop;
    final pins = List<String>.from(workshop.canonPinMessageIds);
    if (pins.contains(id)) {
      pins.remove(id);
    } else {
      pins.add(id);
    }
    return workshop.copyWith(canonPinMessageIds: pins);
  }

  /// Duplicate workshop (new id, copies metadata but not linked lorebook id).
  WorldWorkshop duplicate(WorldWorkshop workshop) {
    return WorldWorkshop(
      id: WorldWorkshop.newId(),
      title: '${workshop.title.trim()} (copy)',
      messages: workshop.messages,
      updatedAt: DateTime.now(),
      importedSource: workshop.importedSource,
      replyLength: workshop.replyLength,
      includeLinkedLorebookInPrompt: workshop.includeLinkedLorebookInPrompt,
      pinned: false,
      tags: workshop.tags,
      worldSummary: workshop.worldSummary,
      worldOverview: workshop.worldOverview,
      canonPinMessageIds: workshop.canonPinMessageIds,
      mode: workshop.mode,
      workshopGuidanceNote: workshop.workshopGuidanceNote,
      chatKit: workshop.chatKit,
      locations: workshop.locations,
      relationships: workshop.relationships,
      sceneIdeas: workshop.sceneIdeas,
    );
  }

  /// Merge two workshops into a new one (messages from A then B, combined metadata).
  WorldWorkshop merge(WorldWorkshop primary, WorldWorkshop secondary) {
    final combinedMessages = [...primary.messages, ...secondary.messages];
    final combinedPins = [
      ...primary.canonPinMessageIds,
      ...secondary.canonPinMessageIds,
    ];
    final combinedChars = [
      ...primary.linkedCharacterIds,
      ...secondary.linkedCharacterIds,
    ];
    final combinedTags = [...primary.tags, ...secondary.tags];
    final combinedLocations = [...primary.locations, ...secondary.locations];
    final combinedRels = [...primary.relationships, ...secondary.relationships];
    final combinedScenes = [...primary.sceneIdeas, ...secondary.sceneIdeas];

    return WorldWorkshop(
      id: WorldWorkshop.newId(),
      title: '${primary.title.trim()} + ${secondary.title.trim()}',
      messages: combinedMessages,
      updatedAt: DateTime.now(),
      replyLength: primary.replyLength,
      tags: combinedTags,
      worldSummary: [
        primary.worldSummary.trim(),
        secondary.worldSummary.trim(),
      ].where((s) => s.isNotEmpty).join('\n\n'),
      worldOverview: primary.worldOverview.trim().isNotEmpty
          ? primary.worldOverview
          : secondary.worldOverview,
      canonPinMessageIds: combinedPins,
      mode: primary.mode,
      workshopGuidanceNote: primary.workshopGuidanceNote,
      linkedCharacterIds: combinedChars,
      linkedPersonaId: primary.linkedPersonaId ?? secondary.linkedPersonaId,
      chatKit: primary.chatKit,
      locations: combinedLocations,
      relationships: combinedRels,
      sceneIdeas: combinedScenes,
      importedSource: primary.importedSource ?? secondary.importedSource,
    );
  }

  /// Play this world — resolve cast, lore, and persona from workshop kit.
  Future<PlayWorldPlan> buildPlayWorldPlan({
    required WorldWorkshop workshop,
    required List<Character> allCharacters,
    required Persona? defaultPersona,
    GlobalLorebook? linkedLorebook,
  }) async {
    final kit = workshop.chatKit;
    final castOrder = kit.defaultCastOrder.isNotEmpty
        ? kit.defaultCastOrder
        : workshop.linkedCharacterIds;

    final cast = <Character>[];
    for (final id in castOrder) {
      Character? found;
      for (final ch in allCharacters) {
        if (ch.id == id) {
          found = ch;
          break;
        }
      }
      if (found != null) cast.add(found);
    }
    if (cast.isEmpty) {
      for (final id in workshop.linkedCharacterIds) {
        Character? found;
        for (final ch in allCharacters) {
          if (ch.id == id) {
            found = ch;
            break;
          }
        }
        if (found != null) cast.add(found);
      }
    }
    for (final c in allCharacters) {
      if (c.sourceWorkshopId == workshop.id && !cast.any((x) => x.id == c.id)) {
        cast.add(c);
      }
    }

    List<String>? lorebookIds;
    if (kit.defaultLorebookEnabled &&
        workshop.exportedLorebookId != null &&
        linkedLorebook != null) {
      lorebookIds = [linkedLorebook.id];
    }

    return PlayWorldPlan(
      characters: cast,
      personaId: kit.defaultPersonaId ?? workshop.linkedPersonaId,
      lorebookIds: lorebookIds,
      authorsNote: kit.defaultAuthorsNote.trim().isNotEmpty
          ? kit.defaultAuthorsNote
          : _defaultAuthorsNoteFromWorkshop(workshop),
      autoReply: kit.autoReply,
      title: workshop.title.trim().isNotEmpty ? workshop.title.trim() : null,
      sourceWorkshopId: workshop.id,
    );
  }

  String _defaultAuthorsNoteFromWorkshop(WorldWorkshop workshop) {
    if (workshop.worldSummary.trim().isNotEmpty) {
      return 'World context: ${workshop.worldSummary.trim()}';
    }
    return '';
  }

  /// Export workshop as shareable bundle JSON (no API key).
  Map<String, dynamic> exportBundle({
    required WorldWorkshop workshop,
    List<Character>? characters,
    GlobalLorebook? lorebook,
    Persona? persona,
  }) {
    return {
      'type': 'anima_world_bundle',
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'workshop': workshop.toJson(),
      if (lorebook != null) 'lorebook': lorebook.toJson(),
      if (characters != null && characters.isNotEmpty)
        'characters': characters.map((c) => c.toJson()).toList(),
      if (persona != null) 'persona': persona.toJson(),
    };
  }

  String encodeBundle(Map<String, dynamic> bundle) {
    return const JsonEncoder.withIndent('  ').convert(bundle);
  }

  /// Import bundle — returns parsed parts (caller saves via services).
  WorkshopBundleImport parseBundle(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException('Bundle must be a JSON object.');
    }
    final map = Map<String, dynamic>.from(decoded);
    final type = '${map['type'] ?? ''}'.trim();
    if (type != 'anima_world_bundle') {
      throw const FormatException('Not an Anima world bundle file.');
    }

    final workshopRaw = map['workshop'];
    if (workshopRaw is! Map) {
      throw const FormatException('Bundle missing workshop data.');
    }
    final workshop =
        WorldWorkshop.fromJson(Map<String, dynamic>.from(workshopRaw)).copyWith(
          id: WorldWorkshop.newId(),
          exportedLorebookId: null,
          clearExportedLorebookId: true,
        );

    GlobalLorebook? lorebook;
    final loreRaw = map['lorebook'];
    if (loreRaw is Map) {
      lorebook = GlobalLorebook.fromJson(Map<String, dynamic>.from(loreRaw));
    }

    final characters = <Character>[];
    final charsRaw = map['characters'];
    if (charsRaw is List) {
      for (final item in charsRaw) {
        if (item is Map) {
          characters.add(Character.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }

    Persona? persona;
    final personaRaw = map['persona'];
    if (personaRaw is Map) {
      persona = Persona.fromJson(Map<String, dynamic>.from(personaRaw));
    }

    return WorkshopBundleImport(
      workshop: workshop,
      lorebook: lorebook,
      characters: characters,
      persona: persona,
    );
  }

  /// Refresh imported source from a linked roleplay chat (merge new material).
  WorkshopSourceContext? refreshSourceFromChat({
    required WorldWorkshop workshop,
    required ChatSession chat,
    required List<Character> characters,
    Persona? persona,
    List<GlobalLorebook> linkedLorebooks = const [],
    WorkshopChatImportOptions? options,
  }) {
    final opts = options ?? WorkshopChatImportOptions.defaults;
    return _builder.buildImportedChatSource(
      session: chat,
      characters: characters,
      persona: persona,
      linkedLorebooks: linkedLorebooks,
      skippedNotes: const [],
      options: opts,
    );
  }
}

class PlayWorldPlan {
  const PlayWorldPlan({
    required this.characters,
    this.personaId,
    this.lorebookIds,
    this.authorsNote = '',
    this.autoReply = false,
    this.title,
    this.sourceWorkshopId,
  });

  final List<Character> characters;
  final String? personaId;
  final List<String>? lorebookIds;
  final String authorsNote;
  final bool autoReply;
  final String? title;
  final String? sourceWorkshopId;

  bool get canPlayGroup => characters.length >= 2;
  bool get canPlaySolo => characters.isNotEmpty;
}

class WorkshopBundleImport {
  const WorkshopBundleImport({
    required this.workshop,
    this.lorebook,
    this.characters = const [],
    this.persona,
  });

  final WorldWorkshop workshop;
  final GlobalLorebook? lorebook;
  final List<Character> characters;
  final Persona? persona;
}
