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
import '../services/persona_service.dart';
import '../services/settings_service.dart';
import '../services/world_info_service.dart';
import '../widgets/anima_avatar.dart';
import '../widgets/character_category_controls.dart';
import '../widgets/greeting_picker.dart';
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
    this.preselectedIds = const {},
    this.existingSession,
  });

  final CharacterService characterService;
  final CharacterCategoryService categoryService;
  final ChatService chatService;
  final PersonaService personaService;
  final WorldInfoService worldInfoService;
  final SettingsService settingsService;
  final NanoGptService nanoGptService;

  /// Character ids already checked (e.g. current chat cast).
  final Set<String> preselectedIds;

  /// When set, changes apply to this chat instead of starting a new one.
  final ChatSession? existingSession;

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
        _autoReply = session.autoReply;
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
                          ? 'Add or remove characters in this chat. Drag to set '
                              'reply order. History stays — nothing starts over.'
                          : 'Pick who is in the group, drag to set reply order, then '
                              'tune auto-reply, lore, and Author’s Note.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Characters',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _isEditMode
                          ? 'Check characters to include. Uncheck to remove them '
                              'from this chat. Use + in the app bar to create someone new.'
                          : 'Checked characters join the chat. Drag the list below '
                              'to set who speaks first (round-robin after that).',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
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
                      const SizedBox(height: 4),
                      Text(
                        'First in the list speaks next when auto-reply is on.',
                        style: Theme.of(context).textTheme.bodySmall,
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
                    const SizedBox(height: 20),
                    Text(
                      'Replies',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Auto-reply'),
                      subtitle: Text(
                        _autoReply
                            ? 'Sending a message also generates the next AI reply.'
                            : 'Manual mode — your message posts alone. Tap a '
                                'name chip or Continue for a reply.',
                      ),
                      value: _autoReply,
                      onChanged: (v) => setState(() => _autoReply = v),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'World Info / lorebooks',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    if (_lorebooks.isEmpty)
                      Text(
                        'No global lorebooks yet. Add them under Settings → '
                        'World Info & lore. Each character’s own book still '
                        'applies when they speak.',
                        style: Theme.of(context).textTheme.bodySmall,
                      )
                    else ...[
                      Text(
                        'Choose which global lorebooks apply to this chat. '
                        'Each character’s card lorebook still applies when '
                        'they speak.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 8),
                      ..._lorebooks.map((book) {
                        final on = _selectedLoreIds.contains(book.id);
                        return CheckboxListTile(
                          value: on,
                          title: Text(book.displayName),
                          subtitle: Text(
                            '${book.enabledEntryCount} entries'
                            '${book.enabled ? '' : ' · off in Settings'}',
                          ),
                          controlAffinity: ListTileControlAffinity.leading,
                          contentPadding: EdgeInsets.zero,
                          onChanged: (v) {
                            setState(() {
                              if (v == true) {
                                _selectedLoreIds.add(book.id);
                              } else {
                                _selectedLoreIds.remove(book.id);
                              }
                            });
                          },
                        );
                      }),
                    ],
                    const SizedBox(height: 20),
                    Text(
                      'Author’s Note',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Optional chat instructions injected every turn '
                      '(same as ⋮ → Author’s Note).',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    PresetButton(
                      label: 'Author’s Note presets',
                      onPressed: () async {
                        final preset = await pickTextPreset(
                          context: context,
                          title: "Author's Note presets",
                          presets: AnimaPresets.authorsNotes,
                        );
                        if (preset == null) return;
                        setState(() {
                          _authorsNoteController.text = preset.text;
                        });
                      },
                    ),
                    TextField(
                      controller: _authorsNoteController,
                      minLines: 3,
                      maxLines: 6,
                      decoration: const InputDecoration(
                        hintText: 'e.g. Keep replies short. Stay in character.',
                        border: OutlineInputBorder(),
                        alignLabelWithHint: true,
                      ),
                    ),
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
