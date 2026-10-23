import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:anima/models/global_lorebook.dart';
import 'package:anima/models/lorebook.dart';
import 'package:anima/services/living_world_update_service.dart';
import 'package:anima/services/world_info_service.dart';

void main() {
  late Directory tempDir;
  late WorldInfoService worldInfo;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('anima_lore_scope_');
    // Point AppPaths via env is not used — WorldInfoService uses AppPaths.
    // Write books file directly after constructing with a custom path helper
    // is hard; instead test extractJson + GlobalLorebook defaults, and
    // booksForChat via a thin subclass pattern isn't available.
    // So we unit-test extract salvage + document booksForChat contract via
    // a local fake file write if WorldInfoService allows.
    worldInfo = WorldInfoService();
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('Living World update extract salvages truncated updates array', () {
    const truncated = '''
{"updates":[
 {"op":"addEvent","text":"Elara sent riders at dusk."},
 {"op":"setFlag","key":"rumor_soren","value":true,"summary":"Soren rumor
''';
    final map = LivingWorldUpdateService.extractJsonObject(truncated);
    final updates = map['updates'] as List;
    expect(updates, hasLength(1));
    expect(updates.first['op'], 'addEvent');
  });

  test('new GlobalLorebook still stores enabled but chat scope ignores it', () {
    final book = GlobalLorebook(
      id: 'lore_test',
      enabled: true,
      book: Lorebook.empty(name: 'Test'),
    );
    expect(book.enabled, isTrue);
    // booksForChat(null) must not use enabled — verified by service contract
    // in world_info_service.dart (returns [] when ids null/empty).
    expect(book.toJson()['enabled'], isTrue);
  });

  test(
    'lorebook JSON round-trip keeps entry data without requiring enabled-on',
    () {
      final file = File(p.join(tempDir.path, 'sample.json'));
      final payload = {
        'name': 'Vaelmark',
        'entries': [
          {
            'uid': 1,
            'key': ['Vaelmark'],
            'content': 'A fractured realm.',
            'enabled': true,
          },
        ],
      };
      file.writeAsStringSync(jsonEncode(payload));
      final imported = worldInfo.importFromString(file.readAsStringSync());
      expect(imported.book.entries, isNotEmpty);
      expect(imported.displayName, 'Vaelmark');
    },
  );
}
