import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Per-chat composer text that survives leaving the chat or killing the app.
///
/// Stored separately from [ChatService] so typing a draft does not rewrite the
/// full chat history or bump [ChatSession.updatedAt] on Home.
class ComposerDraftService {
  ComposerDraftService({Future<Directory> Function()? documentsDirectory})
      : _documentsDirectory =
            documentsDirectory ?? getApplicationDocumentsDirectory;

  static const _fileName = 'anima_composer_drafts.json';

  final Future<Directory> Function() _documentsDirectory;

  Future<File> _file() async {
    final dir = await _documentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  Future<Map<String, String>> _readAll() async {
    final file = await _file();
    if (!await file.exists()) return {};
    try {
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return {};
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      final out = <String, String>{};
      for (final entry in decoded.entries) {
        final key = '${entry.key}'.trim();
        if (key.isEmpty) continue;
        out[key] = '${entry.value}';
      }
      return out;
    } catch (_) {
      return {};
    }
  }

  Future<void> _writeAll(Map<String, String> drafts) async {
    final file = await _file();
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(drafts));
  }

  /// Returns the saved draft for [chatId], or empty if none.
  Future<String> loadDraft(String chatId) async {
    final id = chatId.trim();
    if (id.isEmpty) return '';
    final all = await _readAll();
    return all[id] ?? '';
  }

  /// Saves [text] for [chatId]. Empty text removes the draft.
  Future<void> saveDraft(String chatId, String text) async {
    final id = chatId.trim();
    if (id.isEmpty) return;
    final all = await _readAll();
    final trimmed = text; // keep trailing spaces the user typed
    if (trimmed.trim().isEmpty) {
      if (!all.containsKey(id)) return;
      all.remove(id);
    } else {
      all[id] = trimmed;
    }
    await _writeAll(all);
  }

  /// Clears the draft after a successful send (or when the chat is deleted).
  Future<void> clearDraft(String chatId) async {
    await saveDraft(chatId, '');
  }
}
