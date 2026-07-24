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

/// Enough room for a full ST V2 card even when global max tokens is low.
SamplingSettings _jsonGenerationSampling(SamplingSettings base) {
  const floor = 4096;
  final max = base.maxTokens;
  if (max == null || max < floor) {
    return base.copyWith(maxTokens: floor);
  }
  return base;
}

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
  final _summaryByName = <String, String>{};

  List<GlobalLorebook> _linkedLorebooks = const [];
  List<WorkshopCharacterCandidate> _candidates = const [];
  bool _loadingLore = true;
  bool _scanning = false;
  bool _generating = false;
  String? _error;
  String? _selectedSummary;

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
    if (_hasChatContext) {
      await _scanChat(quiet: true);
    }
  }

  Future<void> _scanChat({bool quiet = false}) async {
    if (!_hasChatContext) {
      if (!quiet && mounted) {
        setState(() {
          _error = 'Chat a bit first, then scan for characters.';
        });
      }
      return;
    }

    setState(() {
      _scanning = true;
      _error = null;
    });

    try {
      final collaborator = await widget.settingsService.getCollaboratorSettings();
      final model = await widget.settingsService.getModel();
      final sampling = _jsonGenerationSampling(
        await widget.settingsService.getSampling(),
      );
      final baseUrl = await widget.settingsService.getApiBaseUrl();

      final raw = await widget.nanoGptService.complete(
        model: model,
        messages: _builder.buildChatCharacterDetectMessages(
          session: widget.session,
          characters: widget.participants,
          persona: widget.persona,
          linkedLorebooks: _linkedLorebooks,
          guidanceNote: collaborator.guidanceNote,
        ),
        baseUrl: baseUrl,
        sampling: sampling,
      );

      final candidates = _builder.parseCharacterCandidatesJson(raw);
      if (!mounted) return;
      setState(() {
        _candidates = candidates;
        _summaryByName
          ..clear()
          ..addEntries(
            candidates.map(
              (c) => MapEntry(c.name.trim().toLowerCase(), c.summary),
            ),
          );
        _scanning = false;
        if (candidates.isEmpty && !quiet) {
          _error =
              'No clear characters found. Type a name and generate, or start blank.';
        }
      });
    } on FormatException catch (error) {
      if (!mounted) return;
      setState(() {
        _scanning = false;
        _error = error.message;
      });
    } on NanoGptException catch (error) {
      if (!mounted) return;
      setState(() {
        _scanning = false;
        _error = error.message;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _scanning = false;
        _error = '$error';
      });
    }
  }

  void _pickCandidate(WorkshopCharacterCandidate candidate) {
    _nameController.text = candidate.name;
    setState(() {
      _selectedSummary = candidate.summary;
      _error = null;
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
      setState(() => _error = 'Enter a character name (or pick one below).');
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
      final collaborator = await widget.settingsService.getCollaboratorSettings();
      final model = await widget.settingsService.getModel();
      final sampling = _jsonGenerationSampling(
        await widget.settingsService.getSampling(),
      );
      final baseUrl = await widget.settingsService.getApiBaseUrl();
      final summary =
          _selectedSummary ?? _summaryByName[name.toLowerCase()] ?? '';
      final messages = _builder.buildChatCharacterExportMessages(
        session: widget.session,
        characters: widget.participants,
        characterName: name,
        characterSummary: summary,
        persona: widget.persona,
        linkedLorebooks: _linkedLorebooks,
        guidanceNote: collaborator.guidanceNote,
      );
      final preferredId = widget.characterService.newId();

      Character? draft;
      for (var attempt = 0; attempt < 2; attempt++) {
        final cardRaw = await widget.nanoGptService.complete(
          model: model,
          messages: messages,
          baseUrl: baseUrl,
          sampling: sampling,
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
    final busy = _scanning || _generating || _loadingLore;

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
                  ? 'Type a name from the story, scan the chat for suggestions, '
                      'or let the AI fill the card from what was said so far.'
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
            if (_candidates.isNotEmpty) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Found in chat',
                  style: theme.textTheme.labelLarge,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final candidate in _candidates)
                    ActionChip(
                      label: Text(candidate.name),
                      tooltip: candidate.summary.isEmpty
                          ? null
                          : candidate.summary,
                      onPressed: busy
                          ? null
                          : () => _pickCandidate(candidate),
                    ),
                ],
              ),
            ],
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
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: busy || !_hasChatContext ? null : () => _scanChat(),
              icon: _scanning
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.search),
              label: Text(_scanning ? 'Scanning chat…' : 'Scan chat for names'),
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
