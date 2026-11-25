import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:gal/gal.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Copies avatar images outside the app sandbox (Gallery / Downloads).
class AvatarExportService {
  static const folderName = 'Anima Avatars';

  /// Saves a user-visible copy. Returns a short message for snackbars.
  Future<String> exportAvatar({
    required Uint8List bytes,
    required String suggestedName,
  }) async {
    final baseName = p.basename(suggestedName.trim());
    if (baseName.isEmpty) {
      throw AvatarExportException('Missing file name for export.');
    }

    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      await Gal.putImageBytes(bytes, name: baseName);
      return Platform.isAndroid
          ? 'Also saved to Gallery: $baseName'
          : 'Also saved to Photos: $baseName';
    }

    final dir = await _exportDir();
    final file = File(p.join(dir.path, baseName));
    await file.writeAsBytes(bytes, flush: true);
    return 'Also saved to ${file.path}';
  }

  Future<Directory> _exportDir() async {
    final downloads = await getDownloadsDirectory();
    final root = downloads ?? await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(root.path, folderName));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }
}

class AvatarExportException implements Exception {
  AvatarExportException(this.message);
  final String message;

  @override
  String toString() => message;
}
