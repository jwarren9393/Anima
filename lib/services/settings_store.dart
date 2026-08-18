import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;

/// Tiny key/value API matching how [SettingsService] used secure storage.
abstract class SettingsKv {
  Future<String?> read({required String key});
  Future<void> write({required String key, required String? value});
  Future<void> delete({required String key});
}

/// In-memory / Keystore / Credential Manager / libsecret (legacy + tests).
class SecureSettingsKv implements SettingsKv {
  SecureSettingsKv(this._secure);

  final FlutterSecureStorage _secure;

  @override
  Future<String?> read({required String key}) => _secure.read(key: key);

  @override
  Future<void> write({required String key, required String? value}) async {
    if (value == null) {
      await _secure.delete(key: key);
      return;
    }
    await _secure.write(key: key, value: value);
  }

  @override
  Future<void> delete({required String key}) => _secure.delete(key: key);
}

/// JSON file in the user-owned Anima folder (`anima_settings.json`).
class FileSettingsKv implements SettingsKv {
  FileSettingsKv({
    required this.documentsDirectory,
    this.legacy,
    this.migrateKeys = const [],
  });

  static const fileName = 'anima_settings.json';

  final Future<Directory> Function() documentsDirectory;
  final SettingsKv? legacy;
  final List<String> migrateKeys;

  Map<String, String>? _cache;
  String? _loadedPath;
  Future<void> _queue = Future.value();

  Future<T> _run<T>(Future<T> Function() op) {
    final next = _queue.then((_) => op());
    _queue = next.then((_) {}, onError: (_) {});
    return next;
  }

  Future<File> _fileFor(Directory dir) {
    return Future.value(File(p.join(dir.path, fileName)));
  }

  Future<void> _ensureLoadedUnlocked() async {
    final dir = await documentsDirectory();
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    if (_cache != null && _loadedPath == dir.path) return;

    _loadedPath = dir.path;
    final file = await _fileFor(dir);
    if (await file.exists()) {
      try {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map) {
          _cache = {
            for (final entry in decoded.entries)
              if (entry.key is String && entry.value != null)
                entry.key as String: '${entry.value}',
          };
          return;
        }
      } catch (_) {
        // Fall through and rebuild from legacy storage if needed.
      }
    }

    _cache = {};
    final from = legacy;
    if (from != null) {
      for (final key in migrateKeys) {
        final value = await from.read(key: key);
        if (value != null && value.isNotEmpty) {
          _cache![key] = value;
        }
      }
      if (_cache!.isNotEmpty) {
        await _flushUnlocked(dir);
      }
    }
  }

  Future<void> _flushUnlocked(Directory dir) async {
    final file = await _fileFor(dir);
    final cache = _cache ?? {};
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(cache),
      flush: true,
    );
  }

  @override
  Future<String?> read({required String key}) {
    return _run(() async {
      await _ensureLoadedUnlocked();
      return _cache![key];
    });
  }

  @override
  Future<void> write({required String key, required String? value}) {
    return _run(() async {
      await _ensureLoadedUnlocked();
      if (value == null) {
        _cache!.remove(key);
      } else {
        _cache![key] = value;
      }
      final dir = await documentsDirectory();
      await _flushUnlocked(dir);
    });
  }

  @override
  Future<void> delete({required String key}) => write(key: key, value: null);
}

SettingsKv createSettingsKv({
  FlutterSecureStorage? storage,
  Future<Directory> Function()? documentsDirectory,
  List<String> migrateKeys = const [],
}) {
  final secure = SecureSettingsKv(storage ?? const FlutterSecureStorage());
  if (documentsDirectory == null) return secure;
  return FileSettingsKv(
    documentsDirectory: documentsDirectory,
    legacy: secure,
    migrateKeys: migrateKeys,
  );
}
