/// Creation Center hub models — workshop modes, chat kit, sheets, scene ideas.
library;

enum WorkshopMode {
  explore,
  canon,
  characters,
  playtest;

  String get label => switch (this) {
        WorkshopMode.explore => 'Explore',
        WorkshopMode.canon => 'Canon',
        WorkshopMode.characters => 'Characters',
        WorkshopMode.playtest => 'Playtest',
      };

  String get subtitle => switch (this) {
        WorkshopMode.explore =>
          'Ideas, questions, and “what if” brainstorming',
        WorkshopMode.canon =>
          'Consolidate facts and flag contradictions',
        WorkshopMode.characters =>
          'Focus on cast, voices, and relationships',
        WorkshopMode.playtest =>
          'Short in-character vignettes to test tone',
      };

  static WorkshopMode fromJson(dynamic raw) {
    return switch ('$raw'.trim().toLowerCase()) {
      'canon' => WorkshopMode.canon,
      'characters' => WorkshopMode.characters,
      'playtest' => WorkshopMode.playtest,
      _ => WorkshopMode.explore,
    };
  }

  String toJson() => name;
}

/// Default kit applied when starting roleplay from a workshop.
class WorkshopChatKit {
  const WorkshopChatKit({
    this.defaultLorebookEnabled = true,
    this.defaultAuthorsNote = '',
    this.defaultPersonaId,
    this.defaultCastOrder = const [],
    this.autoReply = false,
  });

  final bool defaultLorebookEnabled;
  final String defaultAuthorsNote;
  final String? defaultPersonaId;
  final List<String> defaultCastOrder;
  final bool autoReply;

  WorkshopChatKit copyWith({
    bool? defaultLorebookEnabled,
    String? defaultAuthorsNote,
    String? defaultPersonaId,
    bool clearDefaultPersonaId = false,
    List<String>? defaultCastOrder,
    bool? autoReply,
  }) {
    return WorkshopChatKit(
      defaultLorebookEnabled:
          defaultLorebookEnabled ?? this.defaultLorebookEnabled,
      defaultAuthorsNote: defaultAuthorsNote ?? this.defaultAuthorsNote,
      defaultPersonaId: clearDefaultPersonaId
          ? null
          : (defaultPersonaId ?? this.defaultPersonaId),
      defaultCastOrder: defaultCastOrder ?? this.defaultCastOrder,
      autoReply: autoReply ?? this.autoReply,
    );
  }

  Map<String, dynamic> toJson() => {
        if (!defaultLorebookEnabled) 'defaultLorebookEnabled': false,
        if (defaultAuthorsNote.trim().isNotEmpty)
          'defaultAuthorsNote': defaultAuthorsNote,
        if (defaultPersonaId != null && defaultPersonaId!.isNotEmpty)
          'defaultPersonaId': defaultPersonaId,
        if (defaultCastOrder.isNotEmpty) 'defaultCastOrder': defaultCastOrder,
        if (autoReply) 'autoReply': true,
      };

  factory WorkshopChatKit.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const WorkshopChatKit();
    final cast = <String>[];
    final rawCast = json['defaultCastOrder'];
    if (rawCast is List) {
      for (final item in rawCast) {
        final id = '$item'.trim();
        if (id.isNotEmpty) cast.add(id);
      }
    }
    final personaRaw = '${json['defaultPersonaId'] ?? ''}'.trim();
    return WorkshopChatKit(
      defaultLorebookEnabled: json['defaultLorebookEnabled'] != false,
      defaultAuthorsNote: '${json['defaultAuthorsNote'] ?? ''}'.trim(),
      defaultPersonaId: personaRaw.isEmpty ? null : personaRaw,
      defaultCastOrder: cast,
      autoReply: json['autoReply'] == true,
    );
  }
}

class WorkshopLocation {
  const WorkshopLocation({
    required this.name,
    this.description = '',
  });

  final String name;
  final String description;

  WorkshopLocation copyWith({String? name, String? description}) {
    return WorkshopLocation(
      name: name ?? this.name,
      description: description ?? this.description,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        if (description.trim().isNotEmpty) 'description': description,
      };

  factory WorkshopLocation.fromJson(Map<String, dynamic> json) {
    return WorkshopLocation(
      name: '${json['name'] ?? ''}'.trim(),
      description: '${json['description'] ?? ''}'.trim(),
    );
  }
}

class WorkshopRelationship {
  const WorkshopRelationship({
    required this.fromName,
    required this.toName,
    this.relationDynamic = '',
  });

  final String fromName;
  final String toName;
  final String relationDynamic;

  WorkshopRelationship copyWith({
    String? fromName,
    String? toName,
    String? relationDynamic,
  }) {
    return WorkshopRelationship(
      fromName: fromName ?? this.fromName,
      toName: toName ?? this.toName,
      relationDynamic: relationDynamic ?? this.relationDynamic,
    );
  }

  Map<String, dynamic> toJson() => {
        'fromName': fromName,
        'toName': toName,
        if (relationDynamic.trim().isNotEmpty) 'dynamic': relationDynamic,
      };

  factory WorkshopRelationship.fromJson(Map<String, dynamic> json) {
    return WorkshopRelationship(
      fromName: '${json['fromName'] ?? ''}'.trim(),
      toName: '${json['toName'] ?? ''}'.trim(),
      relationDynamic: '${json['dynamic'] ?? ''}'.trim(),
    );
  }
}

class WorkshopSceneIdea {
  const WorkshopSceneIdea({
    required this.id,
    required this.title,
    required this.text,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final String text;
  final DateTime updatedAt;

  WorkshopSceneIdea copyWith({
    String? id,
    String? title,
    String? text,
    DateTime? updatedAt,
  }) {
    return WorkshopSceneIdea(
      id: id ?? this.id,
      title: title ?? this.title,
      text: text ?? this.text,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'text': text,
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory WorkshopSceneIdea.fromJson(Map<String, dynamic> json) {
    return WorkshopSceneIdea(
      id: '${json['id'] ?? ''}'.trim().isEmpty
          ? WorkshopSceneIdea.newId()
          : '${json['id']}'.trim(),
      title: ('${json['title'] ?? ''}').trim().isEmpty
          ? 'Scene idea'
          : ('${json['title']}').trim(),
      text: '${json['text'] ?? ''}'.trim(),
      updatedAt: DateTime.tryParse('${json['updatedAt'] ?? ''}') ??
          DateTime.now(),
    );
  }

  static String newId() => 'scene_${DateTime.now().millisecondsSinceEpoch}';
}

/// Read-only status chips for workshop overview.
class WorkshopHubStatus {
  const WorkshopHubStatus({
    required this.lorebookState,
    required this.characterCount,
    required this.personaLinked,
    required this.sourceChatTitle,
    required this.roleplayChatCount,
    required this.messagesSinceLorebookUpdate,
    required this.isLorebookStale,
    required this.hasWorldSummary,
    required this.canonPinCount,
    required this.sceneIdeaCount,
  });

  final String lorebookState;
  final int characterCount;
  final bool personaLinked;
  final String? sourceChatTitle;
  final int roleplayChatCount;
  final int messagesSinceLorebookUpdate;
  final bool isLorebookStale;
  final bool hasWorldSummary;
  final int canonPinCount;
  final int sceneIdeaCount;
}

/// Glossary term extracted for lorebook bulk-add.
class GlossaryEntry {
  const GlossaryEntry({
    required this.term,
    required this.definition,
    required this.keywords,
  });

  final String term;
  final String definition;
  final List<String> keywords;
}
