import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/character.dart';
import '../models/chat_session.dart';
import '../models/global_lorebook.dart';
import '../models/world_workshop.dart';
import '../models/workshop_chat_import_options.dart';
import '../services/api_key_service.dart';
import '../services/appearance_controller.dart';
import '../services/character_category_service.dart';
import '../services/character_service.dart';
import '../services/chat_service.dart';
import '../services/nanogpt_service.dart';
import '../services/persona_service.dart';
import '../services/settings_service.dart';
import '../services/world_info_service.dart';
import '../services/world_workshop_builder.dart';
import '../services/world_workshop_service.dart';
import '../services/workshop_hub_controller.dart';
import '../widgets/minimal_chip_button.dart';
import '../widgets/workshop_chat_import_sheet.dart';
import 'world_workshop_chat_screen.dart';

enum _WorkshopListFilter { all, pinned, lore, cast }

/// Settings → Creation Center: list of world-building workshop chats.
class WorldWorkshopListScreen extends StatefulWidget {
  const WorldWorkshopListScreen({
    super.key,
    required this.workshopService,
    required this.worldInfoService,
    required this.characterService,
    required this.characterCategoryService,
    required this.personaService,
    required this.chatService,
    required this.apiKeyService,
    required this.settingsService,
    required this.nanoGptService,
    required this.appearanceController,
  });

  final WorldWorkshopService workshopService;
  final WorldInfoService worldInfoService;
  final CharacterService characterService;
  final CharacterCategoryService characterCategoryService;
  final PersonaService personaService;
  final ChatService chatService;
  final ApiKeyService apiKeyService;
  final SettingsService settingsService;
  final NanoGptService nanoGptService;
  final AppearanceController appearanceController;

  @override
  State<WorldWorkshopListScreen> createState() =>
      _WorldWorkshopListScreenState();
}

class _WorldWorkshopListScreenState extends State<WorldWorkshopListScreen> {
  final _builder = WorldWorkshopBuilder();
  final _hubController = WorkshopHubController();

  List<WorldWorkshop> _workshops = [];
  String _searchQuery = '';
  _WorkshopListFilter _filter = _WorkshopListFilter.all;
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
          characterCategoryService: widget.characterCategoryService,
          personaService: widget.personaService,
          chatService: widget.chatService,
          apiKeyService: widget.apiKeyService,
          settingsService: widget.settingsService,
          nanoGptService: widget.nanoGptService,
          worldWorkshopService: widget.workshopService,
          appearanceController: widget.appearanceController,
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

  Future<Map<String, Character>> _characterLookup() async {
    final all = await widget.characterService.loadCharacters();
    return {for (final c in all) c.id: c};
  }

  String _participantLabel(
    ChatSession session,
    Map<String, Character> characters,
  ) {
    final names = <String>[];
    for (final id in session.effectiveParticipantIds) {
      final character = characters[id];
      if (character == null) continue;
      final name = character.name.trim();
      if (name.isNotEmpty) names.add(name);
    }
    if (names.isEmpty) {
      return session.isGroup ? 'Group chat' : 'Character missing';
    }
    if (names.length == 1) return names.first;
    if (names.length == 2) return '${names[0]}, ${names[1]}';
    return '${names[0]}, ${names[1]} +${names.length - 2}';
  }

  Future<void> _chooseExistingChat() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final chats = await widget.chatService.listAllChats();
      final characters = await _characterLookup();
      if (!mounted) return;
      if (chats.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No saved chats yet. Start a chat, then import it here.'),
          ),
        );
        return;
      }

      final selected = await showModalBottomSheet<ChatSession>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (context) {
          final maxHeight = MediaQuery.sizeOf(context).height * 0.75;
          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeight),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                    child: Text(
                      'Import existing chat',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    child: Text(
                      'Pick a chat, then choose what to import (trimmed history, '
                      'optional lorebooks, etc.).',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: chats.length,
                      itemBuilder: (context, index) {
                        final chat = chats[index];
                        final participants =
                            _participantLabel(chat, characters);
                        final count = chat.messages
                            .where((m) => m.text.trim().isNotEmpty)
                            .length;
                        final local = chat.updatedAt.toLocal();
                        final stamp =
                            '${local.month}/${local.day} '
                            '${local.hour.toString().padLeft(2, '0')}:'
                            '${local.minute.toString().padLeft(2, '0')}';
                        return ListTile(
                          leading: Icon(
                            chat.isGroup
                                ? Icons.groups_outlined
                                : Icons.chat_bubble_outline,
                          ),
                          title: Text(
                            chat.title.trim().isEmpty
                                ? participants
                                : chat.title.trim(),
                          ),
                          subtitle: Text(
                            '$participants · $count messages · $stamp'
                            '${chat.memorySummary.trim().isEmpty ? '' : ' · has summary'}',
                          ),
                          onTap: () => Navigator.pop(context, chat),
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

      final contextSettings =
          await widget.settingsService.getContextSettings();
      final loreCounts = _loreCountsForChat(selected, characters);
      if (!mounted) return;

      final options = await pickWorkshopChatImportOptions(
        context,
        session: selected,
        keepRecentDefault: contextSettings.summarizeKeepRecent,
        linkedLorebookCount: loreCounts.$1,
        embeddedLorebookCount: loreCounts.$2,
      );
      if (options == null || !mounted) return;

      await _importChat(selected, characters, options);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not import chat: $error')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Returns (linked global lorebook count, embedded character lorebook count).
  (int, int) _loreCountsForChat(
    ChatSession session,
    Map<String, Character> characterLookup,
  ) {
    final linkedIds = session.lorebookIds;
    final linkedCount =
        linkedIds == null ? 0 : linkedIds.where((id) => id.trim().isNotEmpty).length;

    var embedded = 0;
    for (final id in session.effectiveParticipantIds) {
      final book = characterLookup[id]?.lorebook;
      if (book != null && book.entries.isNotEmpty) embedded++;
    }
    return (linkedCount, embedded);
  }

  Future<void> _importChat(
    ChatSession session,
    Map<String, Character> characterLookup,
    WorkshopChatImportOptions options,
  ) async {
    final skipped = <String>[];
    final characters = <Character>[];
    for (final id in session.effectiveParticipantIds) {
      final character = characterLookup[id];
      if (character == null) {
        skipped.add('Character id $id (deleted)');
        continue;
      }
      characters.add(character);
    }

    final personaId = session.personaId?.trim();
    final persona = (personaId == null || personaId.isEmpty)
        ? null
        : await widget.personaService.getById(personaId);
    if (personaId != null &&
        personaId.isNotEmpty &&
        persona == null) {
      skipped.add('Persona (deleted)');
    }

    final linked = <GlobalLorebook>[];
    if (options.includeGlobalLorebooks) {
      final loreIds = session.lorebookIds;
      if (loreIds != null) {
        for (final id in loreIds) {
          final book = await widget.worldInfoService.getById(id);
          if (book == null) {
            skipped.add('Lorebook id $id (deleted)');
            continue;
          }
          if (book.book.entries.isEmpty) continue;
          linked.add(book);
        }
      }
    }

    final source = _builder.buildImportedChatSource(
      session: session,
      characters: characters,
      persona: persona,
      linkedLorebooks: linked,
      skippedNotes: skipped,
      options: options,
    );
    if (!source.hasContent) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'That chat has no usable source yet (empty messages and no cards).',
          ),
        ),
      );
      return;
    }

    final title = session.title.trim().isEmpty
        ? 'From chat'
        : 'From: ${session.title.trim()}';
    final workshop = await widget.workshopService.upsert(
      WorldWorkshop.empty(title: title).copyWith(importedSource: source),
    );
    if (!mounted) return;

    if (skipped.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Imported with ${skipped.length} missing reference'
            '${skipped.length == 1 ? '' : 's'} skipped.',
          ),
        ),
      );
    }
    await _open(workshop);
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
              leading: const Icon(Icons.chat_bubble_outline),
              title: const Text('Existing chat'),
              subtitle: const Text(
                'Seed a workshop from a saved roleplay chat',
              ),
              onTap: () => Navigator.pop(context, 'chat'),
            ),
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
    if (choice == 'chat') await _chooseExistingChat();
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

  Future<void> _togglePin(WorldWorkshop workshop) async {
    await widget.workshopService.upsert(
      workshop.copyWith(pinned: !workshop.pinned),
    );
    await _load();
  }

  Future<void> _duplicate(WorldWorkshop workshop) async {
    final copy = _hubController.hub.duplicate(workshop);
    await widget.workshopService.upsert(copy);
    await _load();
  }

  Future<void> _importBundle() async {
    try {
      final bundle = await _hubController.importBundleFile();
      if (bundle == null) return;
      if (bundle.lorebook != null) {
        await widget.worldInfoService.upsert(bundle.lorebook!);
      }
      for (final c in bundle.characters) {
        await widget.characterService.upsert(c);
      }
      if (bundle.persona != null) {
        await widget.personaService.upsert(bundle.persona!);
      }
      await widget.workshopService.upsert(bundle.workshop);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('World bundle imported.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Import failed: $error')),
      );
    }
  }

  List<WorldWorkshop> get _filteredWorkshops {
    final q = _searchQuery.trim().toLowerCase();
    return [
      for (final w in _workshops)
        if (_matchesFilter(w) &&
            (q.isEmpty ||
                w.title.toLowerCase().contains(q) ||
                w.tags.any((t) => t.toLowerCase().contains(q))))
          w,
    ];
  }

  bool _matchesFilter(WorldWorkshop w) {
    switch (_filter) {
      case _WorkshopListFilter.all:
        return true;
      case _WorkshopListFilter.pinned:
        return w.pinned;
      case _WorkshopListFilter.lore:
        return w.exportedLorebookId != null;
      case _WorkshopListFilter.cast:
        return w.linkedCharacterIds.isNotEmpty;
    }
  }

  Future<void> _showWorkshopActions(WorldWorkshop workshop) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                workshop.pinned ? Icons.push_pin_outlined : Icons.push_pin,
              ),
              title: Text(workshop.pinned ? 'Unpin' : 'Pin'),
              onTap: () => Navigator.pop(context, 'pin'),
            ),
            ListTile(
              leading: const Icon(Icons.copy_outlined),
              title: const Text('Duplicate'),
              onTap: () => Navigator.pop(context, 'duplicate'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Delete'),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    if (action == 'pin') await _togglePin(workshop);
    if (action == 'duplicate') await _duplicate(workshop);
    if (action == 'delete') await _delete(workshop);
  }

  String _subtitle(WorldWorkshop workshop) {
    final count = workshop.messages.length;
    final bits = <String>[];
    if (count == 0) {
      bits.add('No messages yet');
    } else {
      bits.add('$count messages');
    }
    if (workshop.importedSource != null) {
      bits.add('from chat');
    }
    if (workshop.exportedLorebookId != null) {
      bits.add('Linked to World Info');
    }
    if (workshop.pinned) bits.add('pinned');
    return bits.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Creation Center'),
        actions: [
          IconButton(
            tooltip: 'Import world bundle',
            onPressed: _busy ? null : _importBundle,
            icon: const Icon(Icons.archive_outlined),
          ),
          IconButton(
            tooltip: 'Import',
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
                      'You can also import a lorebook or an existing roleplay chat.',
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
                      label: const Text('Import'),
                    ),
                  ],
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: TextField(
                        decoration: const InputDecoration(
                          hintText: 'Search worlds…',
                          prefixIcon: Icon(Icons.search),
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        onChanged: (v) => setState(() => _searchQuery = v),
                      ),
                    ),
                    MinimalChipRow(
                      children: [
                        MinimalChipButton(
                          label: 'All',
                          selected: _filter == _WorkshopListFilter.all,
                          onPressed: () => setState(
                            () => _filter = _WorkshopListFilter.all,
                          ),
                        ),
                        const SizedBox(width: 8),
                        MinimalChipButton(
                          label: 'Pinned',
                          selected: _filter == _WorkshopListFilter.pinned,
                          onPressed: () => setState(
                            () => _filter = _WorkshopListFilter.pinned,
                          ),
                        ),
                        const SizedBox(width: 8),
                        MinimalChipButton(
                          label: 'Has lore',
                          selected: _filter == _WorkshopListFilter.lore,
                          onPressed: () => setState(
                            () => _filter = _WorkshopListFilter.lore,
                          ),
                        ),
                        const SizedBox(width: 8),
                        MinimalChipButton(
                          label: 'Has cast',
                          selected: _filter == _WorkshopListFilter.cast,
                          onPressed: () => setState(
                            () => _filter = _WorkshopListFilter.cast,
                          ),
                        ),
                      ],
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: _filteredWorkshops.length,
                        itemBuilder: (context, index) {
                          final workshop = _filteredWorkshops[index];
                          return ListTile(
                            leading: Icon(
                              workshop.pinned
                                  ? Icons.push_pin
                                  : workshop.importedSource != null
                                      ? Icons.forum_outlined
                                      : Icons.travel_explore,
                            ),
                            title: Text(workshop.title),
                            subtitle: Text(_subtitle(workshop)),
                            onTap: () => _open(workshop),
                            onLongPress: _busy
                                ? null
                                : () => _showWorkshopActions(workshop),
                          );
                        },
                      ),
                    ),
                  ],
                ),
    );
  }
}
