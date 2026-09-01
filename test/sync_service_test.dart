import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:anima/services/app_backup_service.dart';
import 'package:anima/services/settings_service.dart';
import 'package:anima/services/sync_service.dart';

class _MemorySecureStorage extends FlutterSecureStorage {
  final Map<String, String> _store = {};

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      _store.remove(key);
    } else {
      _store[key] = value;
    }
  }

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      _store[key];

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _store.remove(key);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => Future.value(null);
}

void main() {
  late Directory tempDir;
  late Directory syncDir;
  late Map<String, String> prefs;
  late AppBackupService backupService;
  late SettingsService settings;
  late SyncService syncService;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('anima_sync_docs_');
    syncDir = await Directory.systemTemp.createTemp('anima_sync_file_');
    prefs = {'nanogpt_model': 'test/model'};
    backupService = AppBackupService(
      documentsDirectory: () async => tempDir,
      loadPreferences: () async => Map<String, String>.from(prefs),
      savePreferences: (values) async {
        prefs
          ..clear()
          ..addAll(values);
      },
    );
    settings = SettingsService(storage: _MemorySecureStorage());
    syncService = SyncService(
      settingsService: settings,
      backupService: backupService,
    );
    await File(p.join(tempDir.path, 'anima_chats.json')).writeAsString(
      '{"sessions":[{"id":"s1","characterId":"c1","messages":[]}]}',
    );
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
    if (await syncDir.exists()) await syncDir.delete(recursive: true);
  });

  test('push overwrites the same desktop sync file', () async {
    final syncPath = p.join(syncDir.path, SyncService.defaultFileName);
    await File(syncPath).writeAsString('{"format":"anima_backup_v1","files":{}}');

    await settings.saveSyncFilePath(syncPath);
    final first = await syncService.push();
    expect(first.summary.fileCount, greaterThan(0));

    final inspected = await backupService.inspectBackup(
      await File(syncPath).readAsBytes(),
    );
    expect(inspected.summary.fileCount, greaterThan(0));

    await File(p.join(tempDir.path, 'anima_characters.json'))
        .writeAsString('[{"id":"c2","name":"Nova"}]');
    await syncService.push();
    final again = await backupService.inspectBackup(
      await File(syncPath).readAsBytes(),
    );
    expect(again.files['anima_characters.json'], contains('Nova'));
  });

  test('pull restores from desktop sync file', () async {
    final bundle = await backupService.createBackup();
    final syncPath = p.join(syncDir.path, 'handoff.anima-backup');
    await File(syncPath).writeAsBytes(bundle.bytes);
    await settings.saveSyncFilePath(syncPath);

    await File(p.join(tempDir.path, 'anima_chats.json'))
        .writeAsString('{"sessions":[]}');
    final result = await syncService.pull();
    expect(result.summary.fileCount, greaterThan(0));

    final chats =
        await File(p.join(tempDir.path, 'anima_chats.json')).readAsString();
    expect(chats, contains('s1'));
  });

  test('resolveExistingSyncPath strips a fake .anima-backup suffix', () async {
    final real = File(p.join(syncDir.path, 'DriveFileIdWithoutExt'));
    await real.writeAsString('{"format":"anima_backup_v1"}');
    final picked = '${real.path}.anima-backup';
    expect(await File(picked).exists(), isFalse);

    final resolved = await SyncService.resolveExistingSyncPath(picked);
    expect(resolved, real.path);
  });

  test('resolveExistingSyncPath keeps a real .anima-backup file', () async {
    final real = File(p.join(syncDir.path, 'anima-sync.anima-backup'));
    await real.writeAsString('{"format":"anima_backup_v1"}');

    final resolved = await SyncService.resolveExistingSyncPath(real.path);
    expect(resolved, real.path);
  });

  test('googleDriveMountUriFromPath builds a gio mount URI', () {
    const path =
        '/run/user/1000/gvfs/google-drive:host=gmail.com,user=wjakwan/'
        '0ABT1xvYnwo7lUk9PVA/fileId';
    expect(
      SyncService.googleDriveMountUriFromPath(path),
      'google-drive://wjakwan@gmail.com/',
    );
    expect(SyncService.googleDriveMountUriFromPath('/tmp/local.backup'), isNull);
  });

  test('readStableBytes returns immediately when already stable', () async {
    final bytes = Uint8List.fromList([5, 5, 5]);
    var calls = 0;
    final result = await SyncService.readStableBytes(
      () async {
        calls++;
        return bytes;
      },
      delay: Duration.zero,
    );
    expect(calls, 2);
    expect(result, bytes);
  });

  test('readStableBytes waits until two consecutive reads agree', () async {
    final stale = Uint8List.fromList([1, 2, 3]);
    final fresh = Uint8List.fromList([9, 9, 9, 9]);
    var calls = 0;
    final result = await SyncService.readStableBytes(
      () async {
        calls++;
        if (calls == 1) return stale;
        return fresh;
      },
      retries: 4,
      delay: Duration.zero,
    );
    expect(calls, 3);
    expect(result, fresh);
  });

  test('readStableBytes throws on a permanently empty file', () async {
    await expectLater(
      SyncService.readStableBytes(
        () async => Uint8List(0),
        retries: 2,
        delay: Duration.zero,
      ),
      throwsA(isA<SyncException>()),
    );
  });
}
