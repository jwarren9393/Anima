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

    test('duplicate copies fields and assigns new id', () async {
      await personas.upsert(
        const Persona(
          id: 'persona_src',
          name: 'River',
          description: 'Scout captain.',
          personality: 'Bold.',
        ),
      );
      final copy = await personas.duplicate(
        (await personas.getById('persona_src'))!,
      );
      expect(copy.id, isNot('persona_src'));
      expect(copy.name, 'River (copy)');
      expect(copy.description, 'Scout captain.');
      expect((await personas.loadPersonas()).length, 2);
    });
  });

  group('CharacterService duplicate', () {
    test('copies card fields and lorebook', () async {
      const source = Character(
        id: 'char_src',
        name: 'Mira',
        description: 'Healer.',
        personality: 'Gentle.',
        characterBook: {
          'entries': [
            {'keys': ['mira'], 'content': 'Runs the clinic.', 'enabled': true},
          ],
        },
        tags: ['fantasy'],
      );
      await characters.upsert(source);
      final copy = await characters.duplicate(source);
      expect(copy.id, isNot(source.id));
      expect(copy.name, 'Mira (copy)');
      expect(copy.lorebook?.entries.length, 1);
      expect(copy.tags, ['fantasy']);
      expect((await characters.loadCharacters()).length, 2);
    });

    test('duplicateDisplayName avoids double suffix', () {
      expect(CharacterService.duplicateDisplayName('Hero'), 'Hero (copy)');
      expect(
        CharacterService.duplicateDisplayName('Hero (copy)'),
        'Hero (copy)',
      );
    });
  });
}
