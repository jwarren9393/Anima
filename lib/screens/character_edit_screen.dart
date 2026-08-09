import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/character.dart';
import '../models/lorebook.dart';
import '../services/avatar_prompt_builder.dart';
import '../services/avatar_service.dart';
import '../services/character_collaborator.dart';
import '../services/character_service.dart';
import '../services/character_token_service.dart';
import '../services/ai_field_changes.dart';
import '../services/nanogpt_service.dart';
import '../services/settings_service.dart';
import '../services/world_workshop_builder.dart';
import '../widgets/anima_avatar.dart';
import '../widgets/ai_field_changes_sheet.dart';
import '../widgets/generate_avatar_sheet.dart';
import '../widgets/keyboard_inset.dart';
import '../widgets/minimal_chip_button.dart';
import '../widgets/preset_picker.dart';
import '../widgets/temporary_character_sheet.dart';
import '../models/anima_presets.dart';
import '../models/field_wand_options.dart';
import 'lorebook_edit_screen.dart';
import '../widgets/field_wand_icon_button.dart';
import '../widgets/field_wand_menu_sheet.dart';

enum _CharacterSection { identity, story, chat, lore, advanced }

/// Form to create/edit a SillyTavern-style character card.
class CharacterEditScreen extends StatefulWidget {
  const CharacterEditScreen({
    super.key,
    required this.characterService,
    required this.settingsService,
    required this.nanoGptService,
    this.existing,
    this.generatedDraft = false,
    this.updatingExisting = false,
    this.promoteAsFull = false,
    this.persistToLibrary = true,
    this.wandExternalSources = const [],
  });

  final CharacterService characterService;
  final SettingsService settingsService;
  final NanoGptService nanoGptService;
  final Character? existing;

  /// True when opened from Creation Center (or similar) with AI-filled fields
  /// that are not saved until the user taps Save.
  final bool generatedDraft;

  /// True when reviewing a Creation Center update to an already-saved card.
  /// Save overwrites that same character id after review.
  final bool updatingExisting;

  /// When true, saving clears [Character.isTemporary] (promote NPC to full card).
  final bool promoteAsFull;

  /// When false, Save returns the card without writing to the library.
  final bool persistToLibrary;

  /// Optional workshop / chat transcripts for long-press field wand sources.
  final List<FieldWandExternalSource> wandExternalSources;

  @override
  State<CharacterEditScreen> createState() => _CharacterEditScreenState();
}

class _CharacterEditScreenState extends State<CharacterEditScreen> {
  static const _collaborator = CharacterCollaborator();
  static const _avatarPromptBuilder = AvatarPromptBuilder();
  static const _tokenService = CharacterTokenService();
  static final _workshopBuilder = WorldWorkshopBuilder();

  final _avatarService = AvatarService();
  final _name = TextEditingController();
  final _aiBrief = TextEditingController();
  final _description = TextEditingController();
  final _personality = TextEditingController();
  final _scenario = TextEditingController();
  final _firstMes = TextEditingController();
  final _alternateGreetings = TextEditingController();
  final _mesExample = TextEditingController();
  final _systemPrompt = TextEditingController();
  final _postHistory = TextEditingController();
  bool _saving = false;
  bool _consistencyBusy = false;
  bool _avatarBusy = false;
  bool _aiCardBusy = false;
  CharacterCollaboratorField? _wandBusy;
  Lorebook? _lorebook;
  Map<String, dynamic> _extensions = const {};
  String? _avatarFileName;
  late final String _characterId;

  /// Kept from import / prior saves — not shown in the editor UI.
  /// (Named distinctly from the old TextEditingControllers to avoid hot-reload
  /// type crashes after the UI fields were removed.)
  String _preservedCreatorNotes = '';
  String _preservedCreator = '';
  String _preservedCharacterVersion = '';
  List<String> _preservedTags = const [];
  bool _isTemporary = false;

  _CharacterSection _section = _CharacterSection.identity;

  bool get _isEditing =>
      widget.existing != null &&
      !widget.generatedDraft &&
      !widget.updatingExisting;

  bool get _isGeneratedDraft => widget.generatedDraft || widget.updatingExisting;

  bool get _isUpdatingExisting => widget.updatingExisting;

  bool get _hasSlimCardContent =>
      _description.text.trim().isNotEmpty ||
      _personality.text.trim().isNotEmpty ||
      _mesExample.text.trim().isNotEmpty ||
      _preservedTags.isNotEmpty;

  Character _characterFromDraft() {
    final book = _lorebook;
    return Character(
      id: _characterId,
      name: _name.text.trim(),
      description: _description.text.trim(),
      personality: _personality.text.trim(),
      scenario: _scenario.text.trim(),
      firstMes: _firstMes.text.trim(),
      alternateGreetings: _lines(_alternateGreetings.text),
      mesExample: _mesExample.text.trim(),
      systemPrompt: _systemPrompt.text.trim(),
      postHistoryInstructions: _postHistory.text.trim(),
      creatorNotes: _preservedCreatorNotes.trim(),
      creator: _preservedCreator.trim(),
      characterVersion: _preservedCharacterVersion.trim(),
      tags: List<String>.from(_preservedTags),
      characterBook: book?.toJson(),
      extensions: _extensions,
      avatarFileName: _avatarFileName,
      isTemporary: widget.promoteAsFull ? false : _isTemporary,
    );
  }

  void _applySlimFields(Character character) {
    if (character.name.trim().isNotEmpty) {
      _name.text = character.name.trim();
    }
    _description.text = character.description.trim();
    _personality.text = character.personality.trim();
    _mesExample.text = character.mesExample.trim();
    if (character.tags.isNotEmpty) {
      _preservedTags = List<String>.from(character.tags);
    }
    if (character.creatorNotes.trim().isNotEmpty &&
        _preservedCreatorNotes.trim().isEmpty) {
      _preservedCreatorNotes = character.creatorNotes.trim();
    }
  }

  void _applyCharacterUpdate(Character character) {
    _name.text = character.name.trim();
    _description.text = character.description.trim();
    _personality.text = character.personality.trim();
    _mesExample.text = character.mesExample.trim();
    _preservedTags = List<String>.from(character.tags);
  }

  void _applyFullCharacter(Character character) {
    _name.text = character.name.trim();
    _description.text = character.description.trim();
    _personality.text = character.personality.trim();
    _scenario.text = character.scenario.trim();
    _firstMes.text = character.firstMes.trim();
    _alternateGreetings.text = character.alternateGreetings.join('\n');
    _mesExample.text = character.mesExample.trim();
    _systemPrompt.text = character.systemPrompt.trim();
    _postHistory.text = character.postHistoryInstructions.trim();
    if (character.tags.isNotEmpty) {
      _preservedTags = List<String>.from(character.tags);
    }
  }

  Future<void> _runAiCardGenerate() async {
    if (_aiCardBusy || _wandBusy != null || _consistencyBusy) return;
    final brief = _aiBrief.text.trim();
    if (brief.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Describe the character in plain English first.'),
        ),
      );
      return;
    }

    setState(() => _aiCardBusy = true);
    try {
      final build = await widget.settingsService.resolveCharacterBuild();
      final baseUrl = await widget.settingsService.getApiBaseUrl();
      final messages = _workshopBuilder.buildPlainEnglishCharacterExportMessages(
        userBrief: brief,
        characterName: _name.text.trim(),
        buildPromptNote: build.promptNote,
      );

      Character? draft;
      for (var attempt = 0; attempt < 2; attempt++) {
        final raw = await widget.nanoGptService.complete(
          model: build.model,
          messages: messages,
          baseUrl: baseUrl,
          sampling: WorldWorkshopBuilder.workshopExportSampling(build.sampling),
        );
        try {
          draft = _workshopBuilder.parseCharacterJson(
            raw,
            preferredId: _characterId,
            fallbackName: _name.text.trim(),
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
      final before = _characterFromDraft();
      final changes = compareCharacterFields(before, draft);
      if (changes.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No field changes were suggested. Try rephrasing.'),
          ),
        );
        return;
      }

      final selected = await showAiFieldChangesSheet(
        context: context,
        title: 'Review generated card',
        subtitle:
            'Check fields to apply. Tap a row to compare before and after.',
        changes: changes,
        applyLabel: 'Apply to card',
      );
      if (selected == null || !mounted) return;

      final merged = mergeCharacterChanges(before, draft, selected);
      setState(() => _applySlimFields(merged));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Applied ${selected.length} field${selected.length == 1 ? '' : 's'}.',
          ),
        ),
      );
    } on FormatException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } on NanoGptException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('AI card builder failed: $error')),
      );
    } finally {
      if (mounted) setState(() => _aiCardBusy = false);
    }
  }

  Future<void> _runAiCardUpdate() async {
    if (_aiCardBusy || _wandBusy != null || _consistencyBusy) return;
    final brief = _aiBrief.text.trim();
    if (brief.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Say what you want to change in plain English first.'),
        ),
      );
      return;
    }

    setState(() => _aiCardBusy = true);
    try {
      final build = await widget.settingsService.resolveCharacterBuild();
      final baseUrl = await widget.settingsService.getApiBaseUrl();
      final existing = _characterFromDraft();
      final messages = _workshopBuilder.buildPlainEnglishCharacterUpdateMessages(
        existing: existing,
        userBrief: brief,
        buildPromptNote: build.promptNote,
      );

      Character? draft;
      for (var attempt = 0; attempt < 2; attempt++) {
        final raw = await widget.nanoGptService.complete(
          model: build.model,
          messages: messages,
          baseUrl: baseUrl,
          sampling: WorldWorkshopBuilder.workshopExportSampling(build.sampling),
        );
        try {
          draft = _workshopBuilder.parseCharacterUpdateJson(
            raw,
            original: existing,
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
      final changes = compareCharacterFields(existing, draft);
      if (changes.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No field changes were suggested. Try rephrasing.'),
          ),
        );
        return;
      }

      final selected = await showAiFieldChangesSheet(
        context: context,
        title: 'Review card updates',
        subtitle:
            'Check fields to apply. Tap a row to compare before and after.',
        changes: changes,
        applyLabel: 'Apply updates',
      );
      if (selected == null || !mounted) return;

      final merged = mergeCharacterChanges(existing, draft, selected);
      setState(() => _applyCharacterUpdate(merged));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Applied ${selected.length} field update${selected.length == 1 ? '' : 's'}.',
          ),
        ),
      );
    } on FormatException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } on NanoGptException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('AI card update failed: $error')),
      );
    } finally {
      if (mounted) setState(() => _aiCardBusy = false);
    }
  }

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _characterId = existing?.id ?? widget.characterService.newId();
    if (existing != null) {
      _name.text = existing.name;
      _description.text = existing.description;
      _personality.text = existing.personality;
      _scenario.text = existing.scenario;
      _firstMes.text = existing.firstMes;
      _alternateGreetings.text = existing.alternateGreetings.join('\n');
      _mesExample.text = existing.mesExample;
      _systemPrompt.text = existing.systemPrompt;
      _postHistory.text = existing.postHistoryInstructions;
      _preservedCreatorNotes = existing.creatorNotes;
      _preservedCreator = existing.creator;
      _preservedCharacterVersion = existing.characterVersion;
      _preservedTags = List<String>.from(existing.tags);
      _lorebook = existing.lorebook;
      _extensions = Map<String, dynamic>.from(existing.extensions);
      _avatarFileName = existing.avatarFileName;
      _isTemporary = existing.isTemporary;
    }
    for (final controller in [
      _name,
      _description,
      _personality,
      _scenario,
      _mesExample,
      _systemPrompt,
      _postHistory,
    ]) {
      controller.addListener(_onDraftFieldChanged);
    }
  }

  void _onDraftFieldChanged() {
    if (mounted) setState(() {});
  }

  List<String> _lines(String raw) => raw
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();

  CharacterDraftContext _draftContext() {
    return CharacterDraftContext(
      name: _name.text,
      description: _description.text,
      personality: _personality.text,
      scenario: _scenario.text,
      firstMes: _firstMes.text,
      alternateGreetings: _alternateGreetings.text,
      mesExample: _mesExample.text,
      systemPrompt: _systemPrompt.text,
      postHistoryInstructions: _postHistory.text,
      creatorNotes: _preservedCreatorNotes,
      creator: _preservedCreator,
      tags: _preservedTags.join(', '),
    );
  }

  TextEditingController _controllerFor(CharacterCollaboratorField field) {
    switch (field) {
      case CharacterCollaboratorField.description:
        return _description;
      case CharacterCollaboratorField.personality:
        return _personality;
      case CharacterCollaboratorField.scenario:
        return _scenario;
      case CharacterCollaboratorField.firstMes:
        return _firstMes;
      case CharacterCollaboratorField.alternateGreetings:
        return _alternateGreetings;
      case CharacterCollaboratorField.mesExample:
        return _mesExample;
      case CharacterCollaboratorField.systemPrompt:
        return _systemPrompt;
      case CharacterCollaboratorField.postHistoryInstructions:
        return _postHistory;
    }
  }

  Future<void> _runWand(
    CharacterCollaboratorField field, {
    FieldWandChoice choice = const FieldWandChoice(
      expansion: FieldWandExpansion.light,
    ),
  }) async {
    if (_wandBusy != null || _consistencyBusy) return;

    FieldWandExternalSource? external;
    if (choice.externalSourceId != null) {
      for (final source in widget.wandExternalSources) {
        if (source.id == choice.externalSourceId) {
          external = source;
          break;
        }
      }
    }

    setState(() => _wandBusy = field);
    try {
      final collaborator =
          await widget.settingsService.getCollaboratorSettings();
      final messages = _collaborator.buildMessages(
        field: field,
        draft: _draftContext(),
        guidanceNote: collaborator.guidanceNote,
        expansion: choice.expansion,
        externalSource: external,
      );
      final model = await widget.settingsService.getModel();
      final sampling = await widget.settingsService.getSampling();
      final baseUrl = await widget.settingsService.getApiBaseUrl();
      final generated = await widget.nanoGptService.complete(
        model: model,
        messages: messages,
        baseUrl: baseUrl,
        sampling: sampling,
      );
      if (!mounted) return;
      final controller = _controllerFor(field);
      controller.text =
          _collaborator.appendGenerated(controller.text, generated);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            choice.usesExternal
                ? 'Appended ${choice.expansion.menuTitle.toLowerCase()} detail from ${external?.label ?? 'source'} to ${_collaborator.fieldLabel(field)}.'
                : 'Appended AI text to ${_collaborator.fieldLabel(field)}.',
          ),
        ),
      );
    } on NanoGptCancelledException {
      // User shouldn't hit Stop here; ignore.
    } on NanoGptException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Wand failed: $error')),
      );
    } finally {
      if (mounted) setState(() => _wandBusy = null);
    }
  }

  Future<void> _showWandMenu(CharacterCollaboratorField field) async {
    if (_wandBusy != null || _consistencyBusy) return;
    final choice = await showFieldWandMenuSheet(
      context: context,
      fieldLabel: _collaborator.fieldLabel(field),
      externalSources: widget.wandExternalSources,
    );
    if (choice == null || !mounted) return;
    await _runWand(field, choice: choice);
  }

  Future<void> _runConsistencyCheck() async {
    if (_wandBusy != null || _consistencyBusy) return;
    setState(() => _consistencyBusy = true);
    try {
      final collaborator =
          await widget.settingsService.getCollaboratorSettings();
      final messages = _collaborator.buildConsistencyCheckMessages(
        draft: _draftContext(),
        guidanceNote: collaborator.guidanceNote,
      );
      final model = await widget.settingsService.getModel();
      final sampling = WorldWorkshopBuilder.consistencyReportSampling(
        await widget.settingsService.getSampling(),
      );
      final baseUrl = await widget.settingsService.getApiBaseUrl();
      final report = await widget.nanoGptService.complete(
        model: model,
        messages: messages,
        baseUrl: baseUrl,
        sampling: sampling,
      );
      if (!mounted) return;
      final trimmedReport = report.trim();
      final truncated = _reportLooksTruncated(trimmedReport);
      final fixRequested = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Consistency check'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (truncated)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        'This report may have been cut short. Try again or use '
                        'a higher max-tokens setting in Generation parameters.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.error,
                            ),
                      ),
                    ),
                  SelectableText(trimmedReport),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Close'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Fix inconsistencies'),
            ),
          ],
        ),
      );
      if (fixRequested == true && mounted) {
        await _runConsistencyFix(trimmedReport);
      }
    } on NanoGptCancelledException {
      // Ignore.
    } on NanoGptException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Consistency check failed: $error')),
      );
    } finally {
      if (mounted) setState(() => _consistencyBusy = false);
    }
  }

  Future<void> _runConsistencyFix(String consistencyReport) async {
    if (_wandBusy != null) return;
    setState(() => _consistencyBusy = true);
    try {
      final before = _characterFromDraft();
      final collaborator =
          await widget.settingsService.getCollaboratorSettings();
      final messages = _collaborator.buildConsistencyFixMessages(
        draft: _draftContext(),
        consistencyReport: consistencyReport,
        guidanceNote: collaborator.guidanceNote,
      );
      final model = await widget.settingsService.getModel();
      final sampling = WorldWorkshopBuilder.consistencyFixSampling(
        await widget.settingsService.getSampling(),
      );
      final baseUrl = await widget.settingsService.getApiBaseUrl();

      Character? fixed;
      for (var attempt = 0; attempt < 2; attempt++) {
        final raw = await widget.nanoGptService.complete(
          model: model,
          messages: messages,
          baseUrl: baseUrl,
          sampling: sampling,
        );
        try {
          fixed = _workshopBuilder.parseCharacterConsistencyFixJson(
            raw,
            original: before,
          );
          break;
        } on FormatException {
          if (attempt == 1) rethrow;
        }
      }
      if (fixed == null) {
        throw const FormatException(
          'Could not find character card JSON in the AI reply. Try again.',
        );
      }

      if (!mounted) return;
      final changes = compareCharacterFields(before, fixed);
      if (changes.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No field changes were suggested. Try editing manually.'),
          ),
        );
        return;
      }

      final selected = await showAiFieldChangesSheet(
        context: context,
        title: 'Review card fixes',
        subtitle:
            'Check fields to apply. Tap a row to compare before and after.',
        changes: changes,
        applyLabel: 'Update card',
      );
      if (selected == null || !mounted) return;

      final merged = mergeCharacterChanges(before, fixed, selected);
      setState(() => _applyFullCharacter(merged));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Updated ${selected.length} field${selected.length == 1 ? '' : 's'} from consistency fix.',
          ),
        ),
      );
    } on FormatException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } on NanoGptCancelledException {
      // Ignore.
    } on NanoGptException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Consistency fix failed: $error')),
      );
    } finally {
      if (mounted) setState(() => _consistencyBusy = false);
    }
  }

  bool _draftHasCompactableContent(CharacterDraftContext draft) {
    return draft.description.trim().isNotEmpty ||
        draft.personality.trim().isNotEmpty ||
        draft.scenario.trim().isNotEmpty ||
        draft.firstMes.trim().isNotEmpty ||
        draft.alternateGreetings.trim().isNotEmpty ||
        draft.mesExample.trim().isNotEmpty ||
        draft.systemPrompt.trim().isNotEmpty ||
        draft.postHistoryInstructions.trim().isNotEmpty;
  }

  Future<void> _runCompactCard() async {
    if (_wandBusy != null || _consistencyBusy || _aiCardBusy) return;
    final draft = _draftContext();
    if (!_draftHasCompactableContent(draft)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add some card text first, then compact.'),
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Compact character card?'),
        content: const Text(
          'AI will shorten fields while keeping important facts and voice. '
          'You review every change before saving.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Compact'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _consistencyBusy = true);
    try {
      final before = _characterFromDraft();
      final collaborator =
          await widget.settingsService.getCollaboratorSettings();
      final messages = _collaborator.buildCompactMessages(
        draft: draft,
        guidanceNote: collaborator.guidanceNote,
      );
      final model = await widget.settingsService.getModel();
      final sampling = WorldWorkshopBuilder.consistencyFixSampling(
        await widget.settingsService.getSampling(),
      );
      final baseUrl = await widget.settingsService.getApiBaseUrl();

      Character? compacted;
      for (var attempt = 0; attempt < 2; attempt++) {
        final raw = await widget.nanoGptService.complete(
          model: model,
          messages: messages,
          baseUrl: baseUrl,
          sampling: sampling,
        );
        try {
          compacted = _workshopBuilder.parseCharacterConsistencyFixJson(
            raw,
            original: before,
          );
          break;
        } on FormatException {
          if (attempt == 1) rethrow;
        }
      }
      if (compacted == null) {
        throw const FormatException(
          'Could not find character card JSON in the AI reply. Try again.',
        );
      }

      if (!mounted) return;
      final changes = compareCharacterFields(before, compacted);
      if (changes.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No shorter version was suggested. Try editing manually.'),
          ),
        );
        return;
      }

      final selected = await showAiFieldChangesSheet(
        context: context,
        title: 'Review compacted card',
        subtitle:
            'Check fields to apply. Tap a row to compare before and after.',
        changes: changes,
        applyLabel: 'Update card',
      );
      if (selected == null || !mounted) return;

      final merged = mergeCharacterChanges(before, compacted, selected);
      setState(() => _applyFullCharacter(merged));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Compacted ${selected.length} field${selected.length == 1 ? '' : 's'}.',
          ),
        ),
      );
    } on FormatException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } on NanoGptCancelledException {
      // Ignore.
    } on NanoGptException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Compact failed: $error')),
      );
    } finally {
      if (mounted) setState(() => _consistencyBusy = false);
    }
  }

  Future<void> _pickAvatar() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    Uint8List? bytes = file.bytes;
    if (bytes == null && file.path != null) {
      bytes = await File(file.path!).readAsBytes();
    }
    if (bytes == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not read that image.')),
      );
      return;
    }

    final id = _characterId;
    var ext = '.png';
    final name = file.name.toLowerCase();
    if (name.endsWith('.jpg') || name.endsWith('.jpeg')) {
      ext = '.jpg';
    } else if (name.endsWith('.webp')) {
      ext = '.webp';
    } else if (name.endsWith('.gif')) {
      ext = '.gif';
    }

    final previous = _avatarFileName;
    final saved = await _avatarService.saveBytes(
      stem: id,
      bytes: bytes,
      extension: ext,
    );
    if (previous != null && previous != saved) {
      await _avatarService.delete(previous);
    }
    if (!mounted) return;
    setState(() => _avatarFileName = saved);
  }

  Future<void> _clearAvatar() async {
    final previous = _avatarFileName;
    if (previous != null) {
      await _avatarService.delete(previous);
    }
    if (!mounted) return;
    setState(() => _avatarFileName = null);
  }

  Future<void> _generateAvatar() async {
    if (_avatarBusy || _saving || _wandBusy != null) return;

    final promptController = TextEditingController(
      text: _avatarPromptBuilder.buildPrompt(
        name: _name.text,
        description: _description.text,
        personality: _personality.text,
        scenario: _scenario.text,
        tags: _preservedTags,
      ),
    );

    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (sheetContext) {
          return GenerateAvatarSheet(
            promptController: promptController,
            settingsService: widget.settingsService,
            nanoGptService: widget.nanoGptService,
            onAccepted: (image) async {
              setState(() => _avatarBusy = true);
              try {
                final previous = _avatarFileName;
                final saved = await _avatarService.saveBytes(
                  stem: _characterId,
                  bytes: image.bytes,
                  extension: image.fileExtension,
                );
                if (previous != null && previous != saved) {
                  await _avatarService.delete(previous);
                }
                if (!mounted) return;
                setState(() => _avatarFileName = saved);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Avatar updated from NanoGPT.')),
                );
              } finally {
                if (mounted) setState(() => _avatarBusy = false);
              }
            },
          );
        },
      );
    } finally {
      promptController.dispose();
    }
  }

  Future<void> _openLorebook() async {
    final initial = _lorebook ??
        Lorebook.empty(
          name: _name.text.trim().isEmpty
              ? 'Character lore'
              : '${_name.text.trim()} lore',
        );
    final result = await Navigator.of(context).push<Lorebook>(
      MaterialPageRoute(
        builder: (_) => LorebookEditScreen(
          initial: initial,
          characterName: _name.text.trim(),
          settingsService: widget.settingsService,
          nanoGptService: widget.nanoGptService,
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _lorebook = result.entries.isEmpty &&
              result.name.isEmpty &&
              result.description.isEmpty
          ? null
          : result;
    });
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Give your character a name.')),
      );
      return;
    }

    setState(() => _saving = true);
    final book = _lorebook;
    final character = Character(
      id: _characterId,
      name: name,
      description: _description.text.trim(),
      personality: _personality.text.trim(),
      scenario: _scenario.text.trim(),
      firstMes: _firstMes.text.trim(),
      alternateGreetings: _lines(_alternateGreetings.text),
      mesExample: _mesExample.text.trim(),
      systemPrompt: _systemPrompt.text.trim(),
      postHistoryInstructions: _postHistory.text.trim(),
      creatorNotes: _preservedCreatorNotes.trim(),
      creator: _preservedCreator.trim(),
      characterVersion: _preservedCharacterVersion.trim(),
      tags: List<String>.from(_preservedTags),
      characterBook: book?.toJson(),
      extensions: _extensions,
      avatarFileName: _avatarFileName,
      isTemporary: widget.promoteAsFull ? false : _isTemporary,
    );
    if (widget.persistToLibrary) {
      await widget.characterService.upsert(character);
    }
    if (!mounted) return;
    Navigator.of(context).pop(character);
  }

  bool _reportLooksTruncated(String report) {
    final text = report.trim();
    if (text.length < 80) return false;
    return !text.endsWith('.') &&
        !text.endsWith('!') &&
        !text.endsWith('?') &&
        !text.endsWith(':') &&
        !text.endsWith(')');
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _description,
      _personality,
      _scenario,
      _mesExample,
      _systemPrompt,
      _postHistory,
    ]) {
      controller.removeListener(_onDraftFieldChanged);
    }
    _name.dispose();
    _aiBrief.dispose();
    _description.dispose();
    _personality.dispose();
    _scenario.dispose();
    _firstMes.dispose();
    _alternateGreetings.dispose();
    _mesExample.dispose();
    _systemPrompt.dispose();
    _postHistory.dispose();
    super.dispose();
  }

  Widget _field(
    TextEditingController controller, {
    required String label,
    String? hint,
    String? help,
    int minLines = 1,
    int maxLines = 1,
    CharacterCollaboratorField? wandField,
    String? presetLabel,
    List<TextPreset>? presetList,
  }) {
    final wandBusy = wandField != null && _wandBusy == wandField;
    final anyWandBusy = _wandBusy != null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (presetLabel != null && presetList != null)
            PresetButton(
              label: presetLabel,
              onPressed: () async {
                final preset = await pickTextPreset(
                  context: context,
                  title: presetLabel,
                  presets: presetList,
                );
                if (preset == null) return;
                setState(() => controller.text = preset.text);
              },
            ),
          TextField(
            controller: controller,
            minLines: minLines,
            maxLines: maxLines,
            scrollPadding: kAnimaKeyboardScrollPadding,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: label,
              hintText: hint,
              alignLabelWithHint: minLines > 1,
              border: const OutlineInputBorder(),
              suffixIcon: wandField == null
                  ? null
                  : FieldWandIconButton(
                      busy: wandBusy,
                      enabled: !anyWandBusy,
                      onTap: () => _runWand(wandField),
                      onLongPress: () => _showWandMenu(wandField),
                    ),
            ),
          ),
          if (help != null) ...[
            const SizedBox(height: 6),
            Text(help, style: Theme.of(context).textTheme.bodySmall),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loreCount = _lorebook?.entries.length ?? 0;
    final loreEnabled =
        _lorebook?.entries.where((e) => e.enabled).length ?? 0;

    final title = _isUpdatingExisting
        ? 'Review character update'
        : (_isGeneratedDraft
            ? 'Review generated character'
            : (_isEditing
            ? (_isTemporary && !widget.promoteAsFull
                ? 'Edit temporary character'
                : 'Edit character card')
            : 'New character card'));
    final intro = _isUpdatingExisting || _isGeneratedDraft
        ? 'Review AI draft — edit then Save. Use {{char}} and {{user}}.'
        : '';
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          PopupMenuButton<String>(
            enabled: !_saving &&
                _wandBusy == null &&
                !_aiCardBusy &&
                !_consistencyBusy,
            onSelected: (value) {
              if (value == 'consistency') _runConsistencyCheck();
              if (value == 'compact') _runCompactCard();
              if (value == 'avatar_pick') _pickAvatar();
              if (value == 'avatar_gen') _generateAvatar();
              if (value == 'avatar_clear') _clearAvatar();
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'consistency',
                child: Text('Consistency check'),
              ),
              const PopupMenuItem(
                value: 'compact',
                child: Text('Compact card…'),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'avatar_pick',
                child: Text('Pick avatar photo'),
              ),
              const PopupMenuItem(
                value: 'avatar_gen',
                child: Text('Generate avatar'),
              ),
              if (_avatarFileName != null)
                const PopupMenuItem(
                  value: 'avatar_clear',
                  child: Text('Remove avatar'),
                ),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (intro.isNotEmpty)
            Text(
              intro,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          if (_isTemporary || widget.promoteAsFull) ...[
            if (intro.isNotEmpty) const SizedBox(height: 12),
            Material(
              color: Theme.of(context)
                  .colorScheme
                  .tertiaryContainer
                  .withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_isTemporary) ...[
                      const TemporaryCharacterBadge(),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      child: Text(
                        widget.promoteAsFull
                            ? 'Saving promotes this NPC to a full character card.'
                            : 'Temporary NPC — fill in more fields here, or use '
                                'Characters → Promote to full character when ready.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ] else if (intro.isNotEmpty)
            const SizedBox(height: 16),
          const SizedBox(height: 12),
          MinimalChipRow(
            children: [
              MinimalChipButton(
                label: 'Identity',
                selected: _section == _CharacterSection.identity,
                onPressed: () =>
                    setState(() => _section = _CharacterSection.identity),
              ),
              const SizedBox(width: 8),
              MinimalChipButton(
                label: 'Story',
                selected: _section == _CharacterSection.story,
                onPressed: () =>
                    setState(() => _section = _CharacterSection.story),
              ),
              const SizedBox(width: 8),
              MinimalChipButton(
                label: 'Chat',
                selected: _section == _CharacterSection.chat,
                onPressed: () =>
                    setState(() => _section = _CharacterSection.chat),
              ),
              const SizedBox(width: 8),
              MinimalChipButton(
                label: 'Lore',
                selected: _section == _CharacterSection.lore,
                onPressed: () =>
                    setState(() => _section = _CharacterSection.lore),
              ),
              const SizedBox(width: 8),
              MinimalChipButton(
                label: 'Advanced',
                selected: _section == _CharacterSection.advanced,
                onPressed: () =>
                    setState(() => _section = _CharacterSection.advanced),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_section == _CharacterSection.identity) ..._identitySection(),
          if (_section == _CharacterSection.story) ..._storySection(),
          if (_section == _CharacterSection.chat) ..._chatSection(),
          if (_section == _CharacterSection.lore) ..._loreSection(loreCount, loreEnabled),
          if (_section == _CharacterSection.advanced) ..._advancedSection(),
          FilledButton(
            onPressed:
                _saving || _wandBusy != null || _aiCardBusy ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    _isUpdatingExisting
                        ? 'Save update'
                        : _isGeneratedDraft || _isEditing
                        ? 'Save character'
                        : 'Create character',
                  ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  List<Widget> _identitySection() {
    return [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'AI card builder',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Describe the character in plain English. Fills slim fields '
                    '(description, personality, example dialogue, tags). To change '
                    'one field only, say so — e.g. "make personality more sarcastic". '
                    'Uses Settings → Character builds.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _aiBrief,
                    enabled: !_aiCardBusy && !_saving,
                    minLines: 3,
                    maxLines: 8,
                    scrollPadding: kAnimaKeyboardScrollPadding,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      hintText:
                          'Tall elven ranger, silver hair, dry wit, loyal to the party…',
                      border: OutlineInputBorder(),
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: (_aiCardBusy || _saving || _wandBusy != null)
                        ? null
                        : _runAiCardGenerate,
                    icon: _aiCardBusy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.auto_awesome),
                    label: Text(
                      _hasSlimCardContent
                          ? 'Replace slim fields from description'
                          : 'Generate from description',
                    ),
                  ),
                  if (_isEditing || _isUpdatingExisting || _hasSlimCardContent) ...[
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: (_aiCardBusy || _saving || _wandBusy != null)
                          ? null
                          : _runAiCardUpdate,
                      icon: const Icon(Icons.edit_note),
                      label: const Text('Update from description'),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Center(
            child: Column(
              children: [
                AnimaAvatar(
                  fileName: _avatarFileName,
                  label: _name.text,
                  radius: 48,
                  avatarService: _avatarService,
                ),
                const SizedBox(height: 8),
                Builder(
                  builder: (context) {
                    final breakdown = _tokenService.breakdown(_characterFromDraft());
                    return Column(
                      children: [
                        Text(
                          'Prompt ~${CharacterTokenService.format(breakdown.speakerTotal)}'
                          '${breakdown.embeddedLoreTokens > 0 ? ' · Lore (max) ~${CharacterTokenService.format(breakdown.embeddedLoreTokens)}' : ''}',
                          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                color: Theme.of(context).colorScheme.outline,
                              ),
                        ),
                        if (breakdown.groupSummaryTokens > 0)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              'Group snippet ~${CharacterTokenService.format(breakdown.groupSummaryTokens)} when someone else speaks',
                              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: Theme.of(context).colorScheme.outline,
                                  ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 4),
                Text(
                  'Avatar: ⋮ menu → pick or generate.',
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _field(_name, label: 'Name', hint: 'e.g. Luna'),
    ];
  }

  List<Widget> _storySection() {
    return [
          _field(
            _description,
            label: 'Description',
            hint: 'Appearance, background, important facts…',
            help: 'Usually included in every prompt (ST Description).',
            minLines: 4,
            maxLines: 10,
            wandField: CharacterCollaboratorField.description,
          ),
          _field(
            _personality,
            label: 'Personality',
            hint: 'Short personality summary…',
            minLines: 2,
            maxLines: 6,
            wandField: CharacterCollaboratorField.personality,
          ),
          _field(
            _scenario,
            label: 'Scenario',
            hint: 'Current situation / context…',
            minLines: 2,
            maxLines: 6,
            wandField: CharacterCollaboratorField.scenario,
          ),
    ];
  }

  List<Widget> _chatSection() {
    return [
          _field(
            _firstMes,
            label: 'First message',
            hint: 'Opening greeting…',
            help: 'Shown when a new chat starts.',
            minLines: 3,
            maxLines: 8,
            wandField: CharacterCollaboratorField.firstMes,
          ),
          _field(
            _alternateGreetings,
            label: 'Alternate greetings',
            hint: 'One greeting per line…',
            help: 'Extra first-message swipes (ST alternate_greetings).',
            minLines: 3,
            maxLines: 8,
            wandField: CharacterCollaboratorField.alternateGreetings,
          ),
          _field(
            _mesExample,
            label: 'Example messages',
            hint: '<START>\n{{user}}: …\n{{char}}: …',
            help: 'ST mes_example — teaches tone and style.',
            minLines: 4,
            maxLines: 12,
            wandField: CharacterCollaboratorField.mesExample,
          ),
    ];
  }

  List<Widget> _loreSection(int loreCount, int loreEnabled) {
    return [
          OutlinedButton.icon(
            onPressed: _openLorebook,
            icon: const Icon(Icons.menu_book_outlined),
            label: Text(
              loreCount == 0
                  ? 'World Info / lorebook'
                  : 'World Info / lorebook ($loreEnabled/$loreCount on)',
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 16),
            child: Text(
              loreCount == 0
                  ? 'Optional keyword lore (also used for imported character_book).'
                  : 'Keyword lore is injected during chat when keys match.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
    ];
  }

  List<Widget> _advancedSection() {
    return [
          _field(
            _systemPrompt,
            label: 'System prompt (optional)',
            hint: 'Leave blank to use Anima’s default…',
            help: 'ST system_prompt. Supports {{original}}.',
            minLines: 2,
            maxLines: 6,
            wandField: CharacterCollaboratorField.systemPrompt,
            presetLabel: 'System prompt presets',
            presetList: AnimaPresets.systemPrompts,
          ),
          _field(
            _postHistory,
            label: 'Post-history instructions (optional)',
            hint: 'Nudge after the chat history…',
            help: 'ST post_history_instructions.',
            minLines: 2,
            maxLines: 6,
            wandField:
                CharacterCollaboratorField.postHistoryInstructions,
            presetLabel: 'Post-history presets',
            presetList: AnimaPresets.postHistory,
          ),
    ];
  }
}
