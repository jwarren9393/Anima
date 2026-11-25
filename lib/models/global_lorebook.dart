import 'lorebook.dart';

/// A standalone World Info / lorebook that can apply to any chat (SillyTavern-style).
///
/// Separate from a character card's embedded [Character.characterBook].
class GlobalLorebook {
  const GlobalLorebook({
    required this.id,
    required this.book,
    this.enabled = true,
  });

  final String id;

  /// When true, this book is eligible for injection (unless a chat overrides).
  final bool enabled;

  final Lorebook book;

  String get displayName {
    final name = book.name.trim();
    if (name.isNotEmpty) return name;
    return 'Untitled lorebook';
  }

  int get entryCount => book.entries.length;

  int get enabledEntryCount =>
      book.entries.where((e) => e.enabled).length;

  GlobalLorebook copyWith({
    String? id,
    bool? enabled,
    Lorebook? book,
  }) {
    return GlobalLorebook(
      id: id ?? this.id,
      enabled: enabled ?? this.enabled,
      book: book ?? this.book,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'enabled': enabled,
        'book': book.toJson(),
      };

  factory GlobalLorebook.fromJson(Map<String, dynamic> json) {
    final rawBook = json['book'];
    final Lorebook book;
    if (rawBook is Map) {
      book = Lorebook.fromJson(Map<String, dynamic>.from(rawBook));
    } else {
      // Older / bare shape: treat the whole object as a lorebook + id/enabled.
      book = Lorebook.fromJson(json);
    }

    final id = '${json['id'] ?? ''}'.trim();
    return GlobalLorebook(
      id: id.isEmpty ? newId() : id,
      enabled: json['enabled'] != false,
      book: book,
    );
  }

  static String newId() => 'lore_${DateTime.now().millisecondsSinceEpoch}';

  static GlobalLorebook empty({String name = ''}) {
    return GlobalLorebook(
      id: newId(),
      book: Lorebook.empty(name: name),
    );
  }
}
