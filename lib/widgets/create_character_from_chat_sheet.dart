import 'package:flutter/material.dart';

import '../models/character.dart';
import '../models/chat_session.dart';
import '../models/global_lorebook.dart';
import '../models/persona.dart';
import '../screens/character_edit_screen.dart';
import '../services/character_service.dart';
import '../services/nanogpt_service.dart';
import '../services/persona_service.dart';
import '../services/settings_service.dart';
import '../services/world_info_service.dart';
import '../services/world_workshop_builder.dart';

/// Bottom sheet: create a character from the current chat context or start blank.
///
/// Optionally base the new card on another saved character / persona (shared
/// world material) in addition to the recent chat messages. Both references
/// are optional — leave them at "none" for the plain chat-based card.
Future<Character?> showCreateCharacterFromChatSheet({
  required BuildContext context,
  required ChatSession session,
  required List<Character> participants,
  required Persona? persona,
  required CharacterService characterService,
  required SettingsService settingsService,
  required NanoGptService nanoGptService,
  required WorldInfoService worldInfoService,
  PersonaService? personaService,
}) {
  return showModalBottomSheet<Character?>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _CreateCharacterFromChatSheet(
      session: session,
      participants: participants,
      persona: persona,
      characterService: characterService,
      settingsService: settingsService,
      nanoGptService: nanoGptService,
      worldInfoService: worldInfoService,
      personaService: personaService,
    ),
  );
}

class _CreateCharacterFromChatSheet extends StatefulWidget {
  const _CreateCharacterFromChatSheet({
    required this.session,
    required this.participants,
    required this.persona,
    required this.characterService,
    required this.settingsService,
    required this.nanoGptService,
    required this.worldInfoService,
    this.personaService,
  });

  final ChatSession session;
  final List<Character> participants;
  final Persona? persona;
  final CharacterService characterService;
  final SettingsService settingsService;
  final NanoGptService nanoGptService;
  final WorldInfoService worldInfoService;
  final PersonaService? personaService;

  @override
  State<_CreateCharacterFromChatSheet> createState() =>
      _CreateCharacterFromChatSheetState();
}

class _CreateCharacterFromChatSheetState
    extends State<_CreateCharacterFromChatSheet> {
  final _builder = WorldWorkshopBuilder();
  final _nameController = TextEditingController();

  List<GlobalLorebook> _linkedLorebooks = const [];
  List<Character> _allCharacters = const [];
  List<Persona> _allPersonas = const [];
  Character? _referenceCharacter;
  Persona? _referencePersona;
  bool _loadingData = true;
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
    _loadData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
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

    var personas = <Persona>[];
    final personaService = widget.personaService;
    if (personaService != null) {
      final loaded = await personaService.loadPersonas();
      personas = [
        for (final p in loaded)
          if (!p.isAnonymous && p.name.trim().isNotEmpty) p,
      ];
    }

    if (!mounted) return;
    setState(() {
      _linkedLorebooks = linked;
      _allCharacters = ordered;
      _allPersonas = personas;
      _loadingData = false;
    });
  }

  Future<void> _openCharacterEditor({Character? existing}) async {
    final saved = await Navigator.of(context, rootNavigator: true).push<Character>(
      MaterialPageRoute(
        builder: (_) => CharacterEditScreen(
          characterService: widget.characterService,
          settingsService: widget.settingsService,
          nanoGptService: widget.nanoGptService,
          existing: existing,
          generatedDraft: existing != null,
        ),
      ),
    );
    if (!mounted) return;
    Navigator.of(context).pop(saved);
  }

  Future<void> _chooseReferenceCharacter() async {
    final picked = await showModalBottomSheet<Object?>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  'Base the new card on…',
                  style: theme.textTheme.titleMedium,
                ),
              ),
              ListTile(
                leading: const Icon(Icons.block),
                title: const Text('No reference card'),
                subtitle: const Text('Plain chat-based card'),
                selected: _referenceCharacter == null,
                onTap: () => Navigator.pop(sheetContext, 'clear'),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: _allCharacters.length,
                  itemBuilder: (context, index) {
                    final character = _allCharacters[index];
                    final inChat = _participantIds.contains(character.id);
                    final isSelected = character.id == _referenceCharacter?.id;
                    return ListTile(
                      leading: Icon(
                        isSelected
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                        color: isSelected ? theme.colorScheme.primary : null,
                      ),
                      title: Text(character.name),
                      subtitle: Text(
                        [
                          if (inChat) 'In this chat',
                          'Shared reference card',
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      selected: isSelected,
                      onTap: () => Navigator.pop(sheetContext, character),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (!mounted) return;
    if (picked == 'clear') {
      setState(() => _referenceCharacter = null);
    } else if (picked is Character) {
      setState(() => _referenceCharacter = picked);
    }
  }

  Future<void> _chooseReferencePersona() async {
    final picked = await showModalBottomSheet<Object?>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  'Base the new card on…',
                  style: theme.textTheme.titleMedium,
                ),
              ),
              ListTile(
                leading: const Icon(Icons.block),
                title: const Text('No reference persona'),
                subtitle: const Text('Plain chat-based card'),
                selected: _referencePersona == null,
                onTap: () => Navigator.pop(sheetContext, 'clear'),
              ),
              if (_allPersonas.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('No saved personas yet.'),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    itemCount: _allPersonas.length,
                    itemBuilder: (context, index) {
                      final persona = _allPersonas[index];
                      final isSelected = persona.id == _referencePersona?.id;
                      return ListTile(
                        leading: Icon(
                          isSelected
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off,
                          color: isSelected ? theme.colorScheme.primary : null,
                        ),
                        title: Text(persona.name),
                        subtitle: Text(
                          'Persona — player identity reference',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        selected: isSelected,
                        onTap: () => Navigator.pop(sheetContext, persona),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (!mounted) return;
    if (picked == 'clear') {
      setState(() => _referencePersona = null);
    } else if (picked is Persona) {
      setState(() => _referencePersona = picked);
    }
  }

  Future<void> _generateFromChat() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter a character name.');
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
      final messages = _builder.buildChatCharacterExportMessagesWithReferences(
        session: widget.session,
        characters: widget.participants,
        characterName: name,
        persona: widget.persona,
        linkedLorebooks: _linkedLorebooks,
        buildPromptNote: build.promptNote,
        referenceCharacters: _referenceCharacter == null
            ? const <Character>[]
            : [_referenceCharacter!],
        referencePersonas: _referencePersona == null
            ? const <Persona>[]
            : [_referencePersona!],
      );
      final preferredId = widget.characterService.newId();

      Character? draft;
      for (var attempt = 0; attempt < 2; attempt++) {
        final cardRaw = await widget.nanoGptService.complete(
          model: build.model,
          messages: messages,
          baseUrl: baseUrl,
          sampling: build.sampling,
        );
        try {
          draft = _builder.parseCharacterJson(
            cardRaw,
            preferredId: preferredId,
            fallbackName: name,
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
      await _openCharacterEditor(existing: draft);
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
    final busy = _generating || _loadingData;

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
            Text('New character', style: theme.textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(
              _hasChatContext
                  ? 'Type a name from the story and let the AI fill the card '
                      'from recent messages. Optionally also base it on another '
                      'card or persona (each is optional).'
                  : 'Start a blank card, or chat a bit first to generate from context.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nameController,
              enabled: !busy,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Character name',
                hintText: 'e.g. Marcus, the innkeeper',
                border: OutlineInputBorder(),
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
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: busy || _allCharacters.isEmpty
                        ? null
                        : _chooseReferenceCharacter,
                    icon: const Icon(Icons.face_retouching_natural, size: 18),
                    label: Text(
                      _referenceCharacter == null
                          ? 'Reference card: none'
                          : _referenceCharacter!.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                if (widget.personaService != null) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: busy || _allPersonas.isEmpty
                          ? null
                          : _chooseReferencePersona,
                      icon: const Icon(Icons.person_outline, size: 18),
                      label: Text(
                        _referencePersona == null
                            ? 'Reference persona: none'
                            : _referencePersona!.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Optional — leave both at none for a plain chat-based card.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: busy || !_hasChatContext ? null : _generateFromChat,
              icon: _generating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_awesome),
              label: Text(
                _generating ? 'Generating card…' : 'Generate from chat',
              ),
            ),
            TextButton(
              onPressed: busy ? null : () => _openCharacterEditor(),
              child: const Text('Start blank card instead'),
            ),
          ],
        ),
      ),
    );
  }
}
