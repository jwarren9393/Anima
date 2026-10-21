import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/living_world.dart';
import 'app_paths.dart';
import 'living_world_service.dart';

/// Last-N notebook snapshots so the owner can undo an after-turn apply pack.
class LivingWorldUndoService {
  LivingWorldUndoService({
    Future<Directory> Function()? documentsDirectory,
    this.maxSnapshots = 5,
  }) : _documentsDirectory = documentsDirectory ?? appDocumentsDirectory;

  final Future<Directory> Function() _documentsDirectory;
  final int maxSnapshots;

  Future<File> _undoFile(String worldId) async {
    final docs = await _documentsDirectory();
    final dir = Directory(p.join(docs.path, LivingWorldService.folderName));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final safe = worldId.trim().replaceAll(RegExp(r'[^\w.\-]+'), '_');
    return File(p.join(dir.path, '$safe.undo.json'));
  }

  /// Push [before] (state prior to applying a pack) onto the undo stack.
  Future<void> pushSnapshot(LivingWorld before) async {
    final id = before.id.trim();
    if (id.isEmpty) return;
    final file = await _undoFile(id);
    final stack = await _readStack(file);
    stack.add(before.toJson());
    while (stack.length > maxSnapshots) {
      stack.removeAt(0);
    }
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert({'snapshots': stack}),
      flush: true,
    );
  }

  Future<bool> canUndo(String worldId) async {
    final stack = await _readStack(await _undoFile(worldId));
    return stack.isNotEmpty;
  }

  /// Restore the newest snapshot and save it as the live notebook.
  Future<LivingWorld?> undoLast({
    required LivingWorldService worldService,
    required String worldId,
  }) async {
    final file = await _undoFile(worldId);
    final stack = await _readStack(file);
    if (stack.isEmpty) return null;
    final raw = stack.removeLast();
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert({'snapshots': stack}),
      flush: true,
    );
    final restored = LivingWorld.fromJson(Map<String, dynamic>.from(raw));
    return worldService.save(restored);
  }

  Future<List<Map<String, dynamic>>> _readStack(File file) async {
    if (!await file.exists()) return [];
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return [];
      final list = decoded['snapshots'];
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
