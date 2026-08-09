import 'package:flutter/material.dart';

import '../models/character.dart';
import '../models/chat_session.dart';
import '../models/global_lorebook.dart';
import '../models/persona.dart';
import '../screens/character_edit_screen.dart';
import '../services/character_service.dart';
import '../services/nanogpt_service.dart';
import '../services/settings_service.dart';
import '../services/world_info_service.dart';
import '../services/world_workshop_builder.dart';

/// Result from updating a character from chat context.
class CharacterChatUpdateResult {
  const CharacterChatUpdateResult({
    required this.character,
    required this.chatOnly,
  });

  final Character character;
  final bool chatOnly;
}

/// Bottom sheet: update one saved character card from the current chat context.
Future<CharacterChatUpdateResult?> showUpdateCharacterFromChatSheet({
  required BuildContext context,
  required ChatSession session,
  required List<Character> participants,
  required Persona? persona,
  required CharacterService characterService,
  required SettingsService settingsService,
  required NanoGptService nanoGptService,
  required WorldInfoService worldInfoService,
}) {
  return showModalBottomSheet<CharacterChatUpdateResult>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _UpdateCharacterFromChatSheet(
      session: session,
      participants: participants,
      persona: persona,
      characterService: characterService,
      settingsService: settingsService,
      nanoGptService: nanoGptService,
      worldInfoService: worldInfoService,
    ),
  );
}

class _UpdateCharacterFromChatSheet extends StatefulWidget {
  const _UpdateCharacterFromChatSheet({
    required this.session,
    required this.participants,
    required this.persona,
    required this.characterService,
    required this.settingsService,
    required this.nanoGptService,
    required this.worldInfoService,
  });

  final ChatSession session;
  final List<Character> participants;
  final Persona? persona;
  final CharacterService characterService;
  final SettingsService settingsService;
  final NanoGptService nanoGptService;
  final WorldInfoService worldInfoService;

  @override
  State<_UpdateCharacterFromChatSheet> createState() =>
      _UpdateCharacterFromChatSheetState();
}

class _UpdateCharacterFromChatSheetState
    extends State<_UpdateCharacterFromChatSheet> {
  final _builder = WorldWorkshopBuilder();
  final _notesController = TextEditingController();

  List<GlobalLorebook> _linkedLorebooks = const [];
  List<Character> _allCharacters = const [];
  Character? _selected;
  bool _loading = true;
  bool _generating = false;
  String? _error;

  bool get _hasChatContext =>
      widget.session.messages.any((m) => m.text.trim().isNotEmpty) ||
      widget.session.memorySummary.trim().isNotEmpty;

  Set<String> get _participantIds => {
        for (final c in widget.participants) c.id,
      };

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final linked = <GlobalLorebook>[];
    final loreIds = widget.session.lorebookIds;
    if (loreIds == null) {
      final enabled = await widget.worldInfoService.loadBooks();
      linked.addAll(
        enabled.where((b) => b.enabled && b.book.entries.isNotEmpty),
      );
    } else {
      for (final id in loreIds) {
        final book = await widget.worldInfoService.getById(id);
        if (book == null || book.book.entries.isEmpty) continue;
        linked.add(book);
      }
    }

    final all = await widget.characterService.loadCharacters();
    final ordered = _builder.prioritizeCharactersForChatUpdate(
      allCharacters: all,
      participants: widget.participants,
    );

    if (!mounted) return;
    setState(() {
      _linkedLorebooks = linked;
      _allCharacters = ordered;
      _selected = ordered.isNotEmpty ? ordered.first : null;
      _loading = false;
    });
  }

  Future<void> _updateFromChat({required bool chatOnly}) async {
    final selected = _selected;
    if (selected == null) {
      setState(() => _error = 'Choose a saved character to update.');
      return;
    }
    if (!_hasChatContext) {
      setState(() => _error = 'Chat a bit first so the AI has context.');
      return;
    }

    setState(() {
      _generating = true;
      _error = null;
    });

    try {
      final build = await widget.settingsService.resolveCharacterBuild();
      final baseUrl = await widget.settingsService.getApiBaseUrl();
      final messages = _builder.buildChatCharacterUpdateMessages(
        session: widget.session,
        characters: widget.participants,
        existing: selected,
        persona: widget.persona,
        linkedLorebooks: _linkedLorebooks,
        changeNotes: _notesController.text,
        buildPromptNote: build.promptNote,
      );

      Character? draft;
      for (var attempt = 0; attempt < 2; attempt++) {
        final cardRaw = await widget.nanoGptService.complete(
          model: build.model,
          messages: messages,
          baseUrl: baseUrl,
          sampling: WorldWorkshopBuilder.workshopExportSampling(build.sampling),
        );
        try {
          draft = _builder.parseCharacterUpdateJson(
            cardRaw,
            original: selected,
          );
          break;
        } on FormatException {
          if (attempt == 1) rethrow;
        }
      }
      if (draft == null) {
        throw const FormatException(
          'Could not find character card JSON in the AI reply. Try again.',
        );
      }

      if (!mounted) return;
      setState(() => _generating = false);

      final saved = await Navigator.of(context, rootNavigator: true)
          .push<Character>(
        MaterialPageRoute(
          builder: (_) => CharacterEditScreen(
            characterService: widget.characterService,
            settingsService: widget.settingsService,
            nanoGptService: widget.nanoGptService,
            existing: draft,
            generatedDraft: true,
            updatingExisting: !chatOnly,
            persistToLibrary: !chatOnly,
          ),
        ),
      );
      if (!mounted || saved == null) return;
      Navigator.of(context).pop(
        CharacterChatUpdateResult(character: saved, chatOnly: chatOnly),
      );
    } on FormatException catch (error) {
      if (!mounted) return;
      setState(() {
        _generating = false;
        _error = error.message;
      });
    } on NanoGptException catch (error) {
      if (!mounted) return;
      setState(() {
        _generating = false;
        _error = error.message;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _generating = false;
        _error = '$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final busy = _generating || _loading;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 8,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Update character', style: theme.textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(
              _hasChatContext
                  ? 'Pick a saved card to revise from this chat. Characters '
                      'in this thread are listed first. Choose whether to '
                      'update this chat only or overwrite the library card.'
                  : 'Chat a bit first, then update a character from what happened.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_allCharacters.isEmpty)
              Text(
                'No saved characters yet. Create one first, then update it here.',
                style: theme.textTheme.bodySmall,
              )
            else
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.35,
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _allCharacters.length,
                  itemBuilder: (context, index) {
                    final character = _allCharacters[index];
                    final inChat = _participantIds.contains(character.id);
                    final isSelected = identical(_selected, character);
                    return ListTile(
                      leading: Icon(
                        isSelected
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                        color: isSelected
                            ? theme.colorScheme.primary
                            : null,
                      ),
                      title: Text(character.name),
                      subtitle: Text(
                        [
                          if (character.description.trim().isNotEmpty)
                            character.description.trim(),
                          if (inChat) 'In this chat',
                          'Saved character — review before overwrite',
                        ].join('\n'),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      selected: isSelected,
                      onTap: busy
                          ? null
                          : () => setState(() => _selected = character),
                    );
                  },
                ),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _notesController,
              enabled: !busy,
              minLines: 2,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'What should change? (optional)',
                hintText:
                    'e.g. She cut her hair short and is more guarded now…',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: busy || _allCharacters.isEmpty || !_hasChatContext
                  ? null
                  : () => _updateFromChat(chatOnly: true),
              icon: _generating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.chat_bubble_outline),
              label: Text(
                _generating ? 'Updating…' : 'Update for this chat only',
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: busy || _allCharacters.isEmpty || !_hasChatContext
                  ? null
                  : () => _updateFromChat(chatOnly: false),
              icon: const Icon(Icons.save_outlined),
              label: const Text('Update saved card in library'),
            ),
          ],
        ),
      ),
    );
  }
}
