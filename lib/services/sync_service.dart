import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:saf/saf.dart';
// ignore: implementation_imports
import 'package:saf/src/storage_access_framework/api.dart' as saf_legacy;

import '../models/sync_target.dart';
import 'app_backup_service.dart';
import 'settings_service.dart';

/// Push / pull one `.anima-backup` sync file for phone ↔ desktop handoff.
class SyncService {
  SyncService({
    required this.settingsService,
    required this.backupService,
  });

  static const defaultFileName = 'anima-sync.anima-backup';
  static const mimeType = 'application/json';

  final SettingsService settingsService;
  final AppBackupService backupService;

  Future<SyncTarget> loadTarget() async {
    return SyncTarget(
      filePath: await settingsService.getSyncFilePath(),
      contentUri: await settingsService.getSyncContentUri(),
    );
  }

  Future<bool> get isConfigured async => (await loadTarget()).isConfigured;

  /// Desktop: pick an existing sync file (e.g. in Google Drive folder).
  Future<SyncTarget?> chooseExistingSyncFile() async {
    if (Platform.isAndroid) {
      final saf = Saf();
      final dir = await saf.pickDirectory(
        writePermission: true,
        persistablePermission: true,
      );
      if (dir == null) return null;
      await settingsService.saveSyncContentUri(dir.uri);
      await settingsService.saveSyncFilePath(null);
      return SyncTarget(contentUri: dir.uri);
    }

    final pick = await FilePicker.platform.pickFiles(
      dialogTitle: 'Choose sync file',
      type: FileType.custom,
      allowedExtensions: [AppBackupService.fileExtension],
      allowMultiple: false,
    );
    if (pick == null || pick.files.isEmpty) return null;
    final path = pick.files.single.path;
    if (path == null || path.trim().isEmpty) {
      throw SyncException(
        'Could not read that file path. Try again or create a new sync file.',
      );
    }
    final normalized = _ensureBackupExtension(path.trim());
    await settingsService.saveSyncFilePath(normalized);
    await settingsService.saveSyncContentUri(null);
    return SyncTarget(filePath: normalized);
  }

  /// Desktop: create a new sync file (writes an initial backup).
  Future<SyncTarget?> createSyncFile() async {
    final bundle = await backupService.createBackup();
    if (Platform.isAndroid) {
      final saf = Saf();
      final dir = await saf.pickDirectory(
        writePermission: true,
        persistablePermission: true,
      );
      if (dir == null) return null;
      final doc = await saf.writeFileBytes(
        dir.uri,
        defaultFileName,
        mimeType,
        bundle.bytes,
        overwrite: true,
      );
      await settingsService.saveSyncContentUri(dir.uri);
      await settingsService.saveSyncFilePath(null);
      return SyncTarget(contentUri: doc.uri);
    }

    String? initialDirectory;
    try {
      initialDirectory = await _guessGoogleDriveFolder();
    } catch (_) {}

    final pickedPath = await FilePicker.platform.saveFile(
      dialogTitle: 'Create sync file',
      fileName: defaultFileName,
      initialDirectory: initialDirectory,
      type: FileType.custom,
      allowedExtensions: [AppBackupService.fileExtension],
      bytes: bundle.bytes,
    );
    if (pickedPath == null) return null;
    final savedPath = _ensureBackupExtension(pickedPath);
    final file = File(savedPath);
    await file.writeAsBytes(bundle.bytes, flush: true);
    await settingsService.saveSyncFilePath(savedPath);
    await settingsService.saveSyncContentUri(null);
    return SyncTarget(filePath: savedPath);
  }

  Future<void> clearSyncTarget() async {
    await settingsService.clearSyncTarget();
  }

  Future<AppBackupSummary> peekRemote() async {
    final bytes = await _readSyncBytes(await loadTarget());
    final payload = await backupService.inspectBackup(bytes);
    return payload.summary;
  }

  Future<SyncPushResult> push() async {
    final target = await loadTarget();
    if (!target.isConfigured) {
      throw SyncException('Choose a sync file first.');
    }
    final bundle = await backupService.createBackup();
    await _writeSyncBytes(target, bundle.bytes);
    final pushedAt = DateTime.now().toUtc();
    await settingsService.saveSyncLastPushAt(pushedAt);
    return SyncPushResult(
      pushedAt: pushedAt,
      summary: bundle.summary,
    );
  }

  Future<SyncPullResult> pull() async {
    final target = await loadTarget();
    if (!target.isConfigured) {
      throw SyncException('Choose a sync file first.');
    }
    final bytes = await _readSyncBytes(target);
    final restored = await backupService.restoreBackup(bytes);
    final pulledAt = DateTime.now().toUtc();
    await settingsService.saveSyncLastPullAt(pulledAt);
    return SyncPullResult(
      pulledAt: pulledAt,
      summary: restored,
    );
  }

  Future<Uint8List> _readSyncBytes(SyncTarget target) async {
    final path = target.filePath?.trim();
    if (path != null && path.isNotEmpty) {
      final file = File(path);
      if (!await file.exists()) {
        throw SyncException('Sync file not found at:\n$path');
      }
      return file.readAsBytes();
    }

    final uri = target.contentUri?.trim();
    if (uri != null && uri.isNotEmpty) {
      if (!Platform.isAndroid) {
        throw SyncException('This device uses a file path for sync, not a URI.');
      }
      return _readAndroidBytes(uri);
    }

    throw SyncException('Choose a sync file first.');
  }

  Future<void> _writeSyncBytes(SyncTarget target, Uint8List bytes) async {
    final path = target.filePath?.trim();
    if (path != null && path.isNotEmpty) {
      final file = File(path);
      await file.writeAsBytes(bytes, flush: true);
      return;
    }

    final uri = target.contentUri?.trim();
    if (uri != null && uri.isNotEmpty) {
      if (!Platform.isAndroid) {
        throw SyncException('This device uses a file path for sync, not a URI.');
      }
      await _writeAndroidBytes(uri, bytes);
      return;
    }

    throw SyncException('Choose a sync file first.');
  }

  Future<Uint8List> _readAndroidBytes(String uri) async {
    final saf = Saf();
    final meta = await saf.stat(uri);
    if (meta == null) {
      throw SyncException(
        'Sync file is no longer accessible. Choose the sync folder again.',
      );
    }

    if (meta.isDir) {
      final file = await saf_legacy.findFile(
        Uri.parse(uri),
        defaultFileName,
      );
      if (file == null) {
        throw SyncException(
          '“$defaultFileName” was not found in the sync folder. '
          'Create sync file or Push from another device first.',
        );
      }
      return saf.readFileBytes(file.uri.toString());
    }

    return saf.readFileBytes(uri);
  }

  Future<void> _writeAndroidBytes(String uri, Uint8List bytes) async {
    final saf = Saf();
    final meta = await saf.stat(uri);
    if (meta == null) {
      throw SyncException(
        'Sync file is no longer accessible. Choose the sync folder again.',
      );
    }

    if (meta.isDir) {
      await saf.writeFileBytes(
        uri,
        defaultFileName,
        mimeType,
        bytes,
        overwrite: true,
      );
      return;
    }

    // Legacy: user picked a single file — overwrite via parent folder + name.
    final parent = await saf_legacy.parentFile(Uri.parse(uri));
    if (parent == null) {
      throw SyncException(
        'Could not update the sync file. Tap the link icon and choose the '
        'Google Drive folder again (not the file itself).',
      );
    }
    await saf.writeFileBytes(
      parent.uri.toString(),
      meta.name,
      mimeType,
      bytes,
      overwrite: true,
    );
  }

  String _ensureBackupExtension(String path) {
    final extension = '.${AppBackupService.fileExtension}';
    if (path.toLowerCase().endsWith(extension)) return path;
    return '$path$extension';
  }

  Future<String?> _guessGoogleDriveFolder() async {
    if (!Platform.isWindows) return null;
    final user = Platform.environment['USERPROFILE'];
    if (user == null || user.isEmpty) return null;
    final candidates = <String>[
      p.join(user, 'Google Drive'),
      p.join(user, 'My Drive'),
      'G:\\My Drive',
      'G:\\Google Drive',
    ];
    for (final candidate in candidates) {
      if (await Directory(candidate).exists()) return candidate;
    }
    return null;
  }
}

class SyncPushResult {
  const SyncPushResult({required this.pushedAt, required this.summary});

  final DateTime pushedAt;
  final AppBackupSummary summary;
}

class SyncPullResult {
  const SyncPullResult({required this.pulledAt, required this.summary});

  final DateTime pulledAt;
  final AppBackupSummary summary;
}

class SyncException implements Exception {
  SyncException(this.message);
  final String message;

  @override
  String toString() => message;
}
