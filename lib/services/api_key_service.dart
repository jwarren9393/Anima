import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;

import 'app_data_root.dart';
import 'app_paths.dart';

/// Saves and loads the NanoGPT API key.
///
/// When a user data folder is chosen, the key lives in `api_key.txt` in that
/// folder so the library is portable. Otherwise it stays in secure storage
/// (tests / first launch). Never commit this file to Git.
class ApiKeyService {
  ApiKeyService({
    FlutterSecureStorage? storage,
    Future<Directory> Function()? documentsDirectory,
  })  : _storage = storage ?? const FlutterSecureStorage(),
        _documentsDirectory = documentsDirectory ?? appDocumentsDirectory;

  static const _apiKeyStorageKey = 'nanogpt_api_key';

  final FlutterSecureStorage _storage;
  final Future<Directory> Function() _documentsDirectory;

  Future<File> _file() async {
    final dir = await _documentsDirectory();
    return File(p.join(dir.path, AppDataRoot.apiKeyFileName));
  }

  bool get _useFile {
    final root = AppDataRoot.instance;
    return root != null && root.isConfigured;
  }

  /// Returns the saved API key, or null if none has been saved yet.
  Future<String?> getApiKey() async {
    if (_useFile) {
      try {
        final file = await _file();
        if (await file.exists()) {
          final value = (await file.readAsString()).trim();
          if (value.isNotEmpty) return value;
        }
      } catch (_) {}
      final legacy = await _readSecure();
      if (legacy != null) {
        await saveApiKey(legacy);
        return legacy;
      }
      return null;
    }
    return _readSecure();
  }

  Future<String?> _readSecure() async {
    final key = await _storage.read(key: _apiKeyStorageKey);
    if (key == null || key.trim().isEmpty) return null;
    return key.trim();
  }

  /// Saves the API key on this device (data folder when configured).
  Future<void> saveApiKey(String apiKey) async {
    final trimmed = apiKey.trim();
    if (trimmed.isEmpty) {
      await clearApiKey();
      return;
    }
    if (_useFile) {
      final file = await _file();
      await file.writeAsString(trimmed, flush: true);
      return;
    }
    await _storage.write(key: _apiKeyStorageKey, value: trimmed);
  }

  /// Removes the API key from this device.
  Future<void> clearApiKey() async {
    if (_useFile) {
      try {
        final file = await _file();
        if (await file.exists()) await file.delete();
      } catch (_) {}
      return;
    }
    await _storage.delete(key: _apiKeyStorageKey);
  }

  /// True when a non-empty API key is stored.
  Future<bool> hasApiKey() async {
    final key = await getApiKey();
    return key != null;
  }
}
