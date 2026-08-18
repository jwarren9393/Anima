import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

/// Public shared storage on Android (Documents), not the locked app sandbox.
class AndroidStorage {
  AndroidStorage._();

  static const _channel = MethodChannel('anima/storage');

  static bool get isAndroid => !kIsWeb && Platform.isAndroid;

  /// Typical Samsung / Android public Documents folder.
  static const fallbackDocumentsPath = '/storage/emulated/0/Documents';

  static Future<String> publicDocumentsPath() async {
    if (!isAndroid) return fallbackDocumentsPath;
    try {
      final path = await _channel.invokeMethod<String>('getDocumentsDir');
      if (path != null && path.trim().isNotEmpty) return path.trim();
    } catch (_) {}
    return fallbackDocumentsPath;
  }

  static Future<bool> hasAllFilesAccess() async {
    if (!isAndroid) return true;
    try {
      final granted = await _channel.invokeMethod<bool>('hasAllFilesAccess');
      if (granted == true) return true;
    } catch (_) {}
    return Permission.manageExternalStorage.isGranted;
  }

  /// Ask Android for access to a normal folder the file manager can open.
  ///
  /// On Android 11+ this opens the system “All files access” screen. Come back
  /// to Anima after you allow it.
  static Future<bool> ensureAccess() async {
    if (!isAndroid) return true;
    if (await hasAllFilesAccess()) return true;

    var manage = await Permission.manageExternalStorage.status;
    if (!manage.isGranted) {
      manage = await Permission.manageExternalStorage.request();
    }
    if (manage.isGranted || await hasAllFilesAccess()) return true;

    final storage = await Permission.storage.request();
    return storage.isGranted || await hasAllFilesAccess();
  }
}
