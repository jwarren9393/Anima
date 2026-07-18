import 'chat_message.dart';

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

  WorldWorkshop copyWith({
    String? id,
    String? title,
    List<ChatMessage>? messages,
    DateTime? updatedAt,
    String? exportedLorebookId,
    bool clearExportedLorebookId = false,
    WorkshopSourceContext? importedSource,
    bool clearImportedSource = false,
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

    final updatedRaw = json['updatedAt'] as String?;
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
