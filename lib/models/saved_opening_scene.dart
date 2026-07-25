/// A reusable narrator opening scene saved on device.
class SavedOpeningScene {
  const SavedOpeningScene({
    required this.id,
    required this.title,
    required this.text,
    required this.updatedAt,
    this.workshopId,
  });

  final String id;
  final String title;
  final String text;
  final DateTime updatedAt;

  /// When set, this entry is kept in sync with a Creation Center workshop.
  final String? workshopId;

  String get preview {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return '';
    return trimmed.length <= 120 ? trimmed : '${trimmed.substring(0, 120)}…';
  }

  SavedOpeningScene copyWith({
    String? id,
    String? title,
    String? text,
    DateTime? updatedAt,
    String? workshopId,
    bool clearWorkshopId = false,
  }) {
    return SavedOpeningScene(
      id: id ?? this.id,
      title: title ?? this.title,
      text: text ?? this.text,
      updatedAt: updatedAt ?? this.updatedAt,
      workshopId: clearWorkshopId ? null : (workshopId ?? this.workshopId),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'text': text,
        'updatedAt': updatedAt.toIso8601String(),
        if (workshopId != null && workshopId!.isNotEmpty)
          'workshopId': workshopId,
      };

  factory SavedOpeningScene.fromJson(Map<String, dynamic> json) {
    return SavedOpeningScene(
      id: '${json['id'] ?? ''}'.trim().isEmpty
          ? newId()
          : '${json['id']}'.trim(),
      title: ('${json['title'] ?? ''}').trim().isEmpty
          ? 'Opening scene'
          : ('${json['title']}').trim(),
      text: '${json['text'] ?? ''}'.trim(),
      updatedAt: DateTime.tryParse('${json['updatedAt'] ?? ''}') ??
          DateTime.now(),
      workshopId: ('${json['workshopId'] ?? ''}').trim().isEmpty
          ? null
          : ('${json['workshopId']}').trim(),
    );
  }

  static String newId() => 'open_${DateTime.now().millisecondsSinceEpoch}';
}
