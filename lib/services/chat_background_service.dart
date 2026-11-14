import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'app_paths.dart';

/// Stores chat background images under the app documents folder.
///
/// Theme Studio stores just the file name (e.g. `chat_bg_123.jpg`).
class ChatBackgroundService {
  ChatBackgroundService({Future<Directory> Function()? documentsDirectory})
      : _documentsDirectory =
            documentsDirectory ?? appDocumentsDirectory;

  final Future<Directory> Function() _documentsDirectory;

  Future<Directory> _backgroundsDir() async {
    final docs = await _documentsDirectory();
    final dir = Directory(p.join(docs.path, 'chat_backgrounds'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<String?> resolvePath(String? fileName) async {
    if (fileName == null || fileName.trim().isEmpty) return null;
    final dir = await _backgroundsDir();
    final file = File(p.join(dir.path, p.basename(fileName.trim())));
    if (!await file.exists()) return null;
    return file.path;
  }

  Future<bool> exists(String? fileName) async {
    return (await resolvePath(fileName)) != null;
  }

  Future<String> saveBytes({
    required String stem,
    required Uint8List bytes,
    String extension = '.jpg',
  }) async {
    final dir = await _backgroundsDir();
    final ext = extension.startsWith('.') ? extension : '.$extension';
    final safeStem = stem
        .replaceAll(RegExp(r'[^\w\-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    final name = '${safeStem.isEmpty ? 'chat_bg' : safeStem}$ext';
    final file = File(p.join(dir.path, name));
    await file.writeAsBytes(bytes, flush: true);
    return name;
  }

  Future<String> saveFromPath({
    required String stem,
    required String sourcePath,
  }) async {
    final source = File(sourcePath);
    final bytes = await source.readAsBytes();
    var ext = p.extension(sourcePath).toLowerCase();
    if (ext.isEmpty) ext = '.jpg';
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
