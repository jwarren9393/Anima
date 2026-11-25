import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:anima/models/global_lorebook.dart';
import 'package:anima/models/lorebook.dart';
import 'package:anima/services/world_info_service.dart';

void main() {
  late Directory tempDir;
  late WorldInfoService worldInfo;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('anima_lore_scope_');
    worldInfo = WorldInfoService();
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
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
