import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/saved_opening_scene.dart';
import '../models/world_workshop.dart';

/// Saved opening scenes for reuse when starting chats outside Creation Center.
class OpeningSceneService {
  OpeningSceneService({
    Future<Directory> Function()? documentsDirectory,
  }) : _documentsDirectory =
            documentsDirectory ?? getApplicationDocumentsDirectory;

  static const fileName = 'anima_opening_scenes.json';

  final Future<Directory> Function() _documentsDirectory;

  Future<File> _file() async {
    final dir = await _documentsDirectory();
    return File('${dir.path}/$fileName');
  }

  Future<List<SavedOpeningScene>> loadScenes() async {
    final file = await _file();
    if (!await file.exists()) return <SavedOpeningScene>[];

    try {
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return <SavedOpeningScene>[];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <SavedOpeningScene>[];

      final scenes = decoded
          .whereType<Map>()
          .map(
            (item) =>
                SavedOpeningScene.fromJson(Map<String, dynamic>.from(item)),
          )
          .where((s) => s.id.isNotEmpty && s.text.trim().isNotEmpty)
          .toList();
      scenes.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return scenes;
    } catch (_) {
      return <SavedOpeningScene>[];
    }
  }

  Future<void> saveScenes(List<SavedOpeningScene> scenes) async {
    final file = await _file();
    final payload = scenes.map((s) => s.toJson()).toList();
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(payload),
    );
  }

  Future<SavedOpeningScene> upsert(SavedOpeningScene scene) async {
    final scenes = List<SavedOpeningScene>.from(await loadScenes());
    final next = scene.copyWith(updatedAt: DateTime.now());
    final index = scenes.indexWhere((s) => s.id == scene.id);
    if (index >= 0) {
      scenes[index] = next;
    } else {
      scenes.insert(0, next);
    }
    await saveScenes(scenes);
    return next;
  }

  Future<void> delete(String id) async {
    final scenes = List<SavedOpeningScene>.from(await loadScenes());
    scenes.removeWhere((s) => s.id == id);
    await saveScenes(scenes);
  }

  /// Keep one library entry per workshop when Creation Center saves a scene.
  Future<void> syncFromWorkshop({
    required String workshopId,
    required String workshopTitle,
    required String openingScene,
  }) async {
    final text = openingScene.trim();
    final scenes = List<SavedOpeningScene>.from(await loadScenes());
    final index = scenes.indexWhere((s) => s.workshopId == workshopId);

    if (text.isEmpty) {
      if (index >= 0) {
        scenes.removeAt(index);
        await saveScenes(scenes);
      }
      return;
    }

    final title = workshopTitle.trim().isEmpty
        ? 'Workshop opening'
        : workshopTitle.trim();
    final entry = SavedOpeningScene(
      id: index >= 0 ? scenes[index].id : SavedOpeningScene.newId(),
      title: title,
      text: text,
      workshopId: workshopId,
      updatedAt: DateTime.now(),
    );
    if (index >= 0) {
      scenes[index] = entry;
    } else {
      scenes.insert(0, entry);
    }
    await saveScenes(scenes);
  }

  /// Pull in workshop scenes that are not in the library yet (older saves).
  Future<void> importMissingFromWorkshops(List<WorldWorkshop> workshops) async {
    for (final workshop in workshops) {
      if (workshop.openingScene.trim().isEmpty) continue;
      final scenes = await loadScenes();
      final exists = scenes.any((s) => s.workshopId == workshop.id);
      if (exists) continue;
      await syncFromWorkshop(
        workshopId: workshop.id,
        workshopTitle: workshop.title,
        openingScene: workshop.openingScene,
      );
    }
  }
}
