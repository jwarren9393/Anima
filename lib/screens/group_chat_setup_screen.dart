import 'package:flutter/material.dart';

import '../models/anima_presets.dart';
import '../models/character.dart';
import '../models/character_category.dart';
import '../models/chat_session.dart';
import '../models/global_lorebook.dart';
import '../services/character_category_service.dart';
import '../services/character_service.dart';
import '../services/chat_service.dart';
import '../services/nanogpt_service.dart';
import '../services/opening_scene_service.dart';
import '../services/persona_service.dart';
import '../services/settings_service.dart';
import '../services/world_info_service.dart';
import '../services/world_workshop_service.dart';
import '../widgets/anima_avatar.dart';
import '../widgets/character_category_controls.dart';
import '../widgets/create_character_from_chat_sheet.dart';
import '../widgets/greeting_picker.dart';
import '../widgets/minimal_chip_button.dart';
import '../widgets/opening_scene_picker.dart';
import '../widgets/preset_picker.dart';
import 'character_edit_screen.dart';

/// Setup screen for starting a multi-character group chat from Home,
/// or managing who is in an existing chat from the chat menu.
class GroupChatSetupScreen extends StatefulWidget {
  const GroupChatSetupScreen({
    super.key,
    required this.characterService,
    required this.categoryService,
    required this.chatService,
    required this.personaService,
    required this.worldInfoService,
    required this.settingsService,
    required this.nanoGptService,
    required this.openingSceneService,
    required this.worldWorkshopService,
    this.preselectedIds = const {},
    this.existingSession,
    this.initialOpeningScene = '',
  });

  final CharacterService characterService;
  final CharacterCategoryService categoryService;
  final ChatService chatService;
  final PersonaService personaService;
  final WorldInfoService worldInfoService;
  final SettingsService settingsService;
  final NanoGptService nanoGptService;
  final OpeningSceneService openingSceneService;
  final WorldWorkshopService worldWorkshopService;

  /// Character ids already checked (e.g. current chat cast).
  final Set<String> preselectedIds;

  /// When set, changes apply to this chat instead of starting a new one.
  final ChatSession? existingSession;

  /// Prefill opening scene when starting from Creation Center.
  final String initialOpeningScene;

  bool get isEditMode => existingSession != null;

  @override
  State<GroupChatSetupScreen> createState() => _GroupChatSetupScreenState();
}

class _GroupChatSetupScreenState extends State<GroupChatSetupScreen> {
  List<Character> _all = const [];
  CharacterCategoryState _categoryState = CharacterCategoryState.empty;
  String _filterCategoryId = CharacterCategoryService.allFilterId;
  List<GlobalLorebook> _lorebooks = const [];
  final List<Character> _ordered = [];
  final Set<String> _selectedLoreIds = {};
  final _authorsNoteController = TextEditingController();
  final _openingSceneController = TextEditingController();
  final _titleController = TextEditingController();
  bool _autoReply = false;
  bool _loading = true;
  bool _working = false;

  bool get _isEditMode => widget.isEditMode;

  /// Filtered catalog, plus any already-checked members so they stay visible.
  List<Character> get _pickerCharacters {
    final filtered = widget.categoryService.filterCharacters(
      _all,
      state: _categoryState,
      categoryId: _filterCategoryId,
    );
    if (_filterCategoryId.isEmpty || _ordered.isEmpty) return filtered;
    final seen = filtered.map((c) => c.id).toSet();
    final extras = <Character>[];
    for (final member in _ordered) {
      if (seen.contains(member.id)) continue;
      extras.add(member);
      seen.add(member.id);
    }
    if (extras.isEmpty) return filtered;
    return [...filtered, ...extras];
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final characters = await widget.characterService.loadCharacters();
    var categoryState = await widget.categoryService.loadState();
    categoryState = await widget.categoryService.prune(
      existingCharacterIds: characters.map((c) => c.id),
    );
    final lore = await widget.worldInfoService.loadBooks();
    if (!mounted) return;

    final session = widget.existingSession;
    final idsToSelect = session != null
        ? session.effectiveParticipantIds
        : widget.preselectedIds.toList();

    final ordered = <Character>[];
    for (final id in idsToSelect) {
      for (final c in characters) {
        if (c.id == id) {
          ordered.add(c);
          break;
        }
      }
    }

    final selectedLore = <String>{};
    if (session?.lorebookIds != null) {
      selectedLore.addAll(session!.lorebookIds!);
    } else {
      selectedLore.addAll(lore.where((b) => b.enabled).map((b) => b.id));
    }

    setState(() {
      _all = characters;
      _categoryState = categoryState;
      _lorebooks = lore;
      _ordered
        ..clear()
        ..addAll(ordered);
      _selectedLoreIds
        ..clear()
        ..addAll(selectedLore);
      if (session != null) {
        _authorsNoteController.text = session.authorsNote;
        _openingSceneController.text = session.openingScene;
        _autoReply = session.autoReply;
        final storedTitle = session.title.trim();
        _titleController.text = ChatService.isLegacyGroupMemberListTitle(
          storedTitle,
        )
            ? ''
            : storedTitle;
      } else if (widget.initialOpeningScene.trim().isNotEmpty) {
        _openingSceneController.text = widget.initialOpeningScene.trim();
      }
      _loading = false;
    });
  }

  Future<void> _manageCategories() async {
    await showManageCharacterCategoriesSheet(
      context: context,
      categoryService: widget.categoryService,
      state: _categoryState,
      onChanged: (next) {
        if (!mounted) return;
        setState(() {
          _categoryState = next;
          final stillValid = _filterCategoryId.isEmpty ||
              next.categories.any((c) => c.id == _filterCategoryId);
          if (!stillValid) {
            _filterCategoryId = CharacterCategoryService.allFilterId;
          }
        });
      },
    );
    await _load();
  }

  @override
  void dispose() {
    _authorsNoteController.dispose();
    _openingSceneController.dispose();
    _titleController.dispose();
    super.dispose();
  }

  bool get _canConfirm {
    if (_working) return false;
    if (_isEditMode) return _ordered.isNotEmpty;
    return _ordered.length >= 2;
  }

  void _toggleMember(Character character, bool on) {
    setState(() {
      if (on) {
        if (!_ordered.any((c) => c.id == character.id)) {
          _ordered.add(character);
        }
      } else {
        _ordered.removeWhere((c) => c.id == character.id);
      }
    });
  }

  Future<void> _createCharacter() async {
    if (widget.isEditMode && widget.existingSession != null) {
      final persona = await widget.personaService.getActivePersona();
      if (!mounted) return;
      final created = await showCreateCharacterFromChatSheet(
        context: context,
        session: widget.existingSession!,
        participants: _ordered,
        persona: persona,
        characterService: widget.characterService,
        settingsService: widget.settingsService,
        nanoGptService: widget.nanoGptService,
        worldInfoService: widget.worldInfoService,
      );
      if (created == null || !mounted) return;
      await _load();
      if (!mounted) return;
      setState(() {
        if (!_ordered.any((c) => c.id == created.id)) {
          _ordered.add(created);
        }
      });
      return;
    }

    final created = await Navigator.of(context).push<Character>(
      MaterialPageRoute(
        builder: (_) => CharacterEditScreen(
          characterService: widget.characterService,
          settingsService: widget.settingsService,
          nanoGptService: widget.nanoGptService,
        ),
      ),
    );
    if (created == null || !mounted) return;
    await _load();
    if (!mounted) return;
    setState(() {
      if (!_ordered.any((c) => c.id == created.id)) {
        _ordered.add(created);
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Created ${created.name}')),
    );
  }

  Future<void> _confirm() async {
    if (!_canConfirm) return;
    setState(() => _working = true);
    try {
      if (_isEditMode) {
        final updated = await widget.chatService.updateSessionCast(
          widget.existingSession!,
          List<Character>.from(_ordered),
          authorsNote: _authorsNoteController.text,
          autoReply: _autoReply,
          lorebookIds: _lorebooks.isEmpty
              ? const []
              : _selectedLoreIds.toList(growable: false),
          title: _titleController.text,
        );
        if (!mounted) return;
        Navigator.of(context).pop(updated);
        return;
      }

      final persona = await widget.personaService.getActivePersona();
      if (!mounted) {
        setState(() => _working = false);
        return;
      }
      final first = _ordered.first;
      final greetingIndex = await pickGreetingIndex(
        context,
        character: first,
        userName: persona.name,
      );
      if (greetingIndex == null || !mounted) {
        setState(() => _working = false);
        return;
      }
      await widget.openingSceneService.importMissingFromWorkshops(
        await widget.worldWorkshopService.loadWorkshops(),
      );
      if (!mounted) {
        setState(() => _working = false);
        return;
      }
      final savedScenes = await widget.openingSceneService.loadScenes();
      if (!mounted) {
        setState(() => _working = false);
        return;
      }
      final openingPick = await pickOpeningScene(
        context,
        initial: _openingSceneController.text,
        savedScenes: savedScenes,
        openingSceneService: widget.openingSceneService,
        workshopService: widget.worldWorkshopService,
      );
      if (openingPick == null || !mounted) {
        setState(() => _working = false);
        return;
      }
      final session = await widget.chatService.startGroupChat(
        List<Character>.from(_ordered),
        userName: persona.name,
        personaId: persona.id,
        authorsNote: _authorsNoteController.text,
        autoReply: _autoReply,
        lorebookIds: _lorebooks.isEmpty
            ? null
            : _selectedLoreIds.toList(growable: false),
        greetingIndex: greetingIndex,
        openingScene: openingPick.text,
        title: _titleController.text,
      );
      if (!mounted) return;
      Navigator.of(context).pop(session);
    } catch (error) {
      if (!mounted) return;
      setState(() => _working = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isEditMode
                ? 'Could not update cast: $error'
                : 'Could not start group chat: $error',
          ),
        ),
      );
    }
  }

  String get _confirmLabel {
    if (_isEditMode) {
      if (_ordered.isEmpty) return 'Pick at least 1 character';
      if (_ordered.length == 1) return 'Save cast (solo)';
      return 'Save cast (${_ordered.length} characters)';
    }
    if (_ordered.length < 2) return 'Pick at least 2 characters';
    return 'Start group chat';
  }

  Future<void> _showLorePicker() async {
    if (_lorebooks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No global lorebooks yet. Add them under Settings → World Info.',
          ),
        ),
      );
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        final height = MediaQuery.sizeOf(sheetContext).height * 0.55;
        return SafeArea(
          child: SizedBox(
            height: height,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: Text(
                    'Global lorebooks',
                    style: Theme.of(sheetContext).textTheme.titleMedium,
                  ),
                ),
                Expanded(
                  child: ListView(
                    children: [
                      for (final book in _lorebooks)
                        CheckboxListTile(
                          value: _selectedLoreIds.contains(book.id),
                          title: Text(book.displayName),
                          subtitle: Text(
                            '${book.enabledEntryCount} entries'
                            '${book.enabled ? '' : ' · off in Settings'}',
                          ),
                          onChanged: (v) {
                            setState(() {
                              if (v == true) {
                                _selectedLoreIds.add(book.id);
                              } else {
                                _selectedLoreIds.remove(book.id);
                              }
                            });
                          },
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: FilledButton(
                    onPressed: () => Navigator.pop(sheetContext),
                    child: const Text('Done'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showOpeningSceneEditor() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
          ),
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Opening scene',
                    style: Theme.of(sheetContext).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Optional narrator setup at the top of the chat.',
                    style: Theme.of(sheetContext).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _openingSceneController,
                    minLines: 4,
                    maxLines: 10,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      hintText: 'The harbor fog lifts as your party gathers…',
                      border: OutlineInputBorder(),
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () => Navigator.pop(sheetContext),
                    child: const Text('Done'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    setState(() {});
  }

  Future<void> _showAuthorsNoteEditor() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
          ),
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    "Author's Note",
                    style: Theme.of(sheetContext).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Injected every turn for this chat only.',
                    style: Theme.of(sheetContext).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  PresetButton(
                    label: 'Author’s Note presets',
                    onPressed: () async {
                      final preset = await pickTextPreset(
                        context: sheetContext,
                        title: "Author's Note presets",
                        presets: AnimaPresets.authorsNotes,
                      );
                      if (preset == null) return;
                      _authorsNoteController.text = preset.text;
                    },
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _authorsNoteController,
                    minLines: 4,
                    maxLines: 10,
                    decoration: const InputDecoration(
                      hintText: 'e.g. Keep replies short. Stay in character.',
                      border: OutlineInputBorder(),
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () => Navigator.pop(sheetContext),
                    child: const Text('Done'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    setState(() {});
  }

  Widget _optionsChipRow() {
    final hasScene = _openingSceneController.text.trim().isNotEmpty;
    final hasNote = _authorsNoteController.text.trim().isNotEmpty;
    return MinimalChipRow(
      children: [
        MinimalChipButton(
          label: 'Lore (${_selectedLoreIds.length})',
          icon: Icons.menu_book_outlined,
          onPressed: _working ? null : _showLorePicker,
        ),
        const SizedBox(width: 8),
        MinimalChipButton(
          label: hasScene ? 'Scene' : 'Add scene',
          icon: hasScene
              ? Icons.check_circle_outline
              : Icons.auto_stories_outlined,
          onPressed: _working ? null : _showOpeningSceneEditor,
        ),
        const SizedBox(width: 8),
        MinimalChipButton(
          label: hasNote ? 'Note' : 'Add note',
          icon: hasNote ? Icons.check_circle_outline : Icons.edit_note,
          onPressed: _working ? null : _showAuthorsNoteEditor,
        ),
        const SizedBox(width: 8),
        MinimalChipButton(
          label: _autoReply ? 'Auto-reply' : 'Manual',
          icon: _autoReply ? Icons.bolt : Icons.touch_app_outlined,
          selected: _autoReply,
          onPressed: _working
              ? null
              : () => setState(() => _autoReply = !_autoReply),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final minCharacters = _isEditMode ? 1 : 2;
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditMode ? 'Manage cast' : 'New group chat'),
        actions: [
          IconButton(
            tooltip: 'Create character',
            icon: const Icon(Icons.person_add_outlined),
            onPressed: _working ? null : _createCharacter,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _all.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'Create a character first, then come back to manage '
                      'who is in this chat.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                  children: [
                    Text(
                      _isEditMode
                          ? 'Add or remove characters. Drag to set reply order.'
                          : 'Pick characters, set order, then tune options below.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _titleController,
                      enabled: !_working,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        labelText: 'Chat name',
                        hintText: ChatService.defaultGroupTitle(
                          _ordered.length.clamp(2, 99),
                        ),
                        helperText:
                            'Optional. Give this group a name you will recognize.',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Characters',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    CharacterCategoryFilterBar(
                      state: _categoryState,
                      selectedCategoryId: _filterCategoryId,
                      onChanged: (id) =>
                          setState(() => _filterCategoryId = id),
                      onManage: _manageCategories,
                    ),
                    const SizedBox(height: 4),
                    ..._pickerCharacters.map((c) {
                      final on = _ordered.any((m) => m.id == c.id);
                      return CheckboxListTile(
                        value: on,
                        secondary: AnimaAvatar(
                          fileName: c.avatarFileName,
                          label: c.name,
                          radius: 18,
                        ),
                        title: Text(c.name),
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: EdgeInsets.zero,
                        onChanged: (v) => _toggleMember(c, v == true),
                      );
                    }),
                    if (_ordered.length >= 2) ...[
                      const SizedBox(height: 16),
                      Text(
                        'Reply order',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      ReorderableListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _ordered.length,
                        onReorderItem: (oldIndex, newIndex) {
                          setState(() {
                            final item = _ordered.removeAt(oldIndex);
                            _ordered.insert(newIndex, item);
                          });
                        },
                        itemBuilder: (context, index) {
                          final c = _ordered[index];
                          return ListTile(
                            key: ValueKey(c.id),
                            leading: CircleAvatar(
                              child: Text('${index + 1}'),
                            ),
                            title: Text(c.name),
                            trailing: const Icon(Icons.drag_handle),
                          );
                        },
                      ),
                    ],
                    const SizedBox(height: 12),
                    _optionsChipRow(),
                    if (_all.length < minCharacters) ...[
                      const SizedBox(height: 16),
                      Text(
                        _isEditMode
                            ? 'You need at least one character in the cast.'
                            : 'Create at least two characters first, then come back '
                                'to start a group chat.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
      bottomNavigationBar: _all.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton.icon(
                  onPressed: _canConfirm ? _confirm : null,
                  icon: _working
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(_isEditMode ? Icons.save : Icons.groups),
                  label: Text(_confirmLabel),
                ),
              ),
            ),
    );
  }
}
