import 'chat_message.dart';

/// One saved conversation (solo or group) — SillyTavern-style chat thread.
class ChatSession {
  ChatSession({
    required this.id,
    required this.characterId,
    required this.title,
    required this.updatedAt,
    List<ChatMessage>? messages,
    this.authorsNote = '',
    List<String>? participantIds,
    this.nextSpeakerIndex = 0,
    this.personaId,
    this.autoReply = false,
    List<String>? lorebookIds,
    this.memorySummary = '',
    this.memoryCoveredCount = 0,
    this.openingScene = '',
    this.openingSceneInPrompt = true,
    this.openingSceneInMemory = false,
    this.sourceWorkshopId,
    this.pendingDirectorMessageId,
    this.pendingDirectorAssistantId,
  })  : messages = List<ChatMessage>.from(messages ?? const []),
        participantIds = List<String>.from(participantIds ?? const []),
        lorebookIds =
            lorebookIds == null ? null : List<String>.from(lorebookIds);

  final String id;

  /// Solo: the character id. Group: storage bucket id (see [ChatService.groupsKey]).
  final String characterId;

  final String title;
  final DateTime updatedAt;
  final List<ChatMessage> messages;

  /// Chat-level instructions (SillyTavern Author's Note) — injected each turn.
  final String authorsNote;

  /// Group members (character ids). Empty / single = solo chat with [characterId].
  final List<String> participantIds;

  /// Round-robin index into [participantIds] for who speaks next in a group.
  final int nextSpeakerIndex;

  /// Which user persona (`{{user}}`) this chat uses. Null = app default.
  final String? personaId;

  /// When true, sending a message also generates an AI reply. When false,
  /// your message is saved only — tap a name (group) or Continue to reply.
  /// New chats default to off; older saves without this field stay on.
  final bool autoReply;

  /// Global lorebook ids active for this chat.
  ///
  /// `null` = use every lorebook that is enabled in World Info settings.
  /// A list (even empty) = only those books (chat override).
  final List<String>? lorebookIds;

  /// Running memory of older turns (editable). Injected into prompts when set.
  final String memorySummary;

  /// How many leading messages from [messages] are already folded into
  /// [memorySummary] (those can be skipped when packing recent history).
  final int memoryCoveredCount;

  /// Optional narrator/setup prose shown at the top of the chat (not stored in
  /// [messages] and not tied to a character greeting).
  final String openingScene;

  /// When true, [openingScene] is injected into API prompts (default on).
  /// Turn off via the chat ⋮ menu to save tokens.
  final bool openingSceneInPrompt;

  /// True after the opening scene has been folded into [memorySummary] once.
  final bool openingSceneInMemory;

  /// Creation Center workshop this chat was started from (provenance).
  final String? sourceWorkshopId;

  /// Director note id that still commands the next AI generation (regen/swipe too).
  final String? pendingDirectorMessageId;

  /// Assistant message id this director note is bound to (regen/swipe only).
  final String? pendingDirectorAssistantId;

  bool get isGroup => participantIds.length > 1;

  /// Effective cast for prompting (falls back to [characterId] when solo).
  List<String> get effectiveParticipantIds {
    if (participantIds.isNotEmpty) return participantIds;
    if (characterId.isEmpty) return const [];
    return [characterId];
  }

  ChatSession copyWith({
    String? id,
    String? characterId,
    String? title,
    DateTime? updatedAt,
    List<ChatMessage>? messages,
    String? authorsNote,
    List<String>? participantIds,
    int? nextSpeakerIndex,
    String? personaId,
    bool clearPersonaId = false,
    bool? autoReply,
    List<String>? lorebookIds,
    bool clearLorebookIds = false,
    String? memorySummary,
    int? memoryCoveredCount,
    String? openingScene,
    bool? openingSceneInPrompt,
    bool? openingSceneInMemory,
    String? sourceWorkshopId,
    bool clearSourceWorkshopId = false,
    String? pendingDirectorMessageId,
    bool clearPendingDirector = false,
    String? pendingDirectorAssistantId,
    bool clearPendingDirectorAssistant = false,
  }) {
    return ChatSession(
      id: id ?? this.id,
      characterId: characterId ?? this.characterId,
      title: title ?? this.title,
      updatedAt: updatedAt ?? this.updatedAt,
      messages: messages ?? this.messages,
      authorsNote: authorsNote ?? this.authorsNote,
      participantIds: participantIds ?? this.participantIds,
      nextSpeakerIndex: nextSpeakerIndex ?? this.nextSpeakerIndex,
      personaId: clearPersonaId ? null : (personaId ?? this.personaId),
      autoReply: autoReply ?? this.autoReply,
      lorebookIds: clearLorebookIds ? null : (lorebookIds ?? this.lorebookIds),
      memorySummary: memorySummary ?? this.memorySummary,
      memoryCoveredCount: memoryCoveredCount ?? this.memoryCoveredCount,
      openingScene: openingScene ?? this.openingScene,
      openingSceneInPrompt:
          openingSceneInPrompt ?? this.openingSceneInPrompt,
      openingSceneInMemory:
          openingSceneInMemory ?? this.openingSceneInMemory,
      sourceWorkshopId: clearSourceWorkshopId
          ? null
          : (sourceWorkshopId ?? this.sourceWorkshopId),
      pendingDirectorMessageId: clearPendingDirector
          ? null
          : (pendingDirectorMessageId ?? this.pendingDirectorMessageId),
      pendingDirectorAssistantId: clearPendingDirector ||
              clearPendingDirectorAssistant
          ? null
          : (pendingDirectorAssistantId ?? this.pendingDirectorAssistantId),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'characterId': characterId,
        'title': title,
        'updatedAt': updatedAt.toIso8601String(),
        'messages': messages.map((m) => m.toJson()).toList(),
        'authorsNote': authorsNote,
        'participantIds': participantIds,
        'nextSpeakerIndex': nextSpeakerIndex,
        if (personaId != null && personaId!.isNotEmpty) 'personaId': personaId,
        'autoReply': autoReply,
        if (lorebookIds != null) 'lorebookIds': lorebookIds,
        if (memorySummary.trim().isNotEmpty) 'memorySummary': memorySummary,
        if (memoryCoveredCount > 0) 'memoryCoveredCount': memoryCoveredCount,
        if (openingScene.trim().isNotEmpty) 'openingScene': openingScene,
        if (!openingSceneInPrompt) 'openingSceneInPrompt': false,
        if (openingSceneInMemory) 'openingSceneInMemory': true,
        if (sourceWorkshopId != null && sourceWorkshopId!.isNotEmpty)
          'sourceWorkshopId': sourceWorkshopId,
        if (pendingDirectorMessageId != null &&
            pendingDirectorMessageId!.isNotEmpty)
          'pendingDirectorMessageId': pendingDirectorMessageId,
        if (pendingDirectorAssistantId != null &&
            pendingDirectorAssistantId!.isNotEmpty)
          'pendingDirectorAssistantId': pendingDirectorAssistantId,
      };

  factory ChatSession.fromJson(Map<String, dynamic> json) {
    final rawMessages = json['messages'];
    final messages = <ChatMessage>[];
    if (rawMessages is List) {
      for (final item in rawMessages) {
        if (item is Map) {
          messages.add(ChatMessage.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }

    final participants = <String>[];
    final rawParts = json['participantIds'];
    if (rawParts is List) {
      for (final item in rawParts) {
        final id = '$item'.trim();
        if (id.isNotEmpty) participants.add(id);
      }
    }

    List<String>? lorebookIds;
    if (json.containsKey('lorebookIds')) {
      final rawLore = json['lorebookIds'];
      lorebookIds = <String>[];
      if (rawLore is List) {
        for (final item in rawLore) {
          final id = '$item'.trim();
          if (id.isNotEmpty) lorebookIds.add(id);
        }
      }
    }

    final personaRaw = '${json['personaId'] ?? ''}'.trim();
    final autoReplyRaw = json['autoReply'];
    final autoReply = autoReplyRaw == null
        ? true
        : autoReplyRaw == true || autoReplyRaw == 'true' || autoReplyRaw == 1;

    final covered = json['memoryCoveredCount'];
    final coveredCount = covered is int
        ? covered
        : int.tryParse('$covered') ?? 0;

    return ChatSession(
      id: json['id'] as String? ?? '',
      characterId: json['characterId'] as String? ?? '',
      title: (json['title'] as String? ?? 'Chat').trim().isEmpty
          ? 'Chat'
          : (json['title'] as String).trim(),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
      messages: messages,
      authorsNote: (json['authorsNote'] as String? ?? '').trim(),
      participantIds: participants,
      nextSpeakerIndex: json['nextSpeakerIndex'] as int? ?? 0,
      personaId: personaRaw.isEmpty ? null : personaRaw,
      autoReply: autoReply,
      lorebookIds: lorebookIds,
      memorySummary: (json['memorySummary'] as String? ?? '').trim(),
      memoryCoveredCount: coveredCount.clamp(0, 100000),
      openingScene: (json['openingScene'] as String? ?? '').trim(),
      openingSceneInPrompt: json['openingSceneInPrompt'] != false,
      openingSceneInMemory: json['openingSceneInMemory'] == true,
      sourceWorkshopId: () {
        final raw = '${json['sourceWorkshopId'] ?? ''}'.trim();
        return raw.isEmpty ? null : raw;
      }(),
      pendingDirectorMessageId: () {
        final raw = '${json['pendingDirectorMessageId'] ?? ''}'.trim();
        return raw.isEmpty ? null : raw;
      }(),
      pendingDirectorAssistantId: () {
        final raw = '${json['pendingDirectorAssistantId'] ?? ''}'.trim();
        return raw.isEmpty ? null : raw;
      }(),
    );
  }

  static String newId() => 'chat_${DateTime.now().millisecondsSinceEpoch}';
}
