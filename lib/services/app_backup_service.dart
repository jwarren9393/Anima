import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'persona_service.dart';
import 'settings_service.dart';

/// Plain JSON full-app backup (no encryption, no API key).
///
/// One `.anima-backup` file holds known Anima document JSON files, avatar
/// images (base64), and non-secret preference key/values. On desktop, only
/// this whitelist is touched — never the whole Documents folder.
class AppBackupService {
  AppBackupService({
    Future<Directory> Function()? documentsDirectory,
    SettingsService? settingsService,
    this.personaService,
    this.loadPreferences,
    this.savePreferences,
  })  : _documentsDirectory =
            documentsDirectory ?? getApplicationDocumentsDirectory,
        _settingsService = settingsService ?? SettingsService();

  static const formatId = 'anima_backup_v1';
  static const fileExtension = 'anima-backup';
  static const activePersonaIdKey = 'active_persona_id';

  /// Document files Anima owns (whitelist — do not recurse Documents).
  static const documentFileNames = <String>[
    'anima_characters.json',
    'anima_chats.json',
    'anima_personas.json',
    'anima_character_categories.json',
    'anima_lorebooks.json',
    'anima_world_workshops.json',
    'anima_composer_drafts.json',
    'anima_roadway_cache.json',
  ];

  static const _maxAvatarBytes = 8 * 1024 * 1024; // 8 MB per image
  static const _maxAvatarCount = 200;
  static const _maxJsonFileBytes = 40 * 1024 * 1024; // 40 MB

  final Future<Directory> Function() _documentsDirectory;
  final SettingsService _settingsService;
  final PersonaService? personaService;
  final Future<Map<String, String>> Function()? loadPreferences;
  final Future<void> Function(Map<String, String>)? savePreferences;

  PersonaService get _personas =>
      personaService ??
      PersonaService(
        documentsDirectory: _documentsDirectory,
        settingsService: _settingsService,
      );

  /// Build a backup payload and return encoded JSON bytes + a short summary.
  Future<AppBackupBundle> createBackup() async {
    final docs = await _documentsDirectory();
    final files = <String, String>{};
    for (final name in documentFileNames) {
      final file = File(p.join(docs.path, name));
      if (!await file.exists()) continue;
      files[name] = await file.readAsString();
    }

    final avatars = <String, String>{};
    final avatarsDir = Directory(p.join(docs.path, 'avatars'));
    if (await avatarsDir.exists()) {
      await for (final entity in avatarsDir.list(followLinks: false)) {
        if (entity is! File) continue;
        final name = p.basename(entity.path);
        if (!_isSafeAvatarName(name)) continue;
        final bytes = await entity.readAsBytes();
        if (bytes.length > _maxAvatarBytes) {
          throw AppBackupException(
            'Avatar “$name” is too large to include in a backup.',
          );
        }
        avatars[name] = base64Encode(bytes);
      }
    }

    final preferences = await _exportPreferences();

    final createdAt = DateTime.now().toUtc();
    final payload = <String, dynamic>{
      'format': formatId,
      'createdAt': createdAt.toIso8601String(),
      'files': files,
      'avatars': avatars,
      'settings': preferences,
    };

    final json = const JsonEncoder.withIndent('  ').convert(payload);
    final summary = AppBackupSummary(
      createdAt: createdAt,
      fileCount: files.length,
      avatarCount: avatars.length,
      settingsCount: preferences.length,
    );
    return AppBackupBundle(
      bytes: Uint8List.fromList(utf8.encode(json)),
      summary: summary,
    );
  }

  /// Decode and validate a backup file without writing anything.
  Future<AppBackupPayload> inspectBackup(Uint8List bytes) async {
    return _decode(bytes);
  }

  /// Replace Anima document files, avatars, and preferences from [bytes].
  ///
  /// Does **not** touch the NanoGPT API key.
  Future<AppBackupSummary> restoreBackup(Uint8List bytes) async {
    final payload = await _decode(bytes);
    final docs = await _documentsDirectory();

    // Stage under a temp folder first, then swap into place.
    final staging = await Directory.systemTemp.createTemp('anima_restore_');
    try {
      for (final entry in payload.files.entries) {
        final out = File(p.join(staging.path, entry.key));
        await out.writeAsString(entry.value, flush: true);
      }

      final stagedAvatars = Directory(p.join(staging.path, 'avatars'));
      await stagedAvatars.create(recursive: true);
      for (final entry in payload.avatars.entries) {
        final out = File(p.join(stagedAvatars.path, entry.key));
        await out.writeAsBytes(entry.value, flush: true);
      }

      // Apply document files (write present; delete known files absent from backup).
      for (final name in documentFileNames) {
        final target = File(p.join(docs.path, name));
        final staged = File(p.join(staging.path, name));
        if (await staged.exists()) {
          await target.writeAsBytes(await staged.readAsBytes(), flush: true);
        } else if (await target.exists()) {
          await target.delete();
        }
      }

      // Replace avatars folder contents with the backup set.
      final avatarsDir = Directory(p.join(docs.path, 'avatars'));
      if (await avatarsDir.exists()) {
        await for (final entity in avatarsDir.list(followLinks: false)) {
          if (entity is File) {
            try {
              await entity.delete();
            } catch (_) {}
          }
        }
      } else {
        await avatarsDir.create(recursive: true);
      }
      await for (final entity in stagedAvatars.list(followLinks: false)) {
        if (entity is! File) continue;
        final name = p.basename(entity.path);
        final dest = File(p.join(avatarsDir.path, name));
        await dest.writeAsBytes(await entity.readAsBytes(), flush: true);
      }

      await _importPreferences(payload.settings);
    } finally {
      try {
        await staging.delete(recursive: true);
      } catch (_) {}
    }

    return payload.summary;
  }

  Future<AppBackupPayload> _decode(Uint8List bytes) async {
    if (bytes.isEmpty) {
      throw AppBackupException('That backup file is empty.');
    }

    late final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes));
    } catch (_) {
      throw AppBackupException(
        'That file is not a valid Anima backup (bad JSON).',
      );
    }
    if (decoded is! Map) {
      throw AppBackupException('That file is not a valid Anima backup.');
    }
    final map = Map<String, dynamic>.from(decoded);
    final format = map['format']?.toString();
    if (format != formatId) {
      throw AppBackupException(
        format == null
            ? 'That file is not an Anima backup.'
            : 'This backup format (“$format”) is not supported.',
      );
    }

    final filesRaw = map['files'];
    if (filesRaw is! Map) {
      throw AppBackupException('Backup is missing its file list.');
    }
    final files = <String, String>{};
    for (final entry in filesRaw.entries) {
      final name = entry.key.toString();
      if (!_isAllowedDocumentName(name)) {
        throw AppBackupException('Backup has an unexpected file: $name');
      }
      final text = entry.value?.toString() ?? '';
      if (utf8.encode(text).length > _maxJsonFileBytes) {
        throw AppBackupException('Backup file “$name” is too large.');
      }
      if (text.trim().isNotEmpty) {
        try {
          jsonDecode(text);
        } catch (_) {
          throw AppBackupException(
            'Backup file “$name” is not valid JSON.',
          );
        }
      }
      files[name] = text;
    }

    final avatarsRaw = map['avatars'];
    if (avatarsRaw != null && avatarsRaw is! Map) {
      throw AppBackupException('Backup avatar list is invalid.');
    }
    final avatars = <String, Uint8List>{};
    if (avatarsRaw is Map) {
      if (avatarsRaw.length > _maxAvatarCount) {
        throw AppBackupException('Backup has too many avatars.');
      }
      for (final entry in avatarsRaw.entries) {
        final name = entry.key.toString();
        if (!_isSafeAvatarName(name)) {
          throw AppBackupException('Backup has an unsafe avatar name: $name');
        }
        try {
          final raw = base64Decode(entry.value?.toString() ?? '');
          if (raw.length > _maxAvatarBytes) {
            throw AppBackupException('Avatar “$name” is too large.');
          }
          avatars[name] = Uint8List.fromList(raw);
        } catch (e) {
          if (e is AppBackupException) rethrow;
          throw AppBackupException('Avatar “$name” could not be decoded.');
        }
      }
    }

    final settingsRaw = map['settings'];
    if (settingsRaw != null && settingsRaw is! Map) {
      throw AppBackupException('Backup settings list is invalid.');
    }
    final settings = <String, String>{};
    if (settingsRaw is Map) {
      for (final entry in settingsRaw.entries) {
        final key = entry.key.toString();
        if (key == 'nanogpt_api_key') {
          // Never restore secrets from a backup file.
          continue;
        }
        if (!_isAllowedPreferenceKey(key)) {
          throw AppBackupException('Backup has an unexpected setting: $key');
        }
        settings[key] = entry.value?.toString() ?? '';
      }
    }

    DateTime createdAt;
    try {
      createdAt = DateTime.parse(map['createdAt']?.toString() ?? '');
    } catch (_) {
      createdAt = DateTime.now().toUtc();
    }

    return AppBackupPayload(
      files: files,
      avatars: avatars,
      settings: settings,
      summary: AppBackupSummary(
        createdAt: createdAt,
        fileCount: files.length,
        avatarCount: avatars.length,
        settingsCount: settings.length,
      ),
    );
  }

  Future<Map<String, String>> _exportPreferences() async {
    final loader = loadPreferences;
    if (loader != null) return loader();

    final prefs = await _settingsService.exportForBackup();
    final activeId = await _personas.getActivePersonaId();
    if (activeId != null && activeId.isNotEmpty) {
      prefs[activePersonaIdKey] = activeId;
    }
    return prefs;
  }

  Future<void> _importPreferences(Map<String, String> values) async {
    final saver = savePreferences;
    if (saver != null) {
      await saver(values);
      return;
    }

    final settingsOnly = Map<String, String>.from(values)
      ..remove(activePersonaIdKey);
    await _settingsService.importFromBackup(settingsOnly);

    final activeId = values[activePersonaIdKey];
    await _personas.setActivePersonaId(
      (activeId == null || activeId.isEmpty) ? null : activeId,
    );
  }

  bool _isAllowedDocumentName(String name) {
    if (name.contains('/') || name.contains('\\') || name.contains('..')) {
      return false;
    }
    return documentFileNames.contains(name);
  }

  bool _isSafeAvatarName(String name) {
    if (name.isEmpty || name != p.basename(name)) return false;
    if (name.contains('..') || name.contains('/') || name.contains('\\')) {
      return false;
    }
    // Keep names boring: letters, digits, dash, underscore, dot.
    return RegExp(r'^[\w.\-]+$').hasMatch(name);
  }

  bool _isAllowedPreferenceKey(String key) {
    if (key == activePersonaIdKey) return true;
    return SettingsService.backupPreferenceKeys.contains(key);
  }
}

class AppBackupBundle {
  const AppBackupBundle({
    required this.bytes,
    required this.summary,
  });

  final Uint8List bytes;
  final AppBackupSummary summary;
}

class AppBackupPayload {
  const AppBackupPayload({
    required this.files,
    required this.avatars,
    required this.settings,
    required this.summary,
  });

  final Map<String, String> files;
  final Map<String, Uint8List> avatars;
  final Map<String, String> settings;
  final AppBackupSummary summary;
}

class AppBackupSummary {
  const AppBackupSummary({
    required this.createdAt,
    required this.fileCount,
    required this.avatarCount,
    required this.settingsCount,
  });

  final DateTime createdAt;
  final int fileCount;
  final int avatarCount;
  final int settingsCount;

  String get shortDescription {
    final parts = <String>[
      '$fileCount data file${fileCount == 1 ? '' : 's'}',
      '$avatarCount avatar${avatarCount == 1 ? '' : 's'}',
      '$settingsCount setting${settingsCount == 1 ? '' : 's'}',
    ];
    return parts.join(' · ');
  }
}

class AppBackupException implements Exception {
  AppBackupException(this.message);
  final String message;

  @override
  String toString() => message;
}
