import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/character.dart';
import '../models/character_category.dart';

/// Persists Anima-only character categories (not SillyTavern card fields).
///
/// File: app documents / `anima_character_categories.json`
class CharacterCategoryService {
  CharacterCategoryService({
    Future<Directory> Function()? documentsDirectory,
  }) : _documentsDirectory =
            documentsDirectory ?? getApplicationDocumentsDirectory;

  static const _fileName = 'anima_character_categories.json';

  /// Sentinel filter id meaning “show every character”.
  static const allFilterId = '';

  final Future<Directory> Function() _documentsDirectory;

  Future<File> _file() async {
    final dir = await _documentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  Future<CharacterCategoryState> loadState() async {
    final file = await _file();
    if (!await file.exists()) return CharacterCategoryState.empty;

    try {
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return CharacterCategoryState.empty;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return CharacterCategoryState.empty;
      return CharacterCategoryState.fromJson(
        Map<String, dynamic>.from(decoded),
      );
    } catch (_) {
      return CharacterCategoryState.empty;
    }
  }

  Future<void> saveState(CharacterCategoryState state) async {
    final file = await _file();
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(state.toJson()),
    );
  }

  Future<CharacterCategoryState> upsertCategory(CharacterCategory category) async {
    final name = category.name.trim();
    if (name.isEmpty) {
      throw ArgumentError('Category name cannot be empty.');
    }
    final state = await loadState();
    final next = CharacterCategory(
      id: category.id.trim().isEmpty ? CharacterCategory.newId() : category.id,
      name: name,
    );
    final categories = List<CharacterCategory>.from(state.categories);
    final index = categories.indexWhere((c) => c.id == next.id);
    if (index >= 0) {
      categories[index] = next;
    } else {
      categories.add(next);
    }
    final updated = state.copyWith(categories: categories);
    await saveState(updated);
    return updated;
  }

  Future<CharacterCategoryState> deleteCategory(String categoryId) async {
    final id = categoryId.trim();
    if (id.isEmpty) return loadState();

    final state = await loadState();
    final categories =
        state.categories.where((c) => c.id != id).toList(growable: false);
    final memberships = <String, List<String>>{};
    for (final entry in state.memberships.entries) {
      final kept = entry.value.where((c) => c != id).toList(growable: false);
      if (kept.isNotEmpty) memberships[entry.key] = kept;
    }
    final updated = CharacterCategoryState(
      categories: categories,
      memberships: memberships,
    );
    await saveState(updated);
    return updated;
  }

  Future<CharacterCategoryState> setCategoriesForCharacter(
    String characterId,
    Iterable<String> categoryIds,
  ) async {
    final id = characterId.trim();
    if (id.isEmpty) return loadState();

    final state = await loadState();
    final known = state.categories.map((c) => c.id).toSet();
    final cleaned = <String>[];
    for (final raw in categoryIds) {
      final categoryId = raw.trim();
      if (categoryId.isEmpty || !known.contains(categoryId)) continue;
      if (!cleaned.contains(categoryId)) cleaned.add(categoryId);
    }

    final memberships = Map<String, List<String>>.from(state.memberships);
    if (cleaned.isEmpty) {
      memberships.remove(id);
    } else {
      memberships[id] = cleaned;
    }
    final updated = state.copyWith(memberships: memberships);
    await saveState(updated);
    return updated;
  }

  /// Drops memberships for a deleted character (or any stale id).
  Future<CharacterCategoryState> removeCharacter(String characterId) async {
    final id = characterId.trim();
    if (id.isEmpty) return loadState();
    final state = await loadState();
    if (!state.memberships.containsKey(id)) return state;
    final memberships = Map<String, List<String>>.from(state.memberships)
      ..remove(id);
    final updated = state.copyWith(memberships: memberships);
    await saveState(updated);
    return updated;
  }

  /// Removes memberships pointing at missing characters / categories.
  Future<CharacterCategoryState> prune({
    required Iterable<String> existingCharacterIds,
  }) async {
    final state = await loadState();
    final knownChars = existingCharacterIds.map((id) => id.trim()).toSet()
      ..removeWhere((id) => id.isEmpty);
    final knownCats = state.categories.map((c) => c.id).toSet();

    var changed = false;
    final memberships = <String, List<String>>{};
    for (final entry in state.memberships.entries) {
      if (!knownChars.contains(entry.key)) {
        changed = true;
        continue;
      }
      final kept = [
        for (final categoryId in entry.value)
          if (knownCats.contains(categoryId)) categoryId,
      ];
      if (kept.length != entry.value.length) changed = true;
      if (kept.isNotEmpty) memberships[entry.key] = kept;
    }

    if (!changed && memberships.length == state.memberships.length) {
      return state;
    }
    final updated = state.copyWith(memberships: memberships);
    await saveState(updated);
    return updated;
  }

  /// Filters [characters] by category. Empty [categoryId] means All.
  List<Character> filterCharacters(
    List<Character> characters, {
    required CharacterCategoryState state,
    required String categoryId,
  }) {
    final id = categoryId.trim();
    if (id.isEmpty) return List<Character>.from(characters);
    return [
      for (final character in characters)
        if (state.characterInCategory(character.id, id)) character,
    ];
  }
}
