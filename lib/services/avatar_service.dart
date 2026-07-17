import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Saves avatar images under the app documents folder (device only).
///
/// Files live in `avatars/` — character cards store just the file name
/// (e.g. `char_123.png`), not a full path that can break after updates.
class AvatarService {
  AvatarService({Future<Directory> Function()? documentsDirectory})
      : _documentsDirectory =
            documentsDirectory ?? getApplicationDocumentsDirectory;

  final Future<Directory> Function() _documentsDirectory;

  Future<Directory> _avatarsDir() async {
    final docs = await _documentsDirectory();
    final dir = Directory(p.join(docs.path, 'avatars'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
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
  Future<String> saveBytes({
    required String stem,
    required Uint8List bytes,
    String extension = '.png',
  }) async {
    final dir = await _avatarsDir();
    final ext = extension.startsWith('.') ? extension : '.$extension';
    final safeStem = stem
        .replaceAll(RegExp(r'[^\w\-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    final name = '${safeStem.isEmpty ? 'avatar' : safeStem}$ext';
    final file = File(p.join(dir.path, name));
    await file.writeAsBytes(bytes, flush: true);
    return name;
  }

  /// Copy a picked gallery/file path into avatars/ and return the file name.
  Future<String> saveFromPath({
    required String stem,
    required String sourcePath,
  }) async {
    final source = File(sourcePath);
    final bytes = await source.readAsBytes();
    var ext = p.extension(sourcePath).toLowerCase();
    if (ext.isEmpty) ext = '.img';
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
}
