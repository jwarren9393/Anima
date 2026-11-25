import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anima/services/settings_service.dart';

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
  test('toggle adds favorites newest-first and removes them', () async {
    final service = SettingsService(storage: _MemorySecureStorage());
    expect(await service.getFavoriteModels(), isEmpty);

    expect(
      await service.toggleFavoriteModel('a/model-1', provider: 'Provider A'),
      isTrue,
    );
    expect(
      await service.toggleFavoriteModel('b/model-2', provider: 'Provider B'),
      isTrue,
    );

    var favorites = await service.getFavoriteModels();
    expect(favorites.map((f) => f.id).toList(), ['b/model-2', 'a/model-1']);
    expect(favorites.first.provider, 'Provider B');

    expect(await service.toggleFavoriteModel('a/model-1'), isFalse);
    favorites = await service.getFavoriteModels();
    expect(favorites.map((f) => f.id).toList(), ['b/model-2']);
  });

  test('favorites are deduplicated by id', () async {
    final service = SettingsService(storage: _MemorySecureStorage());
    await service.toggleFavoriteModel('a/model-1', provider: 'Provider A');
    await service.saveFavoriteModels([
      const FavoriteModel(id: 'a/model-1'),
      const FavoriteModel(id: 'a/model-1', provider: 'Dup'),
      const FavoriteModel(id: 'a/model-1'),
    ]);

    final favorites = await service.getFavoriteModels();
    expect(favorites.length, 1);
    expect(favorites.single.id, 'a/model-1');
    expect(favorites.single.provider, 'Provider A');
  });

  test('favorites persist across instances and export for backup', () async {
    final storage = _MemorySecureStorage();
    final first = SettingsService(storage: storage);
    await first.toggleFavoriteModel('a/model-1', provider: 'Provider A');

    final exported = await first.exportForBackup();
    expect(exported['nanogpt_favorite_models'], isNotNull);

    final second = SettingsService(storage: storage);
    final favorites = await second.getFavoriteModels();
    expect(favorites.single.id, 'a/model-1');
    expect(favorites.single.provider, 'Provider A');
  });

  test('malformed stored JSON falls back to an empty list', () async {
    final storage = _MemorySecureStorage();
    await storage.write(key: 'nanogpt_favorite_models', value: 'not-json');
    final service = SettingsService(storage: storage);
    expect(await service.getFavoriteModels(), isEmpty);
  });
}