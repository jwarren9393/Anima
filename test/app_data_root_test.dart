import 'dart:io';

import 'package:anima/services/app_data_root.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temp;
  late Directory support;
  late Directory legacy;
  late Directory homeDocsParent;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('anima_data_root_');
    support = Directory(p.join(temp.path, 'support'));
    legacy = Directory(p.join(temp.path, 'legacy'));
    homeDocsParent = Directory(p.join(temp.path, 'home'));
    await support.create(recursive: true);
    await legacy.create(recursive: true);
    await homeDocsParent.create(recursive: true);
    AppDataRoot.instance = null;
  });

  tearDown(() async {
    AppDataRoot.instance = null;
    if (await temp.exists()) {
      await temp.delete(recursive: true);
    }
  });

  AppDataRoot buildRoot({
    String? exeDir,
    bool isDesktop = true,
    bool isAndroid = false,
  }) {
    return AppDataRoot(
      supportDirectory: () async => support,
      legacyDocumentsDirectory: () async => legacy,
      executableDirectory: exeDir,
      homeDirectory: homeDocsParent.path,
      androidPublicDocumentsPath: p.join(temp.path, 'sdcard', 'Documents'),
      isAndroid: isAndroid,
      isDesktop: isDesktop,
      requestStorageAccess: () async => true,
      hasStorageAccess: () async => true,
      pickDirectoryPath: () async => null,
    );
  }

  test('default public path is Documents/Anima', () async {
    final root = buildRoot();
    expect(
      await root.defaultPublicPath(),
      p.join(homeDocsParent.path, 'Documents', 'Anima'),
    );
  });

  test('adopts an existing public library without a pointer', () async {
    final root = buildRoot();
    final public = Directory(await root.defaultPublicPath());
    await public.create(recursive: true);
    await File(p.join(public.path, 'anima_characters.json'))
        .writeAsString('[]');

    expect(await root.load(), isTrue);
    expect(root.path, public.path);
  });

  test('setPath copies legacy files and writes a pointer', () async {
    await File(p.join(legacy.path, 'anima_chats.json')).writeAsString('{"ok":1}');
    final avatars = Directory(p.join(legacy.path, 'avatars'));
    await avatars.create();
    await File(p.join(avatars.path, 'a.png')).writeAsBytes([1, 2, 3]);

    final root = buildRoot();
    final dest = Directory(p.join(temp.path, 'picked'));
    await root.setPath(dest.path, migrateLegacy: true);

    expect(root.isConfigured, isTrue);
    expect(
      await File(p.join(dest.path, 'anima_chats.json')).readAsString(),
      '{"ok":1}',
    );
    expect(await File(p.join(dest.path, 'avatars', 'a.png')).exists(), isTrue);
    expect(await File(p.join(dest.path, 'README.txt')).exists(), isTrue);
    expect(
      await File(p.join(support.path, AppDataRoot.pointerFileName)).exists(),
      isTrue,
    );
  });

  test('changePath copies the current library to the new folder', () async {
    final root = buildRoot();
    final first = Directory(p.join(temp.path, 'first'));
    await root.setPath(first.path, migrateLegacy: false);
    await File(p.join(first.path, 'anima_personas.json')).writeAsString('[]');

    final second = Directory(p.join(temp.path, 'second'));
    await root.changePath(second.path);

    expect(root.path, second.path);
    expect(
      await File(p.join(second.path, 'anima_personas.json')).readAsString(),
      '[]',
    );
  });

  test('load restores the saved pointer', () async {
    final root = buildRoot();
    final dest = Directory(p.join(temp.path, 'saved'));
    await root.setPath(dest.path, migrateLegacy: false);

    final again = buildRoot();
    expect(await again.load(), isTrue);
    expect(again.path, dest.path);
  });
}
