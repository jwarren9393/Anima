import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:anima/services/avatar_service.dart';

void main() {
  late Directory tempDir;
  late AvatarService service;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('anima_avatar_test_');
    service = AvatarService(documentsDirectory: () async => tempDir);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('saveHistoryBytes keeps multiple files for one stem', () async {
    final first = await service.saveHistoryBytes(
      stem: 'char_abc',
      bytes: Uint8List.fromList([1, 2, 3]),
    );
    final second = await service.saveHistoryBytes(
      stem: 'char_abc',
      bytes: Uint8List.fromList([4, 5, 6]),
    );

    expect(first, isNot(equals(second)));
    final history = await service.listHistoryForStem('char_abc');
    expect(history.length, 2);
    expect(history.map((e) => e.fileName), contains(first));
    expect(history.map((e) => e.fileName), contains(second));
  });

  test('listHistoryForStem includes legacy single-name files', () async {
    await service.saveBytes(
      stem: 'char_legacy',
      bytes: Uint8List.fromList([9]),
    );
    final history = await service.listHistoryForStem('char_legacy');
    expect(history.length, 1);
    expect(history.first.fileName, 'char_legacy.png');
  });

  test('deleteAllForStem removes every portrait for id', () async {
    await service.saveHistoryBytes(
      stem: 'persona_x',
      bytes: Uint8List.fromList([1]),
    );
    await service.saveHistoryBytes(
      stem: 'persona_x',
      bytes: Uint8List.fromList([2]),
    );
    await service.deleteAllForStem('persona_x');
    expect(await service.listHistoryForStem('persona_x'), isEmpty);
  });

  test('readBytes round-trips saved file', () async {
    final bytes = Uint8List.fromList([7, 8, 9]);
    final name = await service.saveHistoryBytes(stem: 'p1', bytes: bytes);
    final loaded = await service.readBytes(name);
    expect(loaded, bytes);
    final path = await service.resolvePath(name);
    expect(path, isNotNull);
    expect(p.dirname(path!), p.join(tempDir.path, 'avatars'));
  });
}
