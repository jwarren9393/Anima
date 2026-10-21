import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'app_paths.dart';
import 'living_world_service.dart';
import 'living_world_update_service.dart';

/// Disk-backed queue of Living World ops waiting for owner review (Phase 11).
///
/// Used so auto-safe play can save safe facts without a modal, while
/// relationship (risky) ops accumulate until "Review pending…".
class LivingWorldPendingService {
  LivingWorldPendingService({
    Future<Directory> Function()? documentsDirectory,
    this.maxPending = 24,
  }) : _documentsDirectory = documentsDirectory ?? appDocumentsDirectory;

  final Future<Directory> Function() _documentsDirectory;
  final int maxPending;

  Future<File> _pendingFile(String worldId) async {
    final docs = await _documentsDirectory();
    final dir = Directory(p.join(docs.path, LivingWorldService.folderName));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final safe = worldId.trim().replaceAll(RegExp(r'[^\w.\-]+'), '_');
    return File(p.join(dir.path, '$safe.pending.json'));
  }

  Future<List<LivingWorldCanonUpdate>> list(String worldId) async {
    final raw = await _read(worldId);
    return [
      for (final item in raw) LivingWorldCanonUpdate.fromJson(item),
    ];
  }

  Future<int> count(String worldId) async {
    final raw = await _read(worldId);
    return raw.length;
  }

  /// Append [ops], skipping duplicates by [LivingWorldCanonUpdate.pendingKey].
  Future<List<LivingWorldCanonUpdate>> enqueue(
    String worldId,
    List<LivingWorldCanonUpdate> ops,
  ) async {
    if (worldId.trim().isEmpty || ops.isEmpty) {
      return list(worldId);
    }
    final existing = await list(worldId);
    final keys = {for (final u in existing) u.pendingKey};
    final next = List<LivingWorldCanonUpdate>.from(existing);
    for (final op in ops) {
      if (keys.contains(op.pendingKey)) continue;
      keys.add(op.pendingKey);
      next.add(op);
    }
    while (next.length > maxPending) {
      next.removeAt(0);
    }
    await _write(worldId, next);
    return next;
  }

  /// Replace the whole queue (e.g. after a partial review apply).
  Future<void> replace(
    String worldId,
    List<LivingWorldCanonUpdate> ops,
  ) async {
    await _write(worldId, ops);
  }

  /// Drop ops whose [pendingKey] is in [applied].
  Future<List<LivingWorldCanonUpdate>> removeApplied(
    String worldId,
    List<LivingWorldCanonUpdate> applied,
  ) async {
    if (applied.isEmpty) return list(worldId);
    final drop = {for (final u in applied) u.pendingKey};
    final kept = [
      for (final u in await list(worldId))
        if (!drop.contains(u.pendingKey)) u,
    ];
    await _write(worldId, kept);
    return kept;
  }

  Future<void> clear(String worldId) async {
    final file = await _pendingFile(worldId);
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<void> _write(
    String worldId,
    List<LivingWorldCanonUpdate> ops,
  ) async {
    final id = worldId.trim();
    if (id.isEmpty) return;
    final file = await _pendingFile(id);
    if (ops.isEmpty) {
      if (await file.exists()) await file.delete();
      return;
    }
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'updates': [for (final u in ops) u.toJson()],
      }),
      flush: true,
    );
  }

  Future<List<Map<String, dynamic>>> _read(String worldId) async {
    final file = await _pendingFile(worldId);
    if (!await file.exists()) return [];
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return [];
      final list = decoded['updates'];
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
