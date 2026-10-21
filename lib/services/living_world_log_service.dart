import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/turn_resolution.dart';
import 'app_paths.dart';
import 'living_world_service.dart';

/// Append-only World log — what the engine applied each turn (Phase 6).
class LivingWorldLogService {
  LivingWorldLogService({
    Future<Directory> Function()? documentsDirectory,
    this.maxEntries = 50,
  }) : _documentsDirectory = documentsDirectory ?? appDocumentsDirectory;

  final Future<Directory> Function() _documentsDirectory;
  final int maxEntries;

  Future<File> _logFile(String worldId) async {
    final docs = await _documentsDirectory();
    final dir = Directory(p.join(docs.path, LivingWorldService.folderName));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final safe = worldId.trim().replaceAll(RegExp(r'[^\w.\-]+'), '_');
    return File(p.join(dir.path, '$safe.log.json'));
  }

  /// Newest first.
  Future<List<TurnResolution>> listEntries(String worldId) async {
    final raw = await _read(worldId);
    return [
      for (final item in raw.reversed)
        TurnResolution.fromJson(item),
    ];
  }

  Future<void> append(TurnResolution resolution) async {
    final id = resolution.worldId.trim();
    if (id.isEmpty) return;
    // Skip totally empty no-op noise (keeps the log readable).
    if (resolution.isEmpty) return;

    final file = await _logFile(id);
    final stack = await _read(id);
    stack.add(resolution.toJson());
    while (stack.length > maxEntries) {
      stack.removeAt(0);
    }
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert({'entries': stack}),
      flush: true,
    );
  }

  Future<void> clear(String worldId) async {
    final file = await _logFile(worldId);
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<List<Map<String, dynamic>>> _read(String worldId) async {
    final file = await _logFile(worldId);
    if (!await file.exists()) return [];
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return [];
      final list = decoded['entries'];
      if (list is! List) return [];
      return [
        for (final item in list)
          if (item is Map) Map<String, dynamic>.from(item),
      ];
    } catch (_) {
      return [];
    }
  }
}
