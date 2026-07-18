import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/global_lorebook.dart';
import '../models/world_workshop.dart';
import '../services/character_service.dart';
import '../services/nanogpt_service.dart';
import '../services/persona_service.dart';
import '../services/settings_service.dart';
import '../services/world_info_service.dart';
import '../services/world_workshop_service.dart';
import 'world_workshop_chat_screen.dart';

/// Settings → Creation Center: list of world-building workshop chats.
class WorldWorkshopListScreen extends StatefulWidget {
  const WorldWorkshopListScreen({
    super.key,
    required this.workshopService,
    required this.worldInfoService,
    required this.characterService,
    required this.personaService,
    required this.settingsService,
    required this.nanoGptService,
  });

  final WorldWorkshopService workshopService;
  final WorldInfoService worldInfoService;
  final CharacterService characterService;
  final PersonaService personaService;
  final SettingsService settingsService;
  final NanoGptService nanoGptService;

  @override
  State<WorldWorkshopListScreen> createState() =>
      _WorldWorkshopListScreenState();
}

class _WorldWorkshopListScreenState extends State<WorldWorkshopListScreen> {
  List<WorldWorkshop> _workshops = [];
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final workshops = await widget.workshopService.loadWorkshops();
    if (!mounted) return;
    setState(() {
      _workshops = workshops;
      _loading = false;
    });
  }

  Future<void> _open(WorldWorkshop workshop) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WorldWorkshopChatScreen(
          workshop: workshop,
          workshopService: widget.workshopService,
          worldInfoService: widget.worldInfoService,
          characterService: widget.characterService,
          personaService: widget.personaService,
          settingsService: widget.settingsService,
          nanoGptService: widget.nanoGptService,
        ),
      ),
    );
    await _load();
  }

  Future<void> _create() async {
    final workshop = await widget.workshopService.upsert(WorldWorkshop.empty());
    if (!mounted) return;
    await _open(workshop);
  }

  Future<void> _linkLorebook(GlobalLorebook book) async {
    for (final workshop in _workshops) {
      if (workshop.exportedLorebookId == book.id) {
        await _open(workshop);
        return;
      }
    }

    final workshop = await widget.workshopService.upsert(
      WorldWorkshop.empty(
        title: book.displayName,
      ).copyWith(exportedLorebookId: book.id),
    );
    if (!mounted) return;
    await _open(workshop);
  }

  Future<void> _chooseExistingLorebook() async {
    final books = await widget.worldInfoService.loadBooks();
    if (!mounted) return;
    if (books.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No World Info lorebooks yet. Import a JSON file instead.',
          ),
        ),
      );
      return;
    }

    final selected = await showModalBottomSheet<GlobalLorebook>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        final maxHeight = MediaQuery.sizeOf(context).height * 0.7;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                  child: Text(
                    'Choose from World Info',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: books.length,
                    itemBuilder: (context, index) {
                      final book = books[index];
                      return ListTile(
                        leading: Icon(
                          book.enabled
                              ? Icons.menu_book
                              : Icons.menu_book_outlined,
                        ),
                        title: Text(book.displayName),
                        subtitle: Text(
                          '${book.entryCount} entries'
                          '${book.enabled ? '' : ' · disabled in World Info'}',
                        ),
                        onTap: () => Navigator.pop(context, book),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (selected == null || !mounted) return;
    await _linkLorebook(selected);
  }

  Future<void> _importLorebookFile() async {
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

      final parsed = widget.worldInfoService.importFromBytes(
        bytes,
        fileName: file.name,
      );
      // Keep an imported workshop source from affecting chats until the owner
      // explicitly enables it in World Info.
      final imported = parsed.copyWith(enabled: false);
      await widget.worldInfoService.upsert(imported);
      await _load();
      if (!mounted) return;
      await _linkLorebook(imported);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Import failed: $error')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showImportOptions() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.menu_book),
              title: const Text('Choose from World Info'),
              subtitle: const Text(
                'Use a lorebook already created or imported in Anima',
              ),
              onTap: () => Navigator.pop(context, 'existing'),
            ),
            ListTile(
              leading: const Icon(Icons.file_upload_outlined),
              title: const Text('Import JSON file'),
              subtitle: const Text(
                'Import a SillyTavern or Anima lorebook from this device',
              ),
              onTap: () => Navigator.pop(context, 'file'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (choice == 'existing') await _chooseExistingLorebook();
    if (choice == 'file') await _importLorebookFile();
  }

  Future<void> _delete(WorldWorkshop workshop) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete workshop?'),
        content: Text(
          'Remove “${workshop.title}”? '
          'Any lorebook or characters you already saved stay in the app.',
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
    if (confirmed != true) return;
    await widget.workshopService.delete(workshop.id);
    await _load();
  }

  String _subtitle(WorldWorkshop workshop) {
    final count = workshop.messages.length;
    final exported =
        workshop.exportedLorebookId != null ? ' · Linked to World Info' : '';
    if (count == 0) return 'No messages yet$exported';
    return '$count messages$exported';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Creation Center'),
        actions: [
          IconButton(
            tooltip: 'Import lorebook',
            onPressed: _busy ? null : _showImportOptions,
            icon: const Icon(Icons.file_upload_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : _create,
        icon: const Icon(Icons.add),
        label: const Text('New workshop'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _workshops.isEmpty
              ? ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    Text(
                      'Build a world by chatting with the AI. '
                      'When you’re ready, create a lorebook for World Info '
                      'and/or turn people from the chat into character cards. '
                      'You can also import a lorebook to revise it with AI.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'One workshop chat = one lorebook (characters are optional extras).',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 20),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _showImportOptions,
                      icon: const Icon(Icons.file_upload_outlined),
                      label: const Text('Import lorebook'),
                    ),
                  ],
                )
              : ListView.builder(
                  itemCount: _workshops.length,
                  itemBuilder: (context, index) {
                    final workshop = _workshops[index];
                    return ListTile(
                      leading: const Icon(Icons.travel_explore),
                      title: Text(workshop.title),
                      subtitle: Text(_subtitle(workshop)),
                      trailing: PopupMenuButton<String>(
                        onSelected: (value) {
                          if (value == 'delete') _delete(workshop);
                        },
                        itemBuilder: (context) => const [
                          PopupMenuItem(value: 'delete', child: Text('Delete')),
                        ],
                      ),
                      onTap: () => _open(workshop),
                    );
                  },
                ),
    );
  }
}
