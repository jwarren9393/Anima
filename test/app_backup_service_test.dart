import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:anima/services/app_backup_service.dart';

void main() {
  late Directory tempDir;
  late Map<String, String> prefs;
  late AppBackupService service;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('anima_backup_');
    prefs = {
      'nanogpt_model': 'test/model',
      'sampling_temperature': '0.9',
      'active_persona_id': 'persona_1',
    };
    service = AppBackupService(
      documentsDirectory: () async => tempDir,
      loadPreferences: () async => Map<String, String>.from(prefs),
      savePreferences: (values) async {
        prefs
          ..clear()
          ..addAll(values);
      },
    );
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<void> seedDocs() async {
    await File(p.join(tempDir.path, 'anima_characters.json'))
        .writeAsString('[{"id":"c1","name":"Aiko"}]');
    await File(p.join(tempDir.path, 'anima_chats.json'))
        .writeAsString('{"sessions":[]}');
    final avatars = Directory(p.join(tempDir.path, 'avatars'));
    await avatars.create(recursive: true);
    await File(p.join(avatars.path, 'char_1.png'))
        .writeAsBytes(Uint8List.fromList([1, 2, 3, 4]));
  }

  test('round-trip restores files, avatars, and settings', () async {
    await seedDocs();

    final bundle = await service.createBackup();
    expect(bundle.summary.fileCount, 2);
    expect(bundle.summary.avatarCount, 1);
    expect(bundle.summary.settingsCount, 3);

    // Wipe and replace with different data.
    await File(p.join(tempDir.path, 'anima_characters.json'))
        .writeAsString('[{"id":"other","name":"Other"}]');
    await File(p.join(tempDir.path, 'anima_lorebooks.json'))
        .writeAsString('{"books":[]}');
    await File(p.join(tempDir.path, 'avatars', 'char_1.png')).delete();
    await File(p.join(tempDir.path, 'avatars', 'extra.png'))
        .writeAsBytes([9, 9]);
    prefs = {'nanogpt_model': 'stale'};

    final summary = await service.restoreBackup(bundle.bytes);
    expect(summary.fileCount, 2);

    expect(
      await File(p.join(tempDir.path, 'anima_characters.json')).readAsString(),
      '[{"id":"c1","name":"Aiko"}]',
    );
    expect(
      await File(p.join(tempDir.path, 'anima_chats.json')).exists(),
      isTrue,
    );
    // File absent from backup should be removed.
    expect(
      await File(p.join(tempDir.path, 'anima_lorebooks.json')).exists(),
      isFalse,
    );
    expect(
      await File(p.join(tempDir.path, 'avatars', 'char_1.png')).readAsBytes(),
      [1, 2, 3, 4],
    );
    expect(
      await File(p.join(tempDir.path, 'avatars', 'extra.png')).exists(),
      isFalse,
    );
    expect(prefs['nanogpt_model'], 'test/model');
    expect(prefs['active_persona_id'], 'persona_1');
  });

  test('API key in settings blob is ignored on restore', () async {
    await seedDocs();
    final bundle = await service.createBackup();
    final map = jsonDecode(utf8.decode(bundle.bytes)) as Map<String, dynamic>;
    final settings = Map<String, dynamic>.from(map['settings'] as Map);
    settings['nanogpt_api_key'] = 'should-never-restore';
    map['settings'] = settings;
    final tampered =
        Uint8List.fromList(utf8.encode(jsonEncode(map)));

    prefs = {};
    await service.restoreBackup(tampered);
    expect(prefs.containsKey('nanogpt_api_key'), isFalse);
  });

  test('wrong format is rejected', () async {
    final bad = Uint8List.fromList(
      utf8.encode(jsonEncode({'format': 'something_else', 'files': {}})),
    );
    expect(
      () => service.inspectBackup(bad),
      throwsA(isA<AppBackupException>()),
    );
  });

  test('path traversal document names are rejected', () async {
    final bad = Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'format': AppBackupService.formatId,
          'createdAt': DateTime.now().toUtc().toIso8601String(),
          'files': {'../secret.json': '{}'},
          'avatars': {},
          'settings': {},
        }),
      ),
    );
    expect(
      () => service.inspectBackup(bad),
      throwsA(isA<AppBackupException>()),
    );
  });

  test('unsafe avatar names are rejected', () async {
    final bad = Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'format': AppBackupService.formatId,
          'createdAt': DateTime.now().toUtc().toIso8601String(),
          'files': {},
          'avatars': {'../evil.png': base64Encode([1])},
          'settings': {},
        }),
      ),
    );
    expect(
      () => service.inspectBackup(bad),
      throwsA(isA<AppBackupException>()),
    );
  });

  test('invalid JSON document content is rejected', () async {
    final bad = Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'format': AppBackupService.formatId,
          'createdAt': DateTime.now().toUtc().toIso8601String(),
          'files': {'anima_characters.json': 'not-json'},
          'avatars': {},
          'settings': {},
        }),
      ),
    );
    expect(
      () => service.inspectBackup(bad),
      throwsA(isA<AppBackupException>()),
    );
  });
}
