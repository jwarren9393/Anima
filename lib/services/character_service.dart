import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/character.dart';
import 'app_paths.dart';
import 'avatar_service.dart';

/// Saves and loads your characters as a JSON file on this device.
///
/// File: Anima library folder / `anima_characters.json`
/// Nothing here is uploaded to GitHub.
class CharacterService {
  CharacterService({
    Future<Directory> Function()? documentsDirectory,
    AvatarService? avatarService,
  })  : _documentsDirectory =
            documentsDirectory ?? appDocumentsDirectory,
        _avatarService = avatarService ??
            AvatarService(documentsDirectory: documentsDirectory);

  static const _fileName = 'anima_characters.json';

  final Future<Directory> Function() _documentsDirectory;
  final AvatarService _avatarService;

  /// Serializes read-modify-write cycles so a concurrent save (e.g. a quick
  /// temporary-character add while an editor save lands) never drops a card
  /// because both read the same old list before writing.
  Future<void> _writeQueue = Future.value();
  bool _writing = false;

  Future<T> _runSerialized<T>(Future<T> Function() op) {
    // Re-entrant calls (upsert -> loadCharacters -> saveCharacters bootstrap)
    // run directly instead of queuing behind the unfinished outer write, which
    // would deadlock.
    if (_writing) return op();
    final next = _writeQueue.then((_) async {
      _writing = true;
      try {
        return await op();
      } finally {
        _writing = false;
      }
    });
    _writeQueue = next.then((_) {}, onError: (_) {});
    return next;
  }

  Future<File> _file() async {
    final dir = await _documentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  /// Writes the characters file with `flush: true` so the bytes are really on
  /// disk before the editor closes. A transient failure is retried once.
  Future<void> _writeCharactersFile(File file, String data) async {
    try {
      await file.writeAsString(data, flush: true);
    } catch (_) {
      await Future<void>.delayed(const Duration(milliseconds: 150));
      await file.writeAsString(data, flush: true);
    }
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
  Future<void> saveCharacters(List<Character> characters) {
    return _runSerialized(() async {
      final file = await _file();
      final payload = characters.map((c) => c.toJson()).toList();
      await _writeCharactersFile(
        file,
        const JsonEncoder.withIndent('  ').convert(payload),
      );
    });
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
  ///
  /// Read → modify → write runs on a single queue so concurrent saves cannot
  /// clobber each other, and after writing we re-read the file from disk to
  /// prove the card actually landed (a silent storage failure throws instead
  /// of letting the editor close and lose the user's edits).
  Future<List<Character>> upsert(Character character) {
    return _runSerialized(() async {
      final all = List<Character>.from(await loadCharacters());
      final index = all.indexWhere((c) => c.id == character.id);
      if (index >= 0) {
        all[index] = character;
      } else {
        all.add(character);
      }
      await saveCharacters(all);
      final onDisk = await getById(character.id);
      if (onDisk == null) {
        throw FileSystemException(
          'The character card did not reach the library file. Please tap '
          'Save again.',
        );
      }
      return all;
    });
  }

  /// Deletes a character. The list may end up empty.
  Future<List<Character>> delete(String id) {
    return _runSerialized(() async {
      final all = await loadCharacters();
      all.removeWhere((c) => c.id == id);
      await _avatarService.deleteAllForStem(id);
      await saveCharacters(all);
      return all;
    });
  }

  /// Creates a new unique id for a character.
  String newId() => 'char_${DateTime.now().millisecondsSinceEpoch}';

  /// Deep copy of [source] with a new id, name suffix, and separate avatar file.
  Future<Character> duplicate(Character source) async {
    final id = newId();
    String? avatar;
    final avatarName = source.avatarFileName?.trim();
    if (avatarName != null && avatarName.isNotEmpty) {
      final bytes = await _avatarService.readBytes(avatarName);
      if (bytes != null) {
        avatar = await _avatarService.saveHistoryBytes(
          stem: id,
          bytes: bytes,
          extension: p.extension(avatarName),
        );
      }
    }

    Map<String, dynamic>? book;
    final rawBook = source.characterBook;
    if (rawBook != null && rawBook.isNotEmpty) {
      book = jsonDecode(jsonEncode(rawBook)) as Map<String, dynamic>;
    }
    final extensions = jsonDecode(jsonEncode(source.extensions))
        as Map<String, dynamic>;

    final baseName = source.name.trim().isEmpty ? 'Character' : source.name.trim();
    return source.copyWith(
      id: id,
      name: '$baseName (copy)',
      avatarFileName: avatar,
      characterBook: book,
      extensions: extensions,
      clearSourceWorkshopId: true,
    );
  }
}
