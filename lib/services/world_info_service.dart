import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/global_lorebook.dart';
import '../models/lorebook.dart';

/// Saves standalone (global) World Info lorebooks on this device.
///
/// File: app documents / `anima_lorebooks.json`
/// These apply across chats when enabled — separate from per-character books.
class WorldInfoService {
  WorldInfoService({
    Future<Directory> Function()? documentsDirectory,
  }) : _documentsDirectory =
            documentsDirectory ?? getApplicationDocumentsDirectory;

  static const _fileName = 'anima_lorebooks.json';

  final Future<Directory> Function() _documentsDirectory;

  Future<File> _file() async {
    final dir = await _documentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  /// All global lorebooks (enabled and disabled).
  Future<List<GlobalLorebook>> loadBooks() async {
    final file = await _file();
    if (!await file.exists()) return <GlobalLorebook>[];

    try {
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return <GlobalLorebook>[];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <GlobalLorebook>[];

      return decoded
          .whereType<Map>()
          .map((item) => GlobalLorebook.fromJson(Map<String, dynamic>.from(item)))
          .where((b) => b.id.isNotEmpty)
          .toList();
    } catch (_) {
      return <GlobalLorebook>[];
    }
  }

  Future<void> saveBooks(List<GlobalLorebook> books) async {
    final file = await _file();
    final payload = books.map((b) => b.toJson()).toList();
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(payload),
    );
  }

  Future<GlobalLorebook> upsert(GlobalLorebook book) async {
    final books = List<GlobalLorebook>.from(await loadBooks());
    final index = books.indexWhere((b) => b.id == book.id);
    if (index >= 0) {
      books[index] = book;
    } else {
      books.add(book);
    }
    await saveBooks(books);
    return book;
  }

  Future<void> delete(String id) async {
    final books = List<GlobalLorebook>.from(await loadBooks());
    books.removeWhere((b) => b.id == id);
    await saveBooks(books);
  }

  Future<GlobalLorebook?> getById(String id) async {
    final books = await loadBooks();
    for (final book in books) {
      if (book.id == id) return book;
    }
    return null;
  }

  /// Books that should inject into prompts right now.
  ///
  /// When [chatLorebookIds] is null, every enabled global book is used.
  /// When set (including empty), only those ids are used (if they still exist).
  Future<List<Lorebook>> booksForChat({List<String>? chatLorebookIds}) async {
    final all = await loadBooks();
    final Iterable<GlobalLorebook> selected;
    if (chatLorebookIds == null) {
      selected = all.where((b) => b.enabled);
    } else {
      final wanted = chatLorebookIds.toSet();
      selected = all.where((b) => wanted.contains(b.id));
    }
    return [
      for (final g in selected)
        if (g.book.entries.isNotEmpty) g.book,
    ];
  }

  /// Import SillyTavern / Anima lorebook JSON bytes.
  GlobalLorebook importFromBytes(List<int> bytes, {String? fileName}) {
    final raw = utf8.decode(bytes, allowMalformed: true);
    return importFromString(raw, fileName: fileName);
  }

  GlobalLorebook importFromString(String raw, {String? fileName}) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException(
        'Lorebook JSON must be an object (SillyTavern World Info export).',
      );
    }
    final map = Map<String, dynamic>.from(decoded);
    final fallback = _nameFromFile(fileName);
    final book = Lorebook.parseImport(map, fallbackName: fallback);
    if (book.entries.isEmpty && book.name.isEmpty) {
      throw const FormatException('That file has no lorebook entries.');
    }
    return GlobalLorebook(
      id: GlobalLorebook.newId(),
      enabled: true,
      book: book.name.trim().isEmpty && fallback.isNotEmpty
          ? book.copyWith(name: fallback)
          : book,
    );
  }

  /// Export a book as SillyTavern-friendly character_book-shaped JSON.
  String exportJson(GlobalLorebook book, {bool pretty = true}) {
    final payload = book.book.toJson();
    if (pretty) {
      return const JsonEncoder.withIndent('  ').convert(payload);
    }
    return jsonEncode(payload);
  }

  String _nameFromFile(String? fileName) {
    if (fileName == null || fileName.trim().isEmpty) return '';
    var name = fileName.trim();
    final slash = name.lastIndexOf(RegExp(r'[/\\]'));
    if (slash >= 0) name = name.substring(slash + 1);
    final dot = name.lastIndexOf('.');
    if (dot > 0) name = name.substring(0, dot);
    return name.trim();
  }
}
