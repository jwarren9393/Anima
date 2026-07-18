import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Cached Path options for one chat, tied to the message they were generated for.
class RoadwayCacheEntry {
  const RoadwayCacheEntry({
    required this.options,
    required this.anchorMessageId,
  });

  final List<String> options;

  /// Id of the newest chat message when these paths were generated.
  /// If the chat has moved on (new last message), the cache is stale.
  final String anchorMessageId;

  Map<String, dynamic> toJson() => {
        'options': options,
        'anchorMessageId': anchorMessageId,
      };

  factory RoadwayCacheEntry.fromJson(Map<String, dynamic> json) {
    final rawOptions = json['options'];
    final options = <String>[];
    if (rawOptions is List) {
      for (final item in rawOptions) {
        final text = '$item'.trim();
        if (text.isNotEmpty) options.add(text);
      }
    }
    return RoadwayCacheEntry(
      options: options,
      anchorMessageId: '${json['anchorMessageId'] ?? ''}'.trim(),
    );
  }
}

/// Per-chat Paths / Roadway options that survive closing the Paths sheet.
///
/// Stored separately from [ChatService] so regenerating paths does not rewrite
/// the full chat history or bump Home’s last-updated time.
class RoadwayCacheService {
  RoadwayCacheService({Future<Directory> Function()? documentsDirectory})
      : _documentsDirectory =
            documentsDirectory ?? getApplicationDocumentsDirectory;

  static const _fileName = 'anima_roadway_cache.json';

  final Future<Directory> Function() _documentsDirectory;

  Future<File> _file() async {
    final dir = await _documentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  Future<Map<String, RoadwayCacheEntry>> _readAll() async {
    final file = await _file();
    if (!await file.exists()) return {};
    try {
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return {};
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      final out = <String, RoadwayCacheEntry>{};
      for (final entry in decoded.entries) {
        final key = '${entry.key}'.trim();
        if (key.isEmpty) continue;
        final value = entry.value;
        if (value is! Map) continue;
        final parsed =
            RoadwayCacheEntry.fromJson(Map<String, dynamic>.from(value));
        if (parsed.options.isEmpty || parsed.anchorMessageId.isEmpty) continue;
        out[key] = parsed;
      }
      return out;
    } catch (_) {
      return {};
    }
  }

  Future<void> _writeAll(Map<String, RoadwayCacheEntry> entries) async {
    final file = await _file();
    final encoded = <String, dynamic>{};
    for (final e in entries.entries) {
      encoded[e.key] = e.value.toJson();
    }
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(encoded),
    );
  }

  /// Returns saved paths for [chatId] when they still match [anchorMessageId].
  ///
  /// Pass the chat’s current last message id. Mismatched or empty caches return
  /// null (and drop the stale entry so it does not linger).
  Future<List<String>?> loadOptions(
    String chatId, {
    required String anchorMessageId,
  }) async {
    final id = chatId.trim();
    final anchor = anchorMessageId.trim();
    if (id.isEmpty || anchor.isEmpty) return null;

    final all = await _readAll();
    final entry = all[id];
    if (entry == null) return null;

    if (entry.anchorMessageId != anchor || entry.options.isEmpty) {
      all.remove(id);
      await _writeAll(all);
      return null;
    }
    return List<String>.from(entry.options);
  }

  /// Saves [options] for [chatId], anchored to the newest message id.
  Future<void> saveOptions(
    String chatId, {
    required List<String> options,
    required String anchorMessageId,
  }) async {
    final id = chatId.trim();
    final anchor = anchorMessageId.trim();
    if (id.isEmpty || anchor.isEmpty) return;

    final cleaned = options
        .map((o) => o.trim())
        .where((o) => o.isNotEmpty)
        .toList(growable: false);
    final all = await _readAll();
    if (cleaned.isEmpty) {
      if (!all.containsKey(id)) return;
      all.remove(id);
    } else {
      all[id] = RoadwayCacheEntry(
        options: cleaned,
        anchorMessageId: anchor,
      );
    }
    await _writeAll(all);
  }

  /// Clears cached paths (Clear button or chat delete).
  Future<void> clearOptions(String chatId) async {
    final id = chatId.trim();
    if (id.isEmpty) return;
    final all = await _readAll();
    if (!all.containsKey(id)) return;
    all.remove(id);
    await _writeAll(all);
  }
}
