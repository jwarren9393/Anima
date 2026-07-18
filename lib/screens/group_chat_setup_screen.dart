import 'package:flutter/material.dart';

import '../models/anima_presets.dart';
import '../models/character.dart';
import '../models/character_category.dart';
import '../models/global_lorebook.dart';
import '../services/character_category_service.dart';
import '../services/character_service.dart';
import '../services/chat_service.dart';
import '../services/persona_service.dart';
import '../services/world_info_service.dart';
import '../widgets/anima_avatar.dart';
import '../widgets/character_category_controls.dart';
import '../widgets/greeting_picker.dart';
import '../widgets/preset_picker.dart';

/// Setup screen for starting a multi-character group chat from Home (or chat).
class GroupChatSetupScreen extends StatefulWidget {
  const GroupChatSetupScreen({
    super.key,
    required this.characterService,
    required this.categoryService,
    required this.chatService,
    required this.personaService,
    required this.worldInfoService,
    this.preselectedIds = const {},
  });

  final CharacterService characterService;
  final CharacterCategoryService categoryService;
  final ChatService chatService;
  final PersonaService personaService;
  final WorldInfoService worldInfoService;

  /// Character ids already checked (e.g. current chat character).
  final Set<String> preselectedIds;

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
  bool _starting = false;

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

    final ordered = <Character>[];
    for (final id in widget.preselectedIds) {
      for (final c in characters) {
        if (c.id == id) {
          ordered.add(c);
          break;
        }
      }
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
        ..addAll(lore.where((b) => b.enabled).map((b) => b.id));
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

  bool get _canStart => _ordered.length >= 2 && !_starting;

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

  Future<void> _start() async {
    if (!_canStart) return;
    setState(() => _starting = true);
    try {
      final persona = await widget.personaService.getActivePersona();
      if (!mounted) {
        setState(() => _starting = false);
        return;
      }
      final first = _ordered.first;
      final greetingIndex = await pickGreetingIndex(
        context,
        character: first,
        userName: persona.name,
      );
      if (greetingIndex == null || !mounted) {
        setState(() => _starting = false);
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
      setState(() => _starting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not start group chat: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New group chat')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _all.length < 2
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'Create at least two characters first, then come back '
                      'to start a group chat.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                  children: [
                    Text(
                      'Pick who is in the group, drag to set reply order, then '
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
                      'Checked characters join the chat. Drag the list below '
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
                        'First in the list greets / speaks first.',
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
                  ],
                ),
      bottomNavigationBar: _all.length < 2
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton.icon(
                  onPressed: _canStart ? _start : null,
                  icon: _starting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.groups),
                  label: Text(
                    _ordered.length < 2
                        ? 'Pick at least 2 characters'
                        : 'Start group chat',
                  ),
                ),
              ),
            ),
    );
  }
}
