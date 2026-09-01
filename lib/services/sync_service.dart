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

  /// Some providers (GNOME gvfs Google Drive on Linux, Android SAF) can return
  /// a stale or partially downloaded copy right after the folder is (re)mounted
  /// or first opened. Reading once can restore an old snapshot — which made
  /// Pull look like it "did nothing" on the first tap. We read until two
  /// consecutive reads return identical, non-empty bytes (the file has been
  /// fetched and is stable), then trust that copy.
  static const readStableRetries = 5;
  static const readStableDelay = Duration(milliseconds: 250);

  /// Reads [read] until two consecutive results are identical non-empty bytes,
  /// or until [retries] runs are exhausted (last non-empty result is returned).
  static Future<Uint8List> readStableBytes(
    Future<Uint8List> Function() read, {
    int retries = readStableRetries,
    Duration delay = readStableDelay,
  }) async {
    Uint8List? previous;
    for (var attempt = 0; attempt < retries; attempt++) {
      final bytes = await read();
      if (bytes.isNotEmpty) {
        if (previous != null && _bytesEqual(previous, bytes)) {
          return bytes;
        }
        previous = bytes;
      }
      await Future<void>.delayed(delay);
    }
    if (previous != null && previous.isNotEmpty) return previous;
    throw SyncException(
      'The sync file came back empty. Open the folder once, then try '
      'Pull again.',
    );
  }

  static bool _bytesEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  final SettingsService settingsService;
  final AppBackupService backupService;

  Future<SyncTarget> loadTarget() async {
    var path = await settingsService.getSyncFilePath();
    if (path != null && path.trim().isNotEmpty) {
      final resolved = await resolveExistingSyncPath(path.trim());
      if (resolved != null && resolved != path) {
        await settingsService.saveSyncFilePath(resolved);
        path = resolved;
      }
    }
    return SyncTarget(
      filePath: path,
      contentUri: await settingsService.getSyncContentUri(),
      friendlyName: path == null || path.trim().isEmpty
          ? null
          : await friendlyNameForPath(path),
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
    final resolved = await resolveExistingSyncPath(path.trim());
    if (resolved == null) {
      throw SyncException(
        'Could not open that Google Drive file. Open Files → Google Drive '
        'once so it connects, then pick anima-sync.anima-backup again.',
      );
    }
    await settingsService.saveSyncFilePath(resolved);
    await settingsService.saveSyncContentUri(null);
    return SyncTarget(
      filePath: resolved,
      friendlyName: await friendlyNameForPath(resolved),
    );
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
    final resolved = await resolveExistingSyncPath(savedPath) ?? savedPath;
    await settingsService.saveSyncFilePath(resolved);
    await settingsService.saveSyncContentUri(null);
    return SyncTarget(
      filePath: resolved,
      friendlyName: await friendlyNameForPath(resolved),
    );
  }

  Future<void> clearSyncTarget() async {
    await settingsService.clearSyncTarget();
  }

  Future<AppBackupSummary> peekRemote() async {
    final target = await loadTarget();
    final bytes = await readStableBytes(() => _readSyncBytes(target));
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
    final bytes = await readStableBytes(() => _readSyncBytes(target));
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
      final resolved = await resolveExistingSyncPath(path);
      if (resolved == null) {
        throw SyncException(_missingDesktopFileMessage(path));
      }
      if (resolved != path) {
        await settingsService.saveSyncFilePath(resolved);
      }
      return File(resolved).readAsBytes();
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
      final resolved = await resolveExistingSyncPath(path);
      if (resolved == null) {
        throw SyncException(_missingDesktopFileMessage(path));
      }
      if (resolved != path) {
        await settingsService.saveSyncFilePath(resolved);
      }
      await File(resolved).writeAsBytes(bytes, flush: true);
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

  /// GNOME Google Drive (gvfs) stores files under a Drive ID with no
  /// `.anima-backup` suffix. The file picker often appends that suffix anyway.
  /// Drive also unmounts when idle — we remount before looking for the file.
  static Future<String?> resolveExistingSyncPath(String path) async {
    final trimmed = path.trim();
    if (trimmed.isEmpty) return null;

    await ensureGoogleDriveMounted(trimmed);

    if (await File(trimmed).exists()) return trimmed;

    const suffix = '.anima-backup';
    if (trimmed.toLowerCase().endsWith(suffix)) {
      final stripped = trimmed.substring(0, trimmed.length - suffix.length);
      if (stripped.isNotEmpty && await File(stripped).exists()) {
        return stripped;
      }
    }

    final dir = Directory(p.dirname(trimmed));
    if (!await dir.exists()) return null;

    final wanted = p.basename(trimmed);
    final strippedName = wanted.toLowerCase().endsWith(suffix)
        ? wanted.substring(0, wanted.length - suffix.length)
        : wanted;

    try {
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is! File) continue;
        final name = p.basename(entity.path);
        if (name == wanted || name == strippedName) return entity.path;
      }
    } catch (_) {}

    return null;
  }

  /// Builds `google-drive://user@host/` from a GNOME gvfs local path.
  ///
  /// Example path fragment: `google-drive:host=gmail.com,user=wjakwan`
  static String? googleDriveMountUriFromPath(String path) {
    final match = RegExp(
      r'google-drive:host=([^,/]+),user=([^/]+)',
    ).firstMatch(path);
    if (match == null) return null;
    final host = match.group(1)?.trim();
    final user = match.group(2)?.trim();
    if (host == null || host.isEmpty || user == null || user.isEmpty) {
      return null;
    }
    return 'google-drive://$user@$host/';
  }

  /// Remounts GNOME Files → Google Drive when the gvfs folder is idle/unmounted.
  static Future<bool> ensureGoogleDriveMounted(String path) async {
    if (!Platform.isLinux) return false;
    final uri = googleDriveMountUriFromPath(path);
    if (uri == null) return false;

    // Already reachable — nothing to do.
    if (await File(path).exists()) return true;
    final parent = Directory(p.dirname(path));
    if (await parent.exists()) return true;

    try {
      final result = await Process.run('gio', ['mount', uri]).timeout(
        const Duration(seconds: 25),
      );
      final out = '${result.stdout}\n${result.stderr}'.toLowerCase();
      final ok = result.exitCode == 0 ||
          out.contains('already mounted') ||
          out.contains('location is already mounted');
      if (!ok) return false;

      // gvfs can take a moment after mount before the path appears.
      for (var i = 0; i < 10; i++) {
        if (await File(path).exists() || await parent.exists()) return true;
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      return await File(path).exists() || await parent.exists();
    } catch (_) {
      return false;
    }
  }

  static Future<String?> friendlyNameForPath(String path) async {
    if (!Platform.isLinux) return null;
    await ensureGoogleDriveMounted(path);
    try {
      final result = await Process.run('gio', [
        'info',
        '-a',
        'standard::display-name',
        path,
      ]);
      if (result.exitCode != 0) return null;
      final match = RegExp(
        r'standard::display-name:\s*(.+)',
      ).firstMatch(result.stdout.toString());
      final name = match?.group(1)?.trim();
      if (name == null || name.isEmpty) return null;
      return name;
    } catch (_) {
      return null;
    }
  }

  String _missingDesktopFileMessage(String path) {
    final gvfs = path.contains('/gvfs/') || path.contains('google-drive');
    if (gvfs) {
      return 'Google Drive is not connected right now. Open Files → '
          'Google Drive once (or wait a few seconds), then try Push / Pull '
          'again. You usually do not need to re-pick the sync file.';
    }
    return 'Sync file not found at:\n$path';
  }

  Future<String?> _guessGoogleDriveFolder() async {
    if (Platform.isLinux) {
      final runtime = Platform.environment['XDG_RUNTIME_DIR'];
      if (runtime != null && runtime.isNotEmpty) {
        final gvfs = Directory(p.join(runtime, 'gvfs'));
        if (await gvfs.exists()) {
          try {
            await for (final mount in gvfs.list()) {
              if (!p.basename(mount.path).startsWith('google-drive')) {
                continue;
              }
              if (mount is! Directory) continue;
              await for (final child in mount.list()) {
                if (p.basename(child.path) == 'GVfsSharedWithMe') continue;
                return child.path;
              }
            }
          } catch (_) {}
        }
      }
    }
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
