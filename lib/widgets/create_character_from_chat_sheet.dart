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

/// Bottom sheet: create a character from the current chat context or start blank.
Future<Character?> showCreateCharacterFromChatSheet({
  required BuildContext context,
  required ChatSession session,
  required List<Character> participants,
  required Persona? persona,
  required CharacterService characterService,
  required SettingsService settingsService,
  required NanoGptService nanoGptService,
  required WorldInfoService worldInfoService,
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
  });

  final ChatSession session;
  final List<Character> participants;
  final Persona? persona;
  final CharacterService characterService;
  final SettingsService settingsService;
  final NanoGptService nanoGptService;
  final WorldInfoService worldInfoService;

  @override
  State<_CreateCharacterFromChatSheet> createState() =>
      _CreateCharacterFromChatSheetState();
}

class _CreateCharacterFromChatSheetState
    extends State<_CreateCharacterFromChatSheet> {
  final _builder = WorldWorkshopBuilder();
  final _nameController = TextEditingController();

  List<GlobalLorebook> _linkedLorebooks = const [];
  bool _loadingLore = true;
  bool _generating = false;
  String? _error;

  bool get _hasChatContext =>
      widget.session.messages.any((m) => m.text.trim().isNotEmpty) ||
      widget.session.memorySummary.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _loadLorebooks();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadLorebooks() async {
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
    if (!mounted) return;
    setState(() {
      _linkedLorebooks = linked;
      _loadingLore = false;
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
      final messages = _builder.buildChatCharacterExportMessages(
        session: widget.session,
        characters: widget.participants,
        characterName: name,
        persona: widget.persona,
        linkedLorebooks: _linkedLorebooks,
        buildPromptNote: build.promptNote,
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
    final busy = _generating || _loadingLore;

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
                      'from what was said so far.'
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
            const SizedBox(height: 16),
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
