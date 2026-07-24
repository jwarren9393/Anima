import 'dart:convert';

import 'package:flutter/material.dart';

import '../models/character.dart';
import '../models/chat_message.dart';
import '../models/global_lorebook.dart';
import '../models/persona.dart';
import '../models/world_workshop.dart';
import '../services/character_service.dart';
import '../services/chat_context_service.dart';
import '../services/nanogpt_service.dart';
import '../services/persona_service.dart';
import '../services/settings_service.dart';
import '../services/world_info_service.dart';
import '../services/world_workshop_builder.dart';
import '../services/world_workshop_service.dart';
import '../widgets/keyboard_inset.dart';
import 'character_edit_screen.dart';
import 'persona_edit_screen.dart';

/// Plain chat with the World Info collaborator; export lorebook / characters.
class WorldWorkshopChatScreen extends StatefulWidget {
  const WorldWorkshopChatScreen({
    super.key,
    required this.workshop,
    required this.workshopService,
    required this.worldInfoService,
    required this.characterService,
    required this.personaService,
    required this.settingsService,
    required this.nanoGptService,
  });

  final WorldWorkshop workshop;
  final WorldWorkshopService workshopService;
  final WorldInfoService worldInfoService;
  final CharacterService characterService;
  final PersonaService personaService;
  final SettingsService settingsService;
  final NanoGptService nanoGptService;

  @override
  State<WorldWorkshopChatScreen> createState() =>
      _WorldWorkshopChatScreenState();
}

class _WorldWorkshopChatScreenState extends State<WorldWorkshopChatScreen>
    with WidgetsBindingObserver {
  final _builder = WorldWorkshopBuilder();
  final _contextService = const ChatContextService();

  final _input = TextEditingController();
  final _scroll = ScrollController();
  late WorldWorkshop _workshop;
  GlobalLorebook? _linkedLorebook;
  bool _loadingLinkedLorebook = false;
  int? _modelContextLength;
  String _modelId = '';
  bool _sending = false;
  bool _exporting = false;
  String? _exportStatus;
  double _keyboardInset = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _workshop = widget.workshop;
    _loadLinkedLorebook();
    _loadModelContext();
  }

  Future<void> _loadLinkedLorebook() async {
    final id = _workshop.exportedLorebookId;
    if (id == null || id.isEmpty) return;
    setState(() => _loadingLinkedLorebook = true);
    final linked = await widget.worldInfoService.getById(id);
    if (!mounted) return;
    setState(() {
      _linkedLorebook = linked;
      _loadingLinkedLorebook = false;
    });
  }

  Future<void> _loadModelContext() async {
    try {
      final modelId = await widget.settingsService.getModel();
      final baseUrl = await widget.settingsService.getApiBaseUrl();
      final models = await widget.nanoGptService.listModels(baseUrl: baseUrl);
      if (!mounted) return;
      int? contextLength;
      for (final model in models) {
        if (model.id == modelId) {
          contextLength = model.contextLength;
          break;
        }
      }
      setState(() {
        _modelId = modelId;
        _modelContextLength = contextLength;
      });
    } catch (_) {
      // Context length is optional UI polish.
    }
  }

  bool get _hasSourceMaterial =>
      _workshop.messages.isNotEmpty ||
      _linkedLorebook != null ||
      (_workshop.importedSource?.hasContent ?? false);

  ContextEstimate get _estimate {
    final loreJson = _linkedLorebook == null
        ? ''
        : const JsonEncoder().convert(_linkedLorebook!.book.toJson());
    final imported = _workshop.importedSource?.promptText ?? '';
    return _contextService.estimateWorkshop(
      messages: _workshop.messages,
      linkedLorebookJson: loreJson,
      importedSourceText: imported,
      modelContextLength: _modelContextLength,
    );
  }

  Future<void> _showContextEstimate() async {
    final estimate = _estimate;
    final ratio = estimate.fillRatio;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Context estimate'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Rough estimate only (≈ 1 token per 4 characters). '
                'Useful for spotting when a long workshop may start dropping early details.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              Text('Messages: ${estimate.messageCount}'),
              Text(
                'Chat transcript: ~${ContextEstimate.formatTokenCount(estimate.fullTranscriptTokens)} tokens',
              ),
              if (estimate.memoryTokens > 0)
                Text(
                  'Imported chat source: ~${ContextEstimate.formatTokenCount(estimate.memoryTokens)} tokens',
                ),
              if (estimate.loreTokens > 0)
                Text(
                  'Linked lorebook: ~${ContextEstimate.formatTokenCount(estimate.loreTokens)} tokens',
                ),
              Text(
                'Estimated send size: ~${ContextEstimate.formatTokenCount(estimate.estimatedSentTokens)} tokens',
              ),
              if (_modelId.isNotEmpty) Text('Current model: $_modelId'),
              if (estimate.modelContextLength != null)
                Text(
                  'Model context: ${ContextEstimate.formatTokenCount(estimate.modelContextLength!)} tokens'
                  '${ratio == null ? '' : ' (~${(ratio * 100).round()}% used)'}',
                )
              else
                const Text(
                  'Model context: unknown (refresh models in API settings after picking a catalog model).',
                ),
              if (estimate.notes.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(estimate.notes),
              ],
              if (ratio != null && ratio >= 0.85) ...[
                const SizedBox(height: 12),
                Text(
                  'Getting full — consider Update lorebook soon so early details stay in World Info.',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  void didChangeMetrics() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final inset = MediaQuery.viewInsetsOf(context).bottom;
      if (inset > _keyboardInset + 8) {
        _scrollToEnd();
      }
      _keyboardInset = inset;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _persist(WorldWorkshop workshop) async {
    final saved = await widget.workshopService.upsert(workshop);
    if (!mounted) return;
    setState(() => _workshop = saved);
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending || _exporting || _loadingLinkedLorebook) {
      return;
    }

    final userMessage = ChatMessage(
      id: ChatMessage.newId(),
      role: ChatRole.user,
      text: text,
    );
    final messages = [..._workshop.messages, userMessage];
    var title = _workshop.title;
    if (title == 'New workshop' || title.trim().isEmpty) {
      title = _builder.suggestTitle(messages);
    }

    _input.clear();
    setState(() {
      _sending = true;
      _workshop = _workshop.copyWith(messages: messages, title: title);
    });
    await _persist(_workshop);
    _scrollToEnd();

    final assistantId = ChatMessage.newId();
    final placeholder = ChatMessage(
      id: assistantId,
      role: ChatRole.assistant,
      text: '',
    );
    setState(() {
      _workshop = _workshop.copyWith(
        messages: [..._workshop.messages, placeholder],
      );
    });

    try {
      final collaborator = await widget.settingsService
          .getCollaboratorSettings();
      final model = await widget.settingsService.getModel();
      final sampling = await widget.settingsService.getSampling();
      final baseUrl = await widget.settingsService.getApiBaseUrl();

      final apiMessages = <Map<String, String>>[
        {
          'role': 'system',
          'content': _builder.chatSystemPrompt(
            guidanceNote: collaborator.guidanceNote,
            sourceLorebook: _linkedLorebook?.book,
            importedSource: _workshop.importedSource,
          ),
        },
        for (final message in messages) message.toApiMap(),
      ];

      final buffer = StringBuffer();
      await for (final chunk in widget.nanoGptService.streamCompletion(
        model: model,
        messages: apiMessages,
        baseUrl: baseUrl,
        sampling: sampling,
      )) {
        if (!mounted) return;
        buffer.write(chunk);
        final updated = List<ChatMessage>.from(_workshop.messages);
        final index = updated.indexWhere((m) => m.id == assistantId);
        if (index < 0) continue;
        updated[index] = updated[index].withEditedText(buffer.toString());
        setState(() {
          _workshop = _workshop.copyWith(messages: updated);
        });
        _scrollToEnd();
      }

      await _persist(_workshop);
    } on NanoGptCancelledException {
      final updated = List<ChatMessage>.from(_workshop.messages);
      final index = updated.indexWhere((m) => m.id == assistantId);
      if (index >= 0) {
        final text = updated[index].text.trim();
        if (text.isEmpty) {
          updated.removeAt(index);
        }
        await _persist(_workshop.copyWith(messages: updated));
      }
    } on NanoGptException catch (error) {
      if (!mounted) return;
      _removeEmptyAssistant(assistantId);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (error) {
      if (!mounted) return;
      _removeEmptyAssistant(assistantId);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Something went wrong: $error')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _removeEmptyAssistant(String assistantId) async {
    final updated = List<ChatMessage>.from(_workshop.messages);
    final index = updated.indexWhere((m) => m.id == assistantId);
    if (index < 0) return;
    if (updated[index].text.trim().isEmpty) {
      updated.removeAt(index);
      await _persist(_workshop.copyWith(messages: updated));
    }
  }

  void _stop() {
    widget.nanoGptService.cancelActiveStream();
  }

  Future<void> _createLorebook() async {
    if (_sending || _exporting || _loadingLinkedLorebook) return;
    if (_workshop.exportedLorebookId != null && _linkedLorebook == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'The linked World Info lorebook is missing. Import or link it again.',
          ),
        ),
      );
      return;
    }
    if (!_hasSourceMaterial) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Chat a bit first (or import a roleplay chat), then create the lorebook.',
          ),
        ),
      );
      return;
    }

    setState(() {
      _exporting = true;
      _exportStatus = 'Creating lorebook…';
    });
    try {
      final collaborator = await widget.settingsService
          .getCollaboratorSettings();
      final model = await widget.settingsService.getModel();
      final sampling = await widget.settingsService.getSampling();
      final baseUrl = await widget.settingsService.getApiBaseUrl();

      final raw = await widget.nanoGptService.complete(
        model: model,
        messages: _builder.buildExportMessages(
          conversation: _workshop.messages,
          guidanceNote: collaborator.guidanceNote,
          sourceLorebook: _linkedLorebook?.book,
          importedSource: _workshop.importedSource,
        ),
        baseUrl: baseUrl,
        sampling: sampling,
      );

      final book = _builder.parseLorebookJson(raw);
      final existingId = _workshop.exportedLorebookId;
      final global = GlobalLorebook(
        id: (existingId != null && existingId.isNotEmpty)
            ? existingId
            : GlobalLorebook.newId(),
        enabled: _linkedLorebook?.enabled ?? true,
        book: book,
      );
      await widget.worldInfoService.upsert(global);
      if (mounted) {
        setState(() => _linkedLorebook = global);
      }

      final title = book.name.trim().isEmpty
          ? _workshop.title
          : book.name.trim();
      await _persist(
        _workshop.copyWith(title: title, exportedLorebookId: global.id),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Saved “${global.displayName}” (${book.entries.length} entries) '
            'to World Info.',
          ),
        ),
      );
    } on FormatException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } on NanoGptException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not create lorebook: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _exporting = false;
          _exportStatus = null;
        });
      }
    }
  }

  Future<void> _createCharacters() async {
    if (_sending || _exporting || _loadingLinkedLorebook) return;
    if (_workshop.exportedLorebookId != null && _linkedLorebook == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'The linked World Info lorebook is missing. Import or link it again.',
          ),
        ),
      );
      return;
    }
    if (!_hasSourceMaterial) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Chat a bit first, then create characters.'),
        ),
      );
      return;
    }

    setState(() {
      _exporting = true;
      _exportStatus = 'Finding characters…';
    });

    try {
      final collaborator = await widget.settingsService
          .getCollaboratorSettings();
      final model = await widget.settingsService.getModel();
      final sampling = await widget.settingsService.getSampling();
      final baseUrl = await widget.settingsService.getApiBaseUrl();
      final existingChars = await widget.characterService.loadCharacters();
      final existingNames = {
        for (final c in existingChars) c.name.trim().toLowerCase(),
      };

      final detectRaw = await widget.nanoGptService.complete(
        model: model,
        messages: _builder.buildCharacterDetectMessages(
          conversation: _workshop.messages,
          guidanceNote: collaborator.guidanceNote,
          sourceLorebook: _linkedLorebook?.book,
          importedSource: _workshop.importedSource,
        ),
        baseUrl: baseUrl,
        sampling: sampling,
      );

      final candidates = _builder.parseCharacterCandidatesJson(detectRaw);
      if (!mounted) return;

      if (candidates.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No clear characters found yet. Chat more about people, then try again.',
            ),
          ),
        );
        return;
      }

      setState(() {
        _exporting = false;
        _exportStatus = null;
      });

      final selected = await _pickCandidates(
        candidates: candidates,
        existingNames: existingNames,
      );
      if (!mounted || selected == null || selected.isEmpty) return;

      setState(() {
        _exporting = true;
        _exportStatus = 'Generating characters…';
      });

      var savedCount = 0;
      var skippedCount = 0;
      final build = await widget.settingsService.resolveCharacterBuild();

      for (var i = 0; i < selected.length; i++) {
        if (!mounted) return;
        final candidate = selected[i];
        setState(() {
          _exportStatus =
              'Generating ${i + 1} of ${selected.length}: ${candidate.name}…';
        });

        try {
          final cardRaw = await widget.nanoGptService.complete(
            model: build.model,
            messages: _builder.buildCharacterExportMessages(
              conversation: _workshop.messages,
              characterName: candidate.name,
              characterSummary: candidate.summary,
              buildPromptNote: build.promptNote,
              sourceLorebook: _linkedLorebook?.book,
              importedSource: _workshop.importedSource,
            ),
            baseUrl: baseUrl,
            sampling: build.sampling,
          );

          final draft = _builder.parseCharacterJson(
            cardRaw,
            preferredId: widget.characterService.newId(),
            fallbackName: candidate.name,
          );

          if (!mounted) return;
          setState(() {
            _exporting = false;
            _exportStatus = null;
          });

          final saved = await Navigator.of(context).push<Character>(
            MaterialPageRoute(
              builder: (_) => CharacterEditScreen(
                characterService: widget.characterService,
                settingsService: widget.settingsService,
                nanoGptService: widget.nanoGptService,
                existing: draft,
                generatedDraft: true,
              ),
            ),
          );

          if (saved != null) {
            savedCount++;
          } else {
            skippedCount++;
          }
        } on FormatException catch (error) {
          if (!mounted) return;
          skippedCount++;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${candidate.name}: ${error.message}'),
              backgroundColor: Theme.of(
                context,
              ).colorScheme.surfaceContainerHigh,
            ),
          );
        } on NanoGptException catch (error) {
          if (!mounted) return;
          skippedCount++;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${candidate.name}: ${error.message}'),
              backgroundColor: Theme.of(
                context,
              ).colorScheme.surfaceContainerHigh,
            ),
          );
        }

        if (!mounted) return;
        // Resume busy state between cards when more remain.
        if (i < selected.length - 1) {
          setState(() {
            _exporting = true;
            _exportStatus = 'Generating ${i + 2} of ${selected.length}…';
          });
        }
      }

      if (!mounted) return;
      final parts = <String>[];
      if (savedCount > 0) {
        parts.add('Saved $savedCount character${savedCount == 1 ? '' : 's'}');
      }
      if (skippedCount > 0) {
        parts.add('skipped $skippedCount');
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            parts.isEmpty ? 'No characters saved.' : parts.join(' · '),
          ),
        ),
      );
    } on FormatException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } on NanoGptException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not create characters: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _exporting = false;
          _exportStatus = null;
        });
      }
    }
  }

  Future<void> _updateExistingCharacter() async {
    if (_sending || _exporting || _loadingLinkedLorebook) return;
    if (_workshop.exportedLorebookId != null && _linkedLorebook == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'The linked World Info lorebook is missing. Import or link it again.',
          ),
        ),
      );
      return;
    }
    if (!_hasSourceMaterial) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Chat a bit first (or import a roleplay chat), then update a character.',
          ),
        ),
      );
      return;
    }

    setState(() {
      _exporting = true;
      _exportStatus = 'Loading characters…';
    });

    try {
      final existingChars = await widget.characterService.loadCharacters();
      if (!mounted) return;
      if (existingChars.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No saved characters yet. Create one first, then update it here.',
            ),
          ),
        );
        return;
      }

      final ordered = _builder.prioritizeCharactersForUpdate(
        characters: existingChars,
        importedSource: _workshop.importedSource,
      );

      setState(() {
        _exporting = false;
        _exportStatus = null;
      });

      final selected = await _pickExistingCharacter(ordered);
      if (!mounted || selected == null) return;

      setState(() {
        _exporting = true;
        _exportStatus = 'Updating ${selected.name}…';
      });

      final build = await widget.settingsService.resolveCharacterBuild();
      final baseUrl = await widget.settingsService.getApiBaseUrl();

      final cardRaw = await widget.nanoGptService.complete(
        model: build.model,
        messages: _builder.buildCharacterUpdateMessages(
          conversation: _workshop.messages,
          existing: selected,
          buildPromptNote: build.promptNote,
          sourceLorebook: _linkedLorebook?.book,
          importedSource: _workshop.importedSource,
        ),
        baseUrl: baseUrl,
        sampling: build.sampling,
      );

      final draft = _builder.parseCharacterUpdateJson(
        cardRaw,
        original: selected,
      );

      if (!mounted) return;
      setState(() {
        _exporting = false;
        _exportStatus = null;
      });

      final saved = await Navigator.of(context).push<Character>(
        MaterialPageRoute(
          builder: (_) => CharacterEditScreen(
            characterService: widget.characterService,
            settingsService: widget.settingsService,
            nanoGptService: widget.nanoGptService,
            existing: draft,
            generatedDraft: true,
            updatingExisting: true,
          ),
        ),
      );

      if (!mounted) return;
      if (saved != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Updated “${saved.name}”.')),
        );
      }
    } on FormatException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } on NanoGptException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update character: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _exporting = false;
          _exportStatus = null;
        });
      }
    }
  }

  Future<Character?> _pickExistingCharacter(List<Character> characters) async {
    return showModalBottomSheet<Character>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        final theme = Theme.of(context);
        final maxHeight = MediaQuery.sizeOf(context).height * 0.7;
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
                    'Update existing character',
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: Text(
                    'Choose a saved card to revise from this workshop. '
                    'You’ll review the merge before it overwrites the original.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: characters.length,
                    itemBuilder: (context, index) {
                      final character = characters[index];
                      final fromImport = _builder.isImportedChatCharacter(
                        character,
                        _workshop.importedSource,
                      );
                      return ListTile(
                        leading: const Icon(Icons.person_outline),
                        title: Text(character.name),
                        subtitle: Text(
                          [
                            if (character.description.trim().isNotEmpty)
                              character.description.trim(),
                            if (fromImport) 'In imported chat',
                          ].join('\n'),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => Navigator.pop(context, character),
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
  }

  Future<void> _createPersona() async {
    if (_sending || _exporting || _loadingLinkedLorebook) return;
    if (_workshop.exportedLorebookId != null && _linkedLorebook == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'The linked World Info lorebook is missing. Import or link it again.',
          ),
        ),
      );
      return;
    }
    if (!_hasSourceMaterial) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Chat a bit first, then create a persona.'),
        ),
      );
      return;
    }

    setState(() {
      _exporting = true;
      _exportStatus = 'Finding persona candidates…';
    });

    try {
      final collaborator = await widget.settingsService
          .getCollaboratorSettings();
      final model = await widget.settingsService.getModel();
      final sampling = await widget.settingsService.getSampling();
      final baseUrl = await widget.settingsService.getApiBaseUrl();
      final existingPersonas = await widget.personaService.loadPersonas();
      final existingNames = {
        for (final p in existingPersonas) p.name.trim().toLowerCase(),
      };

      final detectRaw = await widget.nanoGptService.complete(
        model: model,
        messages: _builder.buildCharacterDetectMessages(
          conversation: _workshop.messages,
          guidanceNote: collaborator.guidanceNote,
          sourceLorebook: _linkedLorebook?.book,
          importedSource: _workshop.importedSource,
        ),
        baseUrl: baseUrl,
        sampling: sampling,
      );
      final candidates = _builder.parseCharacterCandidatesJson(detectRaw);
      if (!mounted) return;
      if (candidates.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No clear people found yet. Add more about your player character, then try again.',
            ),
          ),
        );
        return;
      }

      setState(() {
        _exporting = false;
        _exportStatus = null;
      });
      final selected = await _pickPersonaCandidate(
        candidates: candidates,
        existingNames: existingNames,
      );
      if (!mounted || selected == null) return;

      setState(() {
        _exporting = true;
        _exportStatus = 'Generating persona: ${selected.name}…';
      });
      final personaRaw = await widget.nanoGptService.complete(
        model: model,
        messages: _builder.buildPersonaExportMessages(
          conversation: _workshop.messages,
          personaName: selected.name,
          personaSummary: selected.summary,
          guidanceNote: collaborator.guidanceNote,
          sourceLorebook: _linkedLorebook?.book,
          importedSource: _workshop.importedSource,
        ),
        baseUrl: baseUrl,
        sampling: sampling,
      );
      final draft = _builder.parsePersonaJson(
        personaRaw,
        preferredId: widget.personaService.newId(),
        fallbackName: selected.name,
      );
      if (!mounted) return;
      setState(() {
        _exporting = false;
        _exportStatus = null;
      });

      final saved = await Navigator.of(context).push<Persona>(
        MaterialPageRoute(
          builder: (_) => PersonaEditScreen(
            personaService: widget.personaService,
            settingsService: widget.settingsService,
            nanoGptService: widget.nanoGptService,
            existing: draft,
            generatedDraft: true,
          ),
        ),
      );
      if (!mounted || saved == null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved ${saved.name} to Personas.')),
      );
    } on FormatException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } on NanoGptException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not create persona: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _exporting = false;
          _exportStatus = null;
        });
      }
    }
  }

  Future<WorkshopCharacterCandidate?> _pickPersonaCandidate({
    required List<WorkshopCharacterCandidate> candidates,
    required Set<String> existingNames,
  }) async {
    WorkshopCharacterCandidate? selected = candidates.length == 1
        ? candidates.first
        : null;
    return showModalBottomSheet<WorkshopCharacterCandidate>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final theme = Theme.of(context);
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Create your persona',
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Choose the person you will play. Anima will generate '
                      'player-focused fields, then let you review everything '
                      'before saving.',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.sizeOf(context).height * 0.5,
                      ),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: candidates.length,
                        itemBuilder: (context, index) {
                          final candidate = candidates[index];
                          final exists = existingNames.contains(
                            candidate.name.trim().toLowerCase(),
                          );
                          final isSelected = identical(selected, candidate);
                          return ListTile(
                            leading: Icon(
                              isSelected
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_off,
                              color: isSelected
                                  ? Theme.of(context).colorScheme.primary
                                  : null,
                            ),
                            title: Text(candidate.name),
                            subtitle: Text(
                              [
                                if (candidate.summary.isNotEmpty)
                                  candidate.summary,
                                if (exists)
                                  'A persona with this name already exists; saving creates another.',
                              ].join('\n'),
                            ),
                            selected: isSelected,
                            onTap: () {
                              setSheetState(() => selected = candidate);
                            },
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancel'),
                        ),
                        const Spacer(),
                        FilledButton(
                          onPressed: selected == null
                              ? null
                              : () => Navigator.pop(context, selected),
                          child: const Text('Generate persona'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<List<WorkshopCharacterCandidate>?> _pickCandidates({
    required List<WorkshopCharacterCandidate> candidates,
    required Set<String> existingNames,
  }) async {
    final selected = <String>{
      for (final c in candidates)
        if (!existingNames.contains(c.name.trim().toLowerCase()))
          c.name.trim().toLowerCase(),
    };
    // If everything already exists, still preselect all so the user can
    // intentionally create another version.
    if (selected.isEmpty) {
      selected.addAll(candidates.map((c) => c.name.trim().toLowerCase()));
    }

    return showModalBottomSheet<List<WorkshopCharacterCandidate>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final theme = Theme.of(context);
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
                    Text(
                      'Create characters',
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Choose who to turn into playable character cards. '
                      'You’ll review each card before it’s saved.',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.sizeOf(context).height * 0.5,
                      ),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: candidates.length,
                        itemBuilder: (context, index) {
                          final candidate = candidates[index];
                          final key = candidate.name.trim().toLowerCase();
                          final exists = existingNames.contains(key);
                          final checked = selected.contains(key);
                          return CheckboxListTile(
                            value: checked,
                            onChanged: (value) {
                              setSheetState(() {
                                if (value == true) {
                                  selected.add(key);
                                } else {
                                  selected.remove(key);
                                }
                              });
                            },
                            title: Text(candidate.name),
                            subtitle: Text(
                              [
                                if (candidate.summary.isNotEmpty)
                                  candidate.summary,
                                if (exists)
                                  'Already in Characters (new card won’t overwrite)',
                              ].join('\n'),
                            ),
                            controlAffinity: ListTileControlAffinity.leading,
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancel'),
                        ),
                        const Spacer(),
                        FilledButton(
                          onPressed: selected.isEmpty
                              ? null
                              : () {
                                  final chosen = candidates
                                      .where(
                                        (c) => selected.contains(
                                          c.name.trim().toLowerCase(),
                                        ),
                                      )
                                      .toList();
                                  Navigator.pop(context, chosen);
                                },
                          child: Text('Generate (${selected.length})'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _showImportedSourceDetails() async {
    final source = _workshop.importedSource;
    if (source == null) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Imported: ${source.chatTitle}'),
        content: SingleChildScrollView(
          child: SelectableText(
            source.promptText,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _importedSourceCard(ThemeData theme) {
    final source = _workshop.importedSource;
    if (source == null || !source.hasContent) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Material(
        color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: _showImportedSourceDetails,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(
                  Icons.forum_outlined,
                  color: theme.colorScheme.onSecondaryContainer,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Imported from chat',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: theme.colorScheme.onSecondaryContainer,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${source.chatTitle} · ${source.compactSummary}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSecondaryContainer,
                        ),
                      ),
                      if (source.skippedNotes.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          '${source.skippedNotes.length} missing reference'
                          '${source.skippedNotes.length == 1 ? '' : 's'} skipped',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: theme.colorScheme.onSecondaryContainer,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final busy = _sending || _exporting || _loadingLinkedLorebook;
    final linkedName = _linkedLorebook?.displayName;
    final imported = _workshop.importedSource;
    final hasImported = imported?.hasContent ?? false;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: Text(_workshop.title),
        actions: [
          IconButton(
            tooltip: 'Context estimate',
            onPressed: _showContextEstimate,
            icon: const Icon(Icons.data_usage_outlined),
          ),
          PopupMenuButton<String>(
            tooltip: 'Create people',
            enabled: !busy,
            onSelected: (value) {
              if (value == 'characters') _createCharacters();
              if (value == 'update') _updateExistingCharacter();
              if (value == 'persona') _createPersona();
            },
            icon:
                _exporting &&
                    (_exportStatus?.contains('character') == true ||
                        _exportStatus?.contains('persona') == true ||
                        _exportStatus?.contains('Finding') == true ||
                        _exportStatus?.contains('Generating') == true ||
                        _exportStatus?.contains('Updating') == true)
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.person_add_alt_1),
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'characters',
                child: ListTile(
                  leading: Icon(Icons.groups_outlined),
                  title: Text('Create AI characters'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'update',
                child: ListTile(
                  leading: Icon(Icons.person_search_outlined),
                  title: Text('Update existing character'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'persona',
                child: ListTile(
                  leading: Icon(Icons.person_outline),
                  title: Text('Create my persona'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
          TextButton(
            onPressed: busy ? null : _createLorebook,
            child:
                _exporting &&
                    (_exportStatus == null ||
                        _exportStatus!.contains('lorebook'))
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    _workshop.exportedLorebookId == null
                        ? 'Create lorebook'
                        : 'Update lorebook',
                  ),
          ),
        ],
      ),
      body: KeyboardInset(
        child: Column(
          children: [
            Material(
              color: theme.colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.5,
              ),
              child: InkWell(
                onTap: _showContextEstimate,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        _exportStatus ??
                            (linkedName != null
                                ? 'Linked to “$linkedName” '
                                    '(${_linkedLorebook!.entryCount} entries). '
                                    'Chat to revise it, Update lorebook to save changes, '
                                    'or create character cards from it.'
                                : hasImported
                                    ? 'Seeded from “${imported!.chatTitle}”. '
                                        'Chat to refine ideas, then Create lorebook, '
                                        'Create AI characters, or Update existing character.'
                                    : 'Talk about your world. Use Create lorebook for World Info, '
                                        'or the person+ icon to create/update character cards.'),
                        style: theme.textTheme.bodySmall,
                      ),
                      if (_exportStatus == null) ...[
                        const SizedBox(height: 6),
                        Text(
                          _estimate.compactBannerLine,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: (_estimate.fillRatio ?? 0) >= 0.85
                                ? theme.colorScheme.error
                                : Theme.of(context).colorScheme.tertiary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            _importedSourceCard(theme),
            Expanded(
              child: _workshop.messages.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          linkedName != null
                              ? 'This workshop is ready to use “$linkedName”.\n\n'
                                  'Ask the AI to explain, expand, rewrite, or reorganize '
                                  'the lorebook—or create characters directly.'
                              : hasImported
                                  ? 'Your imported chat is ready as source material.\n\n'
                                      'Ask the AI what to extract into a lorebook, or tap '
                                      'Create lorebook / the person+ icon when you’re ready.'
                                  : 'Example: “I want a rainy coastal city with rival '
                                      'guilds and a buried god under the harbor…”',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.all(16),
                      itemCount: _workshop.messages.length,
                      itemBuilder: (context, index) {
                        final message = _workshop.messages[index];
                        final isUser = message.isUser;
                        return Align(
                          alignment: isUser
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            constraints: BoxConstraints(
                              maxWidth: MediaQuery.sizeOf(context).width * 0.85,
                            ),
                            decoration: BoxDecoration(
                              color: isUser
                                  ? theme.colorScheme.primaryContainer
                                  : theme.colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Text(
                              message.text.isEmpty && !isUser && _sending
                                  ? '…'
                                  : message.text,
                              style: theme.textTheme.bodyMedium,
                            ),
                          ),
                        );
                      },
                    ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _input,
                        minLines: 1,
                        maxLines: 5,
                        textCapitalization: TextCapitalization.sentences,
                        enabled: !_exporting,
                        decoration: const InputDecoration(
                          hintText: 'Describe your world…',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        onSubmitted: (_) {
                          if (_sending) {
                            _stop();
                          } else {
                            _send();
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: _exporting ? null : (_sending ? _stop : _send),
                      icon: Icon(_sending ? Icons.stop : Icons.send),
                      tooltip: _sending ? 'Stop' : 'Send',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
