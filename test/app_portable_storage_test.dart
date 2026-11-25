import 'dart:io';

import 'package:anima/services/api_key_service.dart';
import 'package:anima/services/app_data_root.dart';
import 'package:anima/services/settings_service.dart';
import 'package:anima/services/settings_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class _MemorySecureStorage extends FlutterSecureStorage {
  final Map<String, String> store = {};

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
      store.remove(key);
    } else {
      store[key] = value;
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
      store[key];

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
    store.remove(key);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => Future.value(null);
}

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('anima_settings_file_');
    AppDataRoot.instance = null;
  });

  tearDown(() async {
    AppDataRoot.instance = null;
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('file settings store writes JSON the user can open', () async {
    final storage = _MemorySecureStorage();
    final settings = SettingsService(
      storage: storage,
      documentsDirectory: () async => temp,
    );

    await settings.saveModel('test/model');
    final file = File(p.join(temp.path, FileSettingsKv.fileName));
    expect(await file.exists(), isTrue);
    expect(await file.readAsString(), contains('test/model'));
    expect(await settings.getModel(), 'test/model');
  });

  test('file settings store migrates keys from secure storage', () async {
    final storage = _MemorySecureStorage();
    storage.store['nanogpt_model'] = 'legacy/model';
    final settings = SettingsService(
      storage: storage,
      documentsDirectory: () async => temp,
    );

    expect(await settings.getModel(), 'legacy/model');
    expect(
      await File(p.join(temp.path, FileSettingsKv.fileName)).exists(),
      isTrue,
    );
  });

  test('API key lives in api_key.txt when a data folder is configured', () async {
    AppDataRoot.instance = AppDataRoot(
      supportDirectory: () async => temp,
      legacyDocumentsDirectory: () async => temp,
      homeDirectory: temp.path,
      isAndroid: false,
      isDesktop: true,
      requestStorageAccess: () async => true,
      hasStorageAccess: () async => true,
      pickDirectoryPath: () async => null,
    );
    await AppDataRoot.instance!.setPath(
      p.join(temp.path, 'library'),
      migrateLegacy: false,
    );

    final keys = ApiKeyService(
      storage: _MemorySecureStorage(),
      documentsDirectory: () async => AppDataRoot.instance!.directory(),
    );
    await keys.saveApiKey('sk-test-123');
    expect(await keys.getApiKey(), 'sk-test-123');
    expect(
      await File(
        p.join(AppDataRoot.instance!.path!, AppDataRoot.apiKeyFileName),
      ).readAsString(),
      'sk-test-123',
    );
  });
}
