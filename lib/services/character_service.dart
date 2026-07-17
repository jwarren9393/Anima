import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/character.dart';
import 'avatar_service.dart';

/// Saves and loads your characters as a JSON file on this device.
///
/// File location (typical Android): app documents folder / `anima_characters.json`
/// Nothing here is uploaded to GitHub.
class CharacterService {
  CharacterService({
    Future<Directory> Function()? documentsDirectory,
    AvatarService? avatarService,
  })  : _documentsDirectory =
            documentsDirectory ?? getApplicationDocumentsDirectory,
        _avatarService = avatarService ??
            AvatarService(documentsDirectory: documentsDirectory);

  static const _fileName = 'anima_characters.json';

  final Future<Directory> Function() _documentsDirectory;
  final AvatarService _avatarService;

  Future<File> _file() async {
    final dir = await _documentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  /// Loads all characters. Creates a starter character if the file is missing.
  Future<List<Character>> loadCharacters() async {
    final file = await _file();
    if (!await file.exists()) {
      final starter = Character.starter();
      await saveCharacters([starter]);
      return [starter];
    }

    try {
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) {
        final starter = Character.starter();
        await saveCharacters([starter]);
        return [starter];
      }
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        final starter = Character.starter();
        await saveCharacters([starter]);
        return [starter];
      }

      final characters = decoded
          .whereType<Map>()
          .map((item) => Character.fromJson(Map<String, dynamic>.from(item)))
          .where((c) => c.id.isNotEmpty && c.name.isNotEmpty)
          .toList();

      if (characters.isEmpty) {
        final starter = Character.starter();
        await saveCharacters([starter]);
        return [starter];
      }
      return characters;
    } catch (_) {
      final starter = Character.starter();
      await saveCharacters([starter]);
      return [starter];
    }
  }

  /// Overwrites the characters file with [characters].
  Future<void> saveCharacters(List<Character> characters) async {
    final file = await _file();
    final payload = characters.map((c) => c.toJson()).toList();
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(payload),
    );
  }

  /// Finds one character by id, or null if missing.
  Future<Character?> getById(String id) async {
    final all = await loadCharacters();
    for (final character in all) {
      if (character.id == id) return character;
    }
    return null;
  }

  /// Adds a new character (or replaces one with the same id) and saves.
  Future<List<Character>> upsert(Character character) async {
    final all = await loadCharacters();
    final index = all.indexWhere((c) => c.id == character.id);
    if (index >= 0) {
      all[index] = character;
    } else {
      all.add(character);
    }
    await saveCharacters(all);
    return all;
  }

  /// Deletes a character. Keeps at least one starter if the list would be empty.
  Future<List<Character>> delete(String id) async {
    final all = await loadCharacters();
    Character? removed;
    for (final c in all) {
      if (c.id == id) {
        removed = c;
        break;
      }
    }
    all.removeWhere((c) => c.id == id);
    if (removed?.avatarFileName != null) {
      await _avatarService.delete(removed!.avatarFileName);
    }
    if (all.isEmpty) {
      all.add(Character.starter());
    }
    await saveCharacters(all);
    return all;
  }

  /// Creates a new unique id for a character.
  String newId() => 'char_${DateTime.now().millisecondsSinceEpoch}';
}
