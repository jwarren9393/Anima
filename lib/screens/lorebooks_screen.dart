import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/global_lorebook.dart';
import '../models/lorebook.dart';
import '../services/nanogpt_service.dart';
import '../services/settings_service.dart';
import '../services/world_info_service.dart';
import 'lorebook_edit_screen.dart';

/// Create / import / enable standalone World Info lorebooks (global).
class LorebooksScreen extends StatefulWidget {
  const LorebooksScreen({
    super.key,
    required this.worldInfoService,
    required this.settingsService,
    required this.nanoGptService,
  });

  final WorldInfoService worldInfoService;
  final SettingsService settingsService;
  final NanoGptService nanoGptService;

  @override
  State<LorebooksScreen> createState() => _LorebooksScreenState();
}

class _LorebooksScreenState extends State<LorebooksScreen> {
  List<GlobalLorebook> _books = [];
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final books = await widget.worldInfoService.loadBooks();
    if (!mounted) return;
    setState(() {
      _books = books;
      _loading = false;
    });
  }

  Future<void> _create() async {
    final result = await Navigator.of(context).push<Lorebook>(
      MaterialPageRoute(
        builder: (_) => LorebookEditScreen(
          initial: Lorebook.empty(name: 'New lorebook'),
          settingsService: widget.settingsService,
          nanoGptService: widget.nanoGptService,
        ),
      ),
    );
    if (result == null) return;
    await widget.worldInfoService.upsert(
      GlobalLorebook(
        id: GlobalLorebook.newId(),
        enabled: true,
        book: result,
      ),
    );
    await _load();
  }

  Future<void> _edit(GlobalLorebook existing) async {
    final result = await Navigator.of(context).push<Lorebook>(
      MaterialPageRoute(
        builder: (_) => LorebookEditScreen(
          initial: existing.book,
          characterName: existing.displayName,
          settingsService: widget.settingsService,
          nanoGptService: widget.nanoGptService,
        ),
      ),
    );
    if (result == null) return;
    await widget.worldInfoService.upsert(
      existing.copyWith(book: result),
    );
    await _load();
  }

  Future<void> _toggle(GlobalLorebook book, bool enabled) async {
    await widget.worldInfoService.upsert(book.copyWith(enabled: enabled));
    await _load();
  }

  Future<void> _delete(GlobalLorebook book) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete lorebook?'),
        content: Text(
          'Remove “${book.displayName}” from this device? '
          'Character card lorebooks are not affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await widget.worldInfoService.delete(book.id);
    await _load();
  }

  Future<void> _import() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      var bytes = file.bytes;
      if (bytes == null && file.path != null) {
        bytes = await File(file.path!).readAsBytes();
      }
      if (bytes == null) {
        throw const FormatException('Could not read the selected file.');
      }

      final imported = widget.worldInfoService.importFromBytes(
        bytes,
        fileName: file.name,
      );
      await widget.worldInfoService.upsert(imported);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Imported “${imported.displayName}”')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Import failed: $error')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export(GlobalLorebook book) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final json = widget.worldInfoService.exportJson(book);
      final dir = await getTemporaryDirectory();
      final safeName = book.displayName
          .replaceAll(RegExp(r'[^\w\- ]+'), '')
          .trim()
          .replaceAll(' ', '_');
      final stem = safeName.isEmpty ? 'lorebook' : safeName;
      final path = '${dir.path}/$stem.json';
      final file = File(path);
      await file.writeAsString(json);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(path, mimeType: 'application/json')],
          subject: book.displayName,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: $error')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Global lorebooks'),
        actions: [
          IconButton(
            tooltip: 'Import JSON',
            onPressed: _busy ? null : _import,
            icon: const Icon(Icons.file_upload_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.add),
        label: const Text('New lorebook'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _books.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.public,
                          size: 56,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No global lorebooks yet',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Create one or import a SillyTavern World Info JSON. '
                          'Enabled books apply across chats (plus each '
                          'character’s own lore when they speak).',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 24),
                        FilledButton.icon(
                          onPressed: _create,
                          icon: const Icon(Icons.add),
                          label: const Text('Create lorebook'),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: _busy ? null : _import,
                          icon: const Icon(Icons.file_upload_outlined),
                          label: const Text('Import JSON'),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.only(bottom: 88),
                  itemCount: _books.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final book = _books[index];
                    return ListTile(
                      leading: Icon(
                        book.enabled ? Icons.menu_book : Icons.menu_book_outlined,
                        color: book.enabled
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).disabledColor,
                      ),
                      title: Text(book.displayName),
                      subtitle: Text(
                        '${book.enabledEntryCount}/${book.entryCount} entries on'
                        '${book.enabled ? '' : ' · disabled'}',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Switch(
                            value: book.enabled,
                            onChanged: (on) => _toggle(book, on),
                          ),
                          PopupMenuButton<String>(
                            onSelected: (value) {
                              if (value == 'export') _export(book);
                              if (value == 'delete') _delete(book);
                            },
                            itemBuilder: (context) => const [
                              PopupMenuItem(
                                value: 'export',
                                child: Text('Export JSON'),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child: Text('Delete'),
                              ),
                            ],
                          ),
                        ],
                      ),
                      onTap: () => _edit(book),
                    );
                  },
                ),
    );
  }
}
