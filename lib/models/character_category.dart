/// Anima-only label for organizing characters (not part of SillyTavern cards).
class CharacterCategory {
  const CharacterCategory({
    required this.id,
    required this.name,
  });

  final String id;
  final String name;

  CharacterCategory copyWith({
    String? id,
    String? name,
  }) {
    return CharacterCategory(
      id: id ?? this.id,
      name: name ?? this.name,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
      };

  factory CharacterCategory.fromJson(Map<String, dynamic> json) {
    final id = '${json['id'] ?? ''}'.trim();
    final name = '${json['name'] ?? ''}'.trim();
    return CharacterCategory(
      id: id.isEmpty ? newId() : id,
      name: name.isEmpty ? 'Untitled' : name,
    );
  }

  static String newId() => 'category_${DateTime.now().millisecondsSinceEpoch}';
}

/// Categories plus which characters belong to which lists.
class CharacterCategoryState {
  const CharacterCategoryState({
    this.categories = const [],
    this.memberships = const {},
  });

  final List<CharacterCategory> categories;

  /// characterId → categoryIds (a character may sit in several lists).
  final Map<String, List<String>> memberships;

  static const empty = CharacterCategoryState();

  CharacterCategoryState copyWith({
    List<CharacterCategory>? categories,
    Map<String, List<String>>? memberships,
  }) {
    return CharacterCategoryState(
      categories: categories ?? this.categories,
      memberships: memberships ?? this.memberships,
    );
  }

  List<String> categoriesForCharacter(String characterId) {
    final id = characterId.trim();
    if (id.isEmpty) return const [];
    final raw = memberships[id];
    if (raw == null || raw.isEmpty) return const [];
    final known = categories.map((c) => c.id).toSet();
    return [
      for (final categoryId in raw)
        if (known.contains(categoryId)) categoryId,
    ];
  }

  bool characterInCategory(String characterId, String categoryId) {
    return categoriesForCharacter(characterId).contains(categoryId);
  }

  Map<String, dynamic> toJson() => {
        'version': 1,
        'categories': categories.map((c) => c.toJson()).toList(),
        'memberships': {
          for (final entry in memberships.entries)
            if (entry.key.trim().isNotEmpty && entry.value.isNotEmpty)
              entry.key: entry.value,
        },
      };

  factory CharacterCategoryState.fromJson(Map<String, dynamic> json) {
    final categories = <CharacterCategory>[];
    final rawCategories = json['categories'];
    if (rawCategories is List) {
      for (final item in rawCategories) {
        if (item is! Map) continue;
        final category =
            CharacterCategory.fromJson(Map<String, dynamic>.from(item));
        if (category.id.isEmpty) continue;
        categories.add(category);
      }
    }

    final known = categories.map((c) => c.id).toSet();
    final memberships = <String, List<String>>{};
    final rawMemberships = json['memberships'];
    if (rawMemberships is Map) {
      for (final entry in rawMemberships.entries) {
        final characterId = '${entry.key}'.trim();
        if (characterId.isEmpty) continue;
        final rawIds = entry.value;
        if (rawIds is! List) continue;
        final ids = <String>[];
        for (final item in rawIds) {
          final categoryId = '$item'.trim();
          if (categoryId.isEmpty || !known.contains(categoryId)) continue;
          if (!ids.contains(categoryId)) ids.add(categoryId);
        }
        if (ids.isNotEmpty) memberships[characterId] = ids;
      }
    }

    return CharacterCategoryState(
      categories: categories,
      memberships: memberships,
    );
  }
}
