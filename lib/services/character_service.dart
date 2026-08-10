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

  /// Loads all characters. Returns an empty list when none are saved yet.
  Future<List<Character>> loadCharacters() async {
    final file = await _file();
    if (!await file.exists()) {
      await saveCharacters(const []);
      return const [];
    }

    try {
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) {
        await saveCharacters(const []);
        return const [];
      }
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        await saveCharacters(const []);
        return const [];
      }

      return decoded
          .whereType<Map>()
          .map((item) => Character.fromJson(Map<String, dynamic>.from(item)))
          .where((c) => c.id.isNotEmpty && c.name.isNotEmpty)
          .toList();
    } catch (_) {
      await saveCharacters(const []);
      return const [];
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

  /// Deletes a character. The list may end up empty.
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
    await _avatarService.deleteAllForStem(id);
    await saveCharacters(all);
    return all;
  }

  /// Creates a new unique id for a character.
  String newId() => 'char_${DateTime.now().millisecondsSinceEpoch}';
}
