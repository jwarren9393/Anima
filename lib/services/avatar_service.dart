import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../models/avatar_history_entry.dart';
import 'app_paths.dart';

/// Saves avatar images under the app documents folder (device only).
///
/// Files live in `avatars/` — character cards store just the file name
/// (e.g. `char_123.png`), not a full path that can break after updates.
///
/// History portraits use `{stem}_{timestamp}.png` so older generations are kept.
class AvatarService {
  AvatarService({Future<Directory> Function()? documentsDirectory})
      : _documentsDirectory =
            documentsDirectory ?? appDocumentsDirectory;

  final Future<Directory> Function() _documentsDirectory;

  static const imageExtensions = {'.png', '.jpg', '.jpeg', '.webp', '.gif'};

  Future<Directory> _avatarsDir() async {
    final docs = await _documentsDirectory();
    final dir = Directory(p.join(docs.path, 'avatars'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  String safeStem(String stem) {
    return stem
        .replaceAll(RegExp(r'[^\w\-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }

  bool fileNameMatchesStem(String fileName, String stem) {
    final safe = safeStem(stem);
    if (safe.isEmpty) return false;
    final base = p.basename(fileName.trim()).toLowerCase();
    if (!base.startsWith(safe.toLowerCase())) return false;
    final ext = p.extension(base);
    return imageExtensions.contains(ext);
  }

  /// Full path for a stored avatar file name, or null if missing.
  Future<String?> resolvePath(String? fileName) async {
    if (fileName == null || fileName.trim().isEmpty) return null;
    final dir = await _avatarsDir();
    final file = File(p.join(dir.path, p.basename(fileName.trim())));
    if (!await file.exists()) return null;
    return file.path;
  }

  /// True when [fileName] points at a readable image on disk.
  Future<bool> exists(String? fileName) async {
    return (await resolvePath(fileName)) != null;
  }

  /// Copy raw bytes into `avatars/{stem}{ext}` and return the file name.
  ///
  /// Overwrites when the same stem + extension is used (legacy behavior).
  Future<String> saveBytes({
    required String stem,
    required Uint8List bytes,
    String extension = '.png',
  }) async {
    final dir = await _avatarsDir();
    final ext = extension.startsWith('.') ? extension : '.$extension';
    final safe = safeStem(stem);
    final name = '${safe.isEmpty ? 'avatar' : safe}$ext';
    final file = File(p.join(dir.path, name));
    await file.writeAsBytes(bytes, flush: true);
    return name;
  }

  /// Append a new history file — never overwrites prior generations.
  Future<String> saveHistoryBytes({
    required String stem,
    required Uint8List bytes,
    String extension = '.png',
  }) async {
    final dir = await _avatarsDir();
    final ext = extension.startsWith('.') ? extension : '.$extension';
    final safe = safeStem(stem);
    final prefix = safe.isEmpty ? 'avatar' : safe;
    final name = '${prefix}_${DateTime.now().millisecondsSinceEpoch}$ext';
    final file = File(p.join(dir.path, name));
    await file.writeAsBytes(bytes, flush: true);
    return name;
  }

  /// All portrait files for one character/persona id, newest first.
  Future<List<AvatarHistoryEntry>> listHistoryForStem(String stem) async {
    final dir = await _avatarsDir();
    if (!await dir.exists()) return const [];

    final entries = <AvatarHistoryEntry>[];
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (!fileNameMatchesStem(name, stem)) continue;
      final stat = await entity.stat();
      entries.add(AvatarHistoryEntry(fileName: name, modified: stat.modified));
    }
    entries.sort((a, b) => b.modified.compareTo(a.modified));
    return entries;
  }

  Future<Uint8List?> readBytes(String? fileName) async {
    final path = await resolvePath(fileName);
    if (path == null) return null;
    return File(path).readAsBytes();
  }

  /// Copy one stored portrait to a new character/persona stem.
  Future<String?> copyAvatarFile({
    required String? sourceFileName,
    required String targetStem,
  }) async {
    final bytes = await readBytes(sourceFileName);
    if (bytes == null) return null;
    var ext = p.extension(p.basename(sourceFileName ?? '')).toLowerCase();
    if (ext.isEmpty || !imageExtensions.contains(ext)) {
      ext = '.png';
    }
    return saveBytes(stem: targetStem, bytes: bytes, extension: ext);
  }

  /// Copy a picked gallery/file path into avatars/ and return the file name.
  Future<String> saveFromPath({
    required String stem,
    required String sourcePath,
    bool keepHistory = true,
  }) async {
    final source = File(sourcePath);
    final bytes = await source.readAsBytes();
    var ext = p.extension(sourcePath).toLowerCase();
    if (ext.isEmpty) ext = '.img';
    if (keepHistory) {
      return saveHistoryBytes(stem: stem, bytes: bytes, extension: ext);
    }
    return saveBytes(stem: stem, bytes: bytes, extension: ext);
  }

  Future<void> delete(String? fileName) async {
    final path = await resolvePath(fileName);
    if (path == null) return;
    try {
      await File(path).delete();
    } catch (_) {
      // Best-effort cleanup.
    }
  }

  /// Remove every portrait file tied to [stem] (character/persona delete).
  Future<void> deleteAllForStem(String stem) async {
    final entries = await listHistoryForStem(stem);
    for (final entry in entries) {
      await delete(entry.fileName);
    }
  }
}
