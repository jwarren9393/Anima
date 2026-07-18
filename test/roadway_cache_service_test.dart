import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:anima/services/roadway_cache_service.dart';

void main() {
  late Directory tempDir;
  late RoadwayCacheService service;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('anima_roadway_cache_');
    service = RoadwayCacheService(
      documentsDirectory: () async => tempDir,
    );
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('save then load returns options for same anchor', () async {
    await service.saveOptions(
      'chat_1',
      options: const ['*Look around*', 'Ask a question'],
      anchorMessageId: 'msg_a',
    );

    final loaded = await service.loadOptions(
      'chat_1',
      anchorMessageId: 'msg_a',
    );
    expect(loaded, ['*Look around*', 'Ask a question']);
  });

  test('load returns null and drops entry when scene moved on', () async {
    await service.saveOptions(
      'chat_1',
      options: const ['Old path'],
      anchorMessageId: 'msg_old',
    );

    final loaded = await service.loadOptions(
      'chat_1',
      anchorMessageId: 'msg_new',
    );
    expect(loaded, isNull);

    // Stale entry should be gone — saving again for the old anchor fails soft.
    final again = await service.loadOptions(
      'chat_1',
      anchorMessageId: 'msg_old',
    );
    expect(again, isNull);
  });

  test('clearOptions removes cached paths', () async {
    await service.saveOptions(
      'chat_1',
      options: const ['Keep me'],
      anchorMessageId: 'msg_a',
    );
    await service.clearOptions('chat_1');
    final loaded = await service.loadOptions(
      'chat_1',
      anchorMessageId: 'msg_a',
    );
    expect(loaded, isNull);
  });

  test('empty options clear the entry', () async {
    await service.saveOptions(
      'chat_1',
      options: const ['One'],
      anchorMessageId: 'msg_a',
    );
    await service.saveOptions(
      'chat_1',
      options: const [],
      anchorMessageId: 'msg_a',
    );
    final loaded = await service.loadOptions(
      'chat_1',
      anchorMessageId: 'msg_a',
    );
    expect(loaded, isNull);
  });
}
