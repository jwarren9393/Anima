import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../models/living_world.dart';
import 'app_paths.dart';

/// Load / save Living World notebooks under the Anima library `worlds/` folder.
///
/// Each world is `worlds/<id>.json`. Classic Anima stays unchanged when no chat
/// binds a [ChatSession.worldId].
class LivingWorldService {
  LivingWorldService({
    Future<Directory> Function()? documentsDirectory,
  }) : _documentsDirectory = documentsDirectory ?? appDocumentsDirectory;

  static const folderName = 'worlds';

  final Future<Directory> Function() _documentsDirectory;

  Future<Directory> _worldsDir() async {
    final docs = await _documentsDirectory();
    final dir = Directory(p.join(docs.path, folderName));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<File> _fileFor(String id) async {
    final safe = _safeFileStem(id);
    final dir = await _worldsDir();
    return File(p.join(dir.path, '$safe.json'));
  }

  /// List worlds without loading every full notebook into memory twice.
  Future<List<LivingWorldSummary>> listSummaries() async {
    final dir = await _worldsDir();
    if (!await dir.exists()) return const [];

    final out = <LivingWorldSummary>[];
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File) continue;
      if (!entity.path.toLowerCase().endsWith('.json')) continue;
      try {
        final world = await loadFromFile(entity);
        if (world == null) continue;
        out.add(
          LivingWorldSummary(
            id: world.id,
            title: world.title,
            personCount: world.people.length,
            placeCount: world.places.length,
          ),
        );
      } catch (_) {
        // Skip unreadable files.
      }
    }
    out.sort(
      (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
    );
    return out;
  }

  Future<LivingWorld?> getById(String id) async {
    final trimmed = id.trim();
    if (trimmed.isEmpty) return null;
    final file = await _fileFor(trimmed);
    return loadFromFile(file);
  }

  Future<LivingWorld?> loadFromFile(File file) async {
    if (!await file.exists()) return null;
    try {
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return null;
      return parseWorldJson(raw);
    } catch (_) {
      return null;
    }
  }

  /// Parse a world from JSON text (file or import). Validates schema.
  LivingWorld parseWorldJson(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException('Living World JSON must be an object.');
    }
    return LivingWorld.fromJson(Map<String, dynamic>.from(decoded));
  }

  Future<LivingWorld> save(LivingWorld world) async {
    final cleaned = world.validated();
    if (cleaned.id.trim().isEmpty) {
      throw const FormatException('Cannot save a world without an id.');
    }
    final file = await _fileFor(cleaned.id);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(cleaned.toJson()),
      flush: true,
    );
    return cleaned;
  }

  Future<LivingWorld> createEmpty({String title = 'New world'}) async {
    final world = LivingWorld.empty(title: title);
    return save(world);
  }

  /// Import bytes (UTF-8 JSON). Keeps the file's id when present and unique;
  /// otherwise assigns a new id.
  Future<LivingWorld> importFromBytes(
    List<int> bytes, {
    String? fileName,
  }) async {
    final raw = utf8.decode(bytes, allowMalformed: true);
    var world = parseWorldJson(raw);
    final existing = await getById(world.id);
    if (existing != null) {
      world = world.copyWith(id: LivingWorld.newId());
    }
    if (world.title.trim().isEmpty && fileName != null) {
      final stem = p.basenameWithoutExtension(fileName).trim();
      if (stem.isNotEmpty) {
        world = world.copyWith(title: stem);
      }
    }
    return save(world);
  }

  Future<void> delete(String id) async {
    final file = await _fileFor(id);
    if (await file.exists()) {
      await file.delete();
    }
  }

  /// UTF-8 JSON bytes for export / share (pretty-printed, validated).
  Uint8List exportBytes(LivingWorld world) {
    final cleaned = world.validated();
    return Uint8List.fromList(
      utf8.encode(
        const JsonEncoder.withIndent('  ').convert(cleaned.toJson()),
      ),
    );
  }

  String exportFileName(LivingWorld world) {
    final stem = _safeFileStem(world.title.trim().isEmpty ? world.id : world.title);
    return '$stem.world.json';
  }

  static String _safeFileStem(String id) {
    final cleaned = id.trim().replaceAll(RegExp(r'[^\w.\-]+'), '_');
    if (cleaned.isEmpty) return 'world';
    return cleaned;
  }
}
