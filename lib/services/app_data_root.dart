import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../utils/platform_utils.dart';
import 'android_storage.dart';
import 'settings_store.dart';

/// One user-owned folder for the whole Anima library.
///
/// Android's default app documents path is locked on modern Samsung phones.
/// This service keeps characters, chats, avatars, settings, and the API key
/// in a normal folder you can open in My Files / Files / Explorer.
///
/// The only thing that stays in hidden app storage is a tiny pointer file
/// that remembers *which* folder you chose (so the next launch finds it).
class AppDataRoot {
  AppDataRoot({
    Future<Directory> Function()? supportDirectory,
    Future<Directory> Function()? legacyDocumentsDirectory,
    this.executableDirectory,
    this.homeDirectory,
    this.androidPublicDocumentsPath,
    bool? isAndroid,
    bool? isDesktop,
    Future<bool> Function()? requestStorageAccess,
    Future<bool> Function()? hasStorageAccess,
    Future<String?> Function()? pickDirectoryPath,
  })  : _supportDirectory =
            supportDirectory ?? getApplicationSupportDirectory,
        _legacyDocumentsDirectory =
            legacyDocumentsDirectory ?? getApplicationDocumentsDirectory,
        _isAndroid = isAndroid ?? (!kIsWeb && Platform.isAndroid),
        _isDesktop = isDesktop ?? isDesktopPlatform,
        _requestStorageAccess =
            requestStorageAccess ?? AndroidStorage.ensureAccess,
        _hasStorageAccess =
            hasStorageAccess ?? AndroidStorage.hasAllFilesAccess,
        _pickDirectoryPath = pickDirectoryPath ?? _defaultPickDirectory;

  static AppDataRoot? instance;

  static const pointerFileName = 'anima_data_root.json';
  static const readmeFileName = 'README.txt';
  static const apiKeyFileName = 'api_key.txt';
  static const activePersonaFileName = 'anima_active_persona_id.txt';
  static const folderName = 'Anima';
  static const portableFolderName = 'AnimaData';

  static const libraryFileNames = <String>[
    'anima_characters.json',
    'anima_chats.json',
    'anima_personas.json',
    'anima_character_categories.json',
    'anima_lorebooks.json',
    'anima_world_workshops.json',
    'anima_composer_drafts.json',
    'anima_roadway_cache.json',
    FileSettingsKv.fileName,
    apiKeyFileName,
    activePersonaFileName,
  ];

  static const librarySubdirs = <String>['avatars', 'chat_backgrounds'];

  static const readmeText =
      'This folder is your Anima library.\n'
      '\n'
      'Characters, chats, avatars, lorebooks, workshops, settings, and your\n'
      'NanoGPT API key live here. Copy this whole folder to back up Anima or\n'
      'move it to another phone or PC.\n'
      '\n'
      'Do not share this folder publicly — api_key.txt is your NanoGPT key.\n';

  final Future<Directory> Function() _supportDirectory;
  final Future<Directory> Function() _legacyDocumentsDirectory;
  final String? executableDirectory;
  final String? homeDirectory;
  final String? androidPublicDocumentsPath;
  final bool _isAndroid;
  final bool _isDesktop;
  final Future<bool> Function() _requestStorageAccess;
  final Future<bool> Function() _hasStorageAccess;
  final Future<String?> Function() _pickDirectoryPath;

  String? _path;

  bool get isConfigured => _path != null && _path!.trim().isNotEmpty;

  String? get path => _path;

  factory AppDataRoot.platform() {
    String? exeDir;
    try {
      exeDir = File(Platform.resolvedExecutable).parent.path;
    } catch (_) {}
    return AppDataRoot(
      executableDirectory: exeDir,
      homeDirectory: Platform.environment['HOME'] ??
          Platform.environment['USERPROFILE'],
    );
  }

  Future<Directory> directory() async {
    final path = _path?.trim();
    if (path == null || path.isEmpty) {
      throw StateError('Anima data folder is not chosen yet.');
    }
    final dir = Directory(path);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Suggested visible folder: Documents/Anima.
  Future<String> defaultPublicPath() async {
    if (_isAndroid) {
      final docs = (androidPublicDocumentsPath ??
              await AndroidStorage.publicDocumentsPath())
          .trim();
      return p.join(docs, folderName);
    }
    final home = (homeDirectory ?? '').trim();
    if (home.isNotEmpty) {
      return p.join(home, 'Documents', folderName);
    }
    final legacy = await _legacyDocumentsDirectory();
    return p.join(legacy.path, folderName);
  }

  /// Folder next to the app binary (zip / portable desktop install).
  String? portablePath() {
    final exe = executableDirectory?.trim();
    if (exe == null || exe.isEmpty) return null;
    return p.join(exe, portableFolderName);
  }

  Future<bool> get canUsePortableFolder async {
    if (!_isDesktop) return false;
    final path = portablePath();
    if (path == null) return false;
    return isDirectoryWritable(Directory(path));
  }

  /// Load the saved pointer, or adopt an existing library folder.
  Future<bool> load() async {
    final pointer = await _readPointer();
    if (pointer != null && await _isUsableDirectory(pointer)) {
      _path = pointer;
      return true;
    }

    final publicPath = await defaultPublicPath();
    if (await looksLikeLibrary(Directory(publicPath))) {
      await setPath(publicPath, migrateLegacy: false);
      return true;
    }

    final portable = portablePath();
    if (portable != null && await looksLikeLibrary(Directory(portable))) {
      await setPath(portable, migrateLegacy: false);
      return true;
    }

    return false;
  }

  Future<void> setPath(String path, {required bool migrateLegacy}) async {
    final trimmed = path.trim();
    if (trimmed.isEmpty) {
      throw AppDataRootException('Choose a folder for Anima.');
    }
    final dir = Directory(trimmed);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    if (!await isDirectoryWritable(dir)) {
      throw AppDataRootException(
        'Anima could not write to that folder. Pick a different location.',
      );
    }

    if (migrateLegacy) {
      final legacy = await _legacyDocumentsDirectory();
      await copyLibrary(from: legacy, to: dir);
    }

    await writeReadme(dir);
    _path = dir.path;
    await _writePointer(dir.path);
  }

  /// Copy the current library into [path] and switch to it.
  Future<void> changePath(String path) async {
    final trimmed = path.trim();
    if (trimmed.isEmpty) {
      throw AppDataRootException('Choose a folder for Anima.');
    }
    final current = _path;
    final dest = Directory(trimmed);
    if (!await dest.exists()) {
      await dest.create(recursive: true);
    }
    if (!await isDirectoryWritable(dest)) {
      throw AppDataRootException(
        'Anima could not write to that folder. Pick a different location.',
      );
    }
    if (current != null &&
        p.normalize(current) != p.normalize(dest.path)) {
      await copyLibrary(from: Directory(current), to: dest);
    }
    await writeReadme(dest);
    _path = dest.path;
    await _writePointer(dest.path);
  }

  Future<String?> pickFolder() => _pickDirectoryPath();

  Future<bool> ensureStorageAccess() => _requestStorageAccess();

  Future<bool> hasStorageAccess() => _hasStorageAccess();

  static Future<bool> looksLikeLibrary(Directory dir) async {
    if (!await dir.exists()) return false;
    for (final name in libraryFileNames) {
      if (await File(p.join(dir.path, name)).exists()) return true;
    }
    for (final name in librarySubdirs) {
      if (await Directory(p.join(dir.path, name)).exists()) return true;
    }
    return false;
  }

  static Future<bool> isDirectoryWritable(Directory dir) async {
    try {
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final probe = File(
        p.join(
          dir.path,
          '.anima_write_test_${DateTime.now().microsecondsSinceEpoch}',
        ),
      );
      await probe.writeAsString('ok', flush: true);
      await probe.delete();
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> writeReadme(Directory dir) async {
    final file = File(p.join(dir.path, readmeFileName));
    if (await file.exists()) return;
    await file.writeAsString(readmeText, flush: true);
  }

  static Future<void> copyLibrary({
    required Directory from,
    required Directory to,
  }) async {
    if (p.normalize(from.path) == p.normalize(to.path)) return;
    if (!await from.exists()) return;
    if (!await to.exists()) {
      await to.create(recursive: true);
    }

    for (final name in libraryFileNames) {
      final src = File(p.join(from.path, name));
      if (!await src.exists()) continue;
      final dest = File(p.join(to.path, name));
      if (!await dest.parent.exists()) {
        await dest.parent.create(recursive: true);
      }
      await src.copy(dest.path);
    }

    for (final name in librarySubdirs) {
      final srcDir = Directory(p.join(from.path, name));
      if (!await srcDir.exists()) continue;
      final destDir = Directory(p.join(to.path, name));
      await destDir.create(recursive: true);
      await for (final entity in srcDir.list(followLinks: false)) {
        if (entity is! File) continue;
        final dest = File(p.join(destDir.path, p.basename(entity.path)));
        await entity.copy(dest.path);
      }
    }
  }

  Future<File> _pointerFile() async {
    final support = await _supportDirectory();
    if (!await support.exists()) {
      await support.create(recursive: true);
    }
    return File(p.join(support.path, pointerFileName));
  }

  Future<String?> _readPointer() async {
    try {
      final file = await _pointerFile();
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map && decoded['path'] is String) {
        final path = (decoded['path'] as String).trim();
        if (path.isNotEmpty) return path;
      }
    } catch (_) {}
    return null;
  }

  Future<void> _writePointer(String path) async {
    final file = await _pointerFile();
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert({'path': path}),
      flush: true,
    );
  }

  Future<bool> _isUsableDirectory(String path) async {
    try {
      final dir = Directory(path);
      if (await dir.exists()) {
        return await isDirectoryWritable(dir);
      }
      await dir.create(recursive: true);
      return await isDirectoryWritable(dir);
    } catch (_) {
      return false;
    }
  }

  static Future<String?> _defaultPickDirectory() {
    return FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Choose Anima folder',
    );
  }
}

class AppDataRootException implements Exception {
  AppDataRootException(this.message);
  final String message;

  @override
  String toString() => message;
}
