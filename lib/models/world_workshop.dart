import 'chat_message.dart';
import 'workshop_hub_models.dart';

/// How long Creation Center chat replies are allowed to be (max_tokens cap).
enum WorkshopReplyLength {
  short,
  normal,
  detailed;

  String get label => switch (this) {
        WorkshopReplyLength.short => 'Short',
        WorkshopReplyLength.normal => 'Normal',
        WorkshopReplyLength.detailed => 'Detailed',
      };

  String get subtitle => switch (this) {
        WorkshopReplyLength.short => 'Quick ideas · ~600 tokens',
        WorkshopReplyLength.normal => 'Balanced brainstorming · ~2K tokens',
        WorkshopReplyLength.detailed =>
          'Deep dive + questions · ~4K tokens',
      };

  static WorkshopReplyLength fromJson(dynamic raw) {
    return switch ('$raw'.trim().toLowerCase()) {
      'short' => WorkshopReplyLength.short,
      'detailed' => WorkshopReplyLength.detailed,
      _ => WorkshopReplyLength.normal,
    };
  }

  String toJson() => name;
}

/// Read-only source material when a workshop is seeded from an existing chat.
///
/// Kept separate from [WorldWorkshop.messages] so roleplay replies are never
/// mistaken for Creation Center collaborator turns.
class WorkshopSourceContext {
  const WorkshopSourceContext({
    required this.chatId,
    required this.chatTitle,
    required this.isGroup,
    this.memorySummary = '',
    this.recentTranscript = '',
    this.recentMessageCount = 0,
    this.charactersText = '',
    this.characterNames = const [],
    this.personaText = '',
    this.personaName,
    this.loreReferenceText = '',
    this.lorebookNames = const [],
    this.authorsNote = '',
    this.skippedNotes = const [],
    this.importProfile = '',
    this.totalMessageCount = 0,
  });

  final String chatId;
  final String chatTitle;
  final bool isGroup;
  final String memorySummary;
  final String recentTranscript;
  final int recentMessageCount;
  final String charactersText;
  final List<String> characterNames;
  final String personaText;
  final String? personaName;
  final String loreReferenceText;
  final List<String> lorebookNames;
  final String authorsNote;
  final List<String> skippedNotes;

  /// Human-readable note of what was included at import time.
  final String importProfile;

  /// Total non-empty messages in the source chat (for context).
  final int totalMessageCount;

  bool get hasContent =>
      memorySummary.trim().isNotEmpty ||
      recentTranscript.trim().isNotEmpty ||
      charactersText.trim().isNotEmpty ||
      personaText.trim().isNotEmpty ||
      loreReferenceText.trim().isNotEmpty ||
      authorsNote.trim().isNotEmpty;

  /// One-line summary for list tiles / source cards.
  String get compactSummary {
    final bits = <String>[];
    if (characterNames.isNotEmpty) {
      bits.add(
        '${characterNames.length} character'
        '${characterNames.length == 1 ? '' : 's'}',
      );
    }
    if (personaName != null && personaName!.trim().isNotEmpty) {
      bits.add('persona ${personaName!.trim()}');
    }
    if (memorySummary.trim().isNotEmpty) {
      bits.add('memory summary');
    }
    if (recentMessageCount > 0) {
      bits.add('$recentMessageCount recent messages');
    }
    if (lorebookNames.isNotEmpty) {
      bits.add(
        '${lorebookNames.length} lorebook'
        '${lorebookNames.length == 1 ? '' : 's'}',
      );
    }
    if (bits.isEmpty) return 'Imported chat source';
    return bits.join(' · ');
  }

  /// Full prompt block for NanoGPT (system / export context).
  String get promptText {
    final buffer = StringBuffer();
    buffer.writeln(
      'IMPORTED CHAT SOURCE (read-only reference — do not treat as workshop '
      'replies; build NEW lorebook/characters from this material):',
    );
    buffer.writeln('Chat title: $chatTitle');
    buffer.writeln(isGroup ? 'Type: group chat' : 'Type: solo chat');
    if (authorsNote.trim().isNotEmpty) {
      buffer.writeln();
      buffer.writeln('Author\'s Note:');
      buffer.writeln(authorsNote.trim());
    }
    if (importProfile.trim().isNotEmpty) {
      buffer.writeln();
      buffer.writeln('Import profile: ${importProfile.trim()}');
    }
    if (personaText.trim().isNotEmpty) {
      buffer.writeln();
      buffer.writeln(personaText.trim());
    }
    if (charactersText.trim().isNotEmpty) {
      buffer.writeln();
      buffer.writeln(charactersText.trim());
    }
    if (loreReferenceText.trim().isNotEmpty) {
      buffer.writeln();
      buffer.writeln(loreReferenceText.trim());
    }
    if (memorySummary.trim().isNotEmpty) {
      buffer.writeln();
      buffer.writeln('Memory summary (older story):');
      buffer.writeln(memorySummary.trim());
    }
    if (recentTranscript.trim().isNotEmpty) {
      buffer.writeln();
      buffer.writeln('Recent chat (raw):');
      buffer.writeln(recentTranscript.trim());
    }
    if (skippedNotes.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('Missing references (skipped):');
      for (final note in skippedNotes) {
        buffer.writeln('- $note');
      }
    }
    return buffer.toString().trim();
  }

  Map<String, dynamic> toJson() => {
        'chatId': chatId,
        'chatTitle': chatTitle,
        'isGroup': isGroup,
        if (memorySummary.trim().isNotEmpty) 'memorySummary': memorySummary,
        if (recentTranscript.trim().isNotEmpty)
          'recentTranscript': recentTranscript,
        'recentMessageCount': recentMessageCount,
        if (charactersText.trim().isNotEmpty) 'charactersText': charactersText,
        if (characterNames.isNotEmpty) 'characterNames': characterNames,
        if (personaText.trim().isNotEmpty) 'personaText': personaText,
        if (personaName != null && personaName!.trim().isNotEmpty)
          'personaName': personaName,
        if (loreReferenceText.trim().isNotEmpty)
          'loreReferenceText': loreReferenceText,
        if (lorebookNames.isNotEmpty) 'lorebookNames': lorebookNames,
        if (authorsNote.trim().isNotEmpty) 'authorsNote': authorsNote,
        if (skippedNotes.isNotEmpty) 'skippedNotes': skippedNotes,
        if (importProfile.trim().isNotEmpty) 'importProfile': importProfile,
        if (totalMessageCount > 0) 'totalMessageCount': totalMessageCount,
      };

  factory WorkshopSourceContext.fromJson(Map<String, dynamic> json) {
    List<String> stringList(dynamic raw) {
      if (raw is! List) return const [];
      return [
        for (final item in raw)
          if ('$item'.trim().isNotEmpty) '$item'.trim(),
      ];
    }

    return WorkshopSourceContext(
      chatId: '${json['chatId'] ?? ''}'.trim(),
      chatTitle: ('${json['chatTitle'] ?? ''}').trim().isEmpty
          ? 'Imported chat'
          : ('${json['chatTitle']}').trim(),
      isGroup: json['isGroup'] == true,
      memorySummary: '${json['memorySummary'] ?? ''}'.trim(),
      recentTranscript: '${json['recentTranscript'] ?? ''}'.trim(),
      recentMessageCount:
          (json['recentMessageCount'] as num?)?.toInt().clamp(0, 100000) ?? 0,
      charactersText: '${json['charactersText'] ?? ''}'.trim(),
      characterNames: stringList(json['characterNames']),
      personaText: '${json['personaText'] ?? ''}'.trim(),
      personaName: ('${json['personaName'] ?? ''}').trim().isEmpty
          ? null
          : ('${json['personaName']}').trim(),
      loreReferenceText: '${json['loreReferenceText'] ?? ''}'.trim(),
      lorebookNames: stringList(json['lorebookNames']),
      authorsNote: '${json['authorsNote'] ?? ''}'.trim(),
      skippedNotes: stringList(json['skippedNotes']),
      importProfile: '${json['importProfile'] ?? ''}'.trim(),
      totalMessageCount:
          (json['totalMessageCount'] as num?)?.toInt().clamp(0, 100000) ?? 0,
    );
  }
}

/// One Creation Center workshop: a plain AI chat that builds toward one lorebook.
class WorldWorkshop {
  const WorldWorkshop({
    required this.id,
    required this.title,
    required this.messages,
    required this.updatedAt,
    this.exportedLorebookId,
    this.importedSource,
    this.replyLength = WorkshopReplyLength.normal,
    this.includeLinkedLorebookInPrompt = false,
    this.pinned = false,
    this.tags = const [],
    this.coverFileName,
    this.worldSummary = '',
    this.worldOverview = '',
    this.worldSummaryCoveredCount = 0,
    this.canonPinMessageIds = const [],
    this.mode = WorkshopMode.explore,
    this.workshopGuidanceNote = '',
    this.linkedCharacterIds = const [],
    this.linkedPersonaId,
    this.lorebookUpdatedAtMessageCount = 0,
    this.chatKit = const WorkshopChatKit(),
    this.locations = const [],
    this.relationships = const [],
    this.sceneIdeas = const [],
  });

  final String id;

  /// Shown in the workshop list (often the emerging world name).
  final String title;

  final List<ChatMessage> messages;
  final DateTime updatedAt;

  /// When set, this workshop already produced a global lorebook with this id.
  /// Creating again can update that same book.
  final String? exportedLorebookId;

  /// Optional seed from an existing roleplay chat (read-only reference).
  final WorkshopSourceContext? importedSource;

  /// Reply length preset for workshop brainstorming chat (not exports).
  final WorkshopReplyLength replyLength;

  /// When false (default), the saved lorebook is not re-sent on every chat turn.
  /// The workshop transcript is usually enough; turn on only if you want the AI
  /// to read the exported book while brainstorming.
  final bool includeLinkedLorebookInPrompt;

  /// Pinned workshops sort to the top of the Creation Center list.
  final bool pinned;

  /// Genre / tone tags for filtering (e.g. Fantasy, Horror).
  final List<String> tags;

  /// Optional cover image under app avatars/ (Anima-only).
  final String? coverFileName;

  /// Editable running summary of the workshop (like chat memory summary).
  final String worldSummary;

  /// Auto-generated one-page world bible (overview doc).
  final String worldOverview;

  /// Messages [0..worldSummaryCoveredCount) are folded into [worldSummary] for API
  /// prompts — same idea as [ChatSession.memoryCoveredCount].
  final int worldSummaryCoveredCount;

  /// Message ids pinned as canon — always injected into exports.
  final List<String> canonPinMessageIds;

  /// Brainstorm mode / intent for the collaborator AI.
  final WorkshopMode mode;

  /// Per-workshop override of global collaborator guidance (empty = use global).
  final String workshopGuidanceNote;

  /// Character ids saved from or linked to this workshop.
  final List<String> linkedCharacterIds;

  /// Persona id created for this world (optional).
  final String? linkedPersonaId;

  /// [messages].length when lorebook was last created/updated (stale detection).
  final int lorebookUpdatedAtMessageCount;

  /// Defaults when starting roleplay from this workshop.
  final WorkshopChatKit chatKit;

  final List<WorkshopLocation> locations;
  final List<WorkshopRelationship> relationships;
  final List<WorkshopSceneIdea> sceneIdeas;

  int get messagesSinceLorebookUpdate {
    if (lorebookUpdatedAtMessageCount <= 0) return messages.length;
    return (messages.length - lorebookUpdatedAtMessageCount).clamp(0, 100000);
  }

  bool get isLorebookStale =>
      exportedLorebookId != null &&
      messagesSinceLorebookUpdate >= 8 &&
      messages.isNotEmpty;

  WorldWorkshop copyWith({
    String? id,
    String? title,
    List<ChatMessage>? messages,
    DateTime? updatedAt,
    String? exportedLorebookId,
    bool clearExportedLorebookId = false,
    WorkshopSourceContext? importedSource,
    bool clearImportedSource = false,
    WorkshopReplyLength? replyLength,
    bool? includeLinkedLorebookInPrompt,
    bool? pinned,
    List<String>? tags,
    String? coverFileName,
    bool clearCoverFileName = false,
    String? worldSummary,
    String? worldOverview,
    int? worldSummaryCoveredCount,
    List<String>? canonPinMessageIds,
    WorkshopMode? mode,
    String? workshopGuidanceNote,
    List<String>? linkedCharacterIds,
    String? linkedPersonaId,
    bool clearLinkedPersonaId = false,
    int? lorebookUpdatedAtMessageCount,
    WorkshopChatKit? chatKit,
    List<WorkshopLocation>? locations,
    List<WorkshopRelationship>? relationships,
    List<WorkshopSceneIdea>? sceneIdeas,
  }) {
    return WorldWorkshop(
      id: id ?? this.id,
      title: title ?? this.title,
      messages: messages ?? this.messages,
      updatedAt: updatedAt ?? this.updatedAt,
      exportedLorebookId: clearExportedLorebookId
          ? null
          : (exportedLorebookId ?? this.exportedLorebookId),
      importedSource: clearImportedSource
          ? null
          : (importedSource ?? this.importedSource),
      replyLength: replyLength ?? this.replyLength,
      includeLinkedLorebookInPrompt: includeLinkedLorebookInPrompt ??
          this.includeLinkedLorebookInPrompt,
      pinned: pinned ?? this.pinned,
      tags: tags ?? this.tags,
      coverFileName:
          clearCoverFileName ? null : (coverFileName ?? this.coverFileName),
      worldSummary: worldSummary ?? this.worldSummary,
      worldOverview: worldOverview ?? this.worldOverview,
      worldSummaryCoveredCount:
          worldSummaryCoveredCount ?? this.worldSummaryCoveredCount,
      canonPinMessageIds: canonPinMessageIds ?? this.canonPinMessageIds,
      mode: mode ?? this.mode,
      workshopGuidanceNote: workshopGuidanceNote ?? this.workshopGuidanceNote,
      linkedCharacterIds: linkedCharacterIds ?? this.linkedCharacterIds,
      linkedPersonaId: clearLinkedPersonaId
          ? null
          : (linkedPersonaId ?? this.linkedPersonaId),
      lorebookUpdatedAtMessageCount:
          lorebookUpdatedAtMessageCount ?? this.lorebookUpdatedAtMessageCount,
      chatKit: chatKit ?? this.chatKit,
      locations: locations ?? this.locations,
      relationships: relationships ?? this.relationships,
      sceneIdeas: sceneIdeas ?? this.sceneIdeas,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'messages': messages.map((m) => m.toJson()).toList(),
        'updatedAt': updatedAt.toIso8601String(),
        if (exportedLorebookId != null && exportedLorebookId!.isNotEmpty)
          'exportedLorebookId': exportedLorebookId,
        if (importedSource != null) 'importedSource': importedSource!.toJson(),
        'replyLength': replyLength.toJson(),
        'includeLinkedLorebookInPrompt': includeLinkedLorebookInPrompt,
        if (pinned) 'pinned': true,
        if (tags.isNotEmpty) 'tags': tags,
        if (coverFileName != null && coverFileName!.isNotEmpty)
          'coverFileName': coverFileName,
        if (worldSummary.trim().isNotEmpty) 'worldSummary': worldSummary,
        if (worldOverview.trim().isNotEmpty) 'worldOverview': worldOverview,
        if (worldSummaryCoveredCount > 0)
          'worldSummaryCoveredCount': worldSummaryCoveredCount,
        if (canonPinMessageIds.isNotEmpty)
          'canonPinMessageIds': canonPinMessageIds,
        if (mode != WorkshopMode.explore) 'mode': mode.toJson(),
        if (workshopGuidanceNote.trim().isNotEmpty)
          'workshopGuidanceNote': workshopGuidanceNote,
        if (linkedCharacterIds.isNotEmpty)
          'linkedCharacterIds': linkedCharacterIds,
        if (linkedPersonaId != null && linkedPersonaId!.isNotEmpty)
          'linkedPersonaId': linkedPersonaId,
        if (lorebookUpdatedAtMessageCount > 0)
          'lorebookUpdatedAtMessageCount': lorebookUpdatedAtMessageCount,
        if (chatKit != const WorkshopChatKit()) 'chatKit': chatKit.toJson(),
        if (locations.isNotEmpty)
          'locations': locations.map((l) => l.toJson()).toList(),
        if (relationships.isNotEmpty)
          'relationships': relationships.map((r) => r.toJson()).toList(),
        if (sceneIdeas.isNotEmpty)
          'sceneIdeas': sceneIdeas.map((s) => s.toJson()).toList(),
      };

  factory WorldWorkshop.fromJson(Map<String, dynamic> json) {
    final rawMessages = json['messages'];
    final messages = <ChatMessage>[];
    if (rawMessages is List) {
      for (final item in rawMessages) {
        if (item is Map) {
          messages.add(
            ChatMessage.fromJson(Map<String, dynamic>.from(item)),
          );
        }
      }
    }

    WorkshopSourceContext? imported;
    final rawSource = json['importedSource'];
    if (rawSource is Map) {
      imported = WorkshopSourceContext.fromJson(
        Map<String, dynamic>.from(rawSource),
      );
    }

    List<String> stringList(dynamic raw) {
      if (raw is! List) return const [];
      return [
        for (final item in raw)
          if ('$item'.trim().isNotEmpty) '$item'.trim(),
      ];
    }

    List<WorkshopLocation> parseLocations(dynamic raw) {
      if (raw is! List) return const [];
      return [
        for (final item in raw)
          if (item is Map)
            WorkshopLocation.fromJson(Map<String, dynamic>.from(item)),
      ];
    }

    List<WorkshopRelationship> parseRelationships(dynamic raw) {
      if (raw is! List) return const [];
      return [
        for (final item in raw)
          if (item is Map)
            WorkshopRelationship.fromJson(Map<String, dynamic>.from(item)),
      ];
    }

    List<WorkshopSceneIdea> parseSceneIdeas(dynamic raw) {
      if (raw is! List) return const [];
      return [
        for (final item in raw)
          if (item is Map)
            WorkshopSceneIdea.fromJson(Map<String, dynamic>.from(item)),
      ];
    }

    final updatedRaw = json['updatedAt'] as String?;
    final personaRaw = '${json['linkedPersonaId'] ?? ''}'.trim();
    final coverRaw = '${json['coverFileName'] ?? ''}'.trim();
  final chatKitRaw = json['chatKit'];
    return WorldWorkshop(
      id: '${json['id'] ?? ''}'.trim().isEmpty
          ? newId()
          : '${json['id']}'.trim(),
      title: ('${json['title'] ?? ''}').trim().isEmpty
          ? 'New workshop'
          : ('${json['title']}').trim(),
      messages: messages,
      updatedAt: updatedRaw == null
          ? DateTime.now()
          : (DateTime.tryParse(updatedRaw) ?? DateTime.now()),
      exportedLorebookId:
          ('${json['exportedLorebookId'] ?? ''}').trim().isEmpty
              ? null
              : ('${json['exportedLorebookId']}').trim(),
      importedSource: imported,
      replyLength: WorkshopReplyLength.fromJson(json['replyLength']),
      includeLinkedLorebookInPrompt:
          json['includeLinkedLorebookInPrompt'] == true,
      pinned: json['pinned'] == true,
      tags: stringList(json['tags']),
      coverFileName: coverRaw.isEmpty ? null : coverRaw,
      worldSummary: '${json['worldSummary'] ?? ''}'.trim(),
      worldOverview: '${json['worldOverview'] ?? ''}'.trim(),
      worldSummaryCoveredCount:
          (json['worldSummaryCoveredCount'] as num?)?.toInt().clamp(
                0,
                100000,
              ) ??
              0,
      canonPinMessageIds: stringList(json['canonPinMessageIds']),
      mode: WorkshopMode.fromJson(json['mode']),
      workshopGuidanceNote: '${json['workshopGuidanceNote'] ?? ''}'.trim(),
      linkedCharacterIds: stringList(json['linkedCharacterIds']),
      linkedPersonaId: personaRaw.isEmpty ? null : personaRaw,
      lorebookUpdatedAtMessageCount:
          (json['lorebookUpdatedAtMessageCount'] as num?)?.toInt().clamp(
                0,
                100000,
              ) ??
              0,
      chatKit: chatKitRaw is Map
          ? WorkshopChatKit.fromJson(Map<String, dynamic>.from(chatKitRaw))
          : const WorkshopChatKit(),
      locations: parseLocations(json['locations']),
      relationships: parseRelationships(json['relationships']),
      sceneIdeas: parseSceneIdeas(json['sceneIdeas']),
    );
  }

  static String newId() => 'ws_${DateTime.now().millisecondsSinceEpoch}';

  static WorldWorkshop empty({String title = 'New workshop'}) {
    return WorldWorkshop(
      id: newId(),
      title: title,
      messages: const [],
      updatedAt: DateTime.now(),
    );
  }
}
