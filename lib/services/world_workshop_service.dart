import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/world_workshop.dart';

/// Persists Creation Center workshops on this device.
///
/// File: app documents / `anima_world_workshops.json`
class WorldWorkshopService {
  WorldWorkshopService({
    Future<Directory> Function()? documentsDirectory,
  }) : _documentsDirectory =
            documentsDirectory ?? getApplicationDocumentsDirectory;

  static const _fileName = 'anima_world_workshops.json';

  final Future<Directory> Function() _documentsDirectory;

  Future<File> _file() async {
    final dir = await _documentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  Future<List<WorldWorkshop>> loadWorkshops() async {
    final file = await _file();
    if (!await file.exists()) return <WorldWorkshop>[];

    try {
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return <WorldWorkshop>[];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <WorldWorkshop>[];

      final workshops = decoded
          .whereType<Map>()
          .map((item) => WorldWorkshop.fromJson(Map<String, dynamic>.from(item)))
          .where((w) => w.id.isNotEmpty)
          .toList();
      workshops.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return workshops;
    } catch (_) {
      return <WorldWorkshop>[];
    }
  }

  Future<void> saveWorkshops(List<WorldWorkshop> workshops) async {
    final file = await _file();
    final payload = workshops.map((w) => w.toJson()).toList();
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(payload),
    );
  }

  Future<WorldWorkshop> upsert(WorldWorkshop workshop) async {
    final workshops = List<WorldWorkshop>.from(await loadWorkshops());
    final index = workshops.indexWhere((w) => w.id == workshop.id);
    final next = workshop.copyWith(updatedAt: DateTime.now());
    if (index >= 0) {
      workshops[index] = next;
    } else {
      workshops.insert(0, next);
    }
    await saveWorkshops(workshops);
    return next;
  }

  Future<void> delete(String id) async {
    final workshops = List<WorldWorkshop>.from(await loadWorkshops());
    workshops.removeWhere((w) => w.id == id);
    await saveWorkshops(workshops);
  }

  Future<WorldWorkshop?> getById(String id) async {
    final workshops = await loadWorkshops();
    for (final workshop in workshops) {
      if (workshop.id == id) return workshop;
    }
    return null;
  }
}
