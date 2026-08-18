import 'dart:io';

import 'package:anima/models/character.dart';
import 'package:anima/models/persona.dart';
import 'package:anima/services/character_service.dart';
import 'package:anima/services/persona_service.dart';
import 'package:anima/services/settings_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

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
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late CharacterService characters;
  late PersonaService personas;
  late SettingsService settings;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('anima_svc_test_');
    final storage = _MemorySecureStorage();
    characters = CharacterService(documentsDirectory: () async => tempDir);
    settings = SettingsService(storage: storage);
    personas = PersonaService(
      documentsDirectory: () async => tempDir,
      settingsService: settings,
      storage: storage,
    );
    await File('${tempDir.path}/anima_personas.json').writeAsString('[]');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('CharacterService', () {
    test('starts empty and stays empty after deleting the last card', () async {
      expect(await characters.loadCharacters(), isEmpty);

      final id = characters.newId();
      await characters.upsert(Character(id: id, name: 'Mira'));
      expect((await characters.loadCharacters()).length, 1);

      await characters.delete(id);
      expect(await characters.loadCharacters(), isEmpty);
    });
  });

  group('PersonaService', () {
    test('starts empty without legacy persona fields', () async {
      expect(await personas.loadPersonas(), isEmpty);
      expect(await personas.tryGetActivePersona(), isNull);
      expect((await personas.defaultForNewChat()).isAnonymous, isTrue);
    });

    test('allows deleting the last persona', () async {
      await personas.upsert(const Persona(id: 'persona_test', name: 'Jay'));
      expect((await personas.loadPersonas()).length, 1);

      await personas.delete('persona_test');
      expect(await personas.loadPersonas(), isEmpty);
      expect(await personas.getActivePersonaId(), isNull);
    });
  });
}
