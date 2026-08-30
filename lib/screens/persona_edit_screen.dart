import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/persona.dart';
import '../services/avatar_prompt_builder.dart';
import '../services/avatar_export_service.dart';
import '../services/avatar_service.dart';
import '../services/nanogpt_service.dart';
import '../services/persona_collaborator.dart';
import '../services/persona_service.dart';
import '../services/persona_token_service.dart';
import '../services/ai_field_changes.dart';
import '../services/settings_service.dart';
import '../widgets/character_token_badge.dart';
import '../widgets/ai_field_changes_sheet.dart';
import '../services/world_workshop_builder.dart';
import '../widgets/anima_avatar.dart';
import '../widgets/avatar_history_sheet.dart';
import '../widgets/generate_avatar_sheet.dart';
import '../widgets/keyboard_inset.dart';
import '../models/field_wand_options.dart';
import '../widgets/field_wand_icon_button.dart';
import '../widgets/field_wand_menu_sheet.dart';
import 'settings_ui.dart';

/// Create or edit one user persona.
class PersonaEditScreen extends StatefulWidget {
  const PersonaEditScreen({
    super.key,
    required this.personaService,
    required this.settingsService,
    required this.nanoGptService,
    this.existing,
    this.generatedDraft = false,
    this.persistToLibrary = true,
    this.wandExternalSources = const [],
  });

  final PersonaService personaService;
  final SettingsService settingsService;
  final NanoGptService nanoGptService;
  final Persona? existing;
  final bool generatedDraft;

  /// When false, Save returns the persona without writing to the library.
  final bool persistToLibrary;

  final List<FieldWandExternalSource> wandExternalSources;

  @override
  State<PersonaEditScreen> createState() => _PersonaEditScreenState();
}

class _PersonaEditScreenState extends State<PersonaEditScreen> {
  static const _avatarPromptBuilder = AvatarPromptBuilder();
  static const _collaborator = PersonaCollaborator();
  static const _tokenService = PersonaTokenService();
  final _workshopBuilder = WorldWorkshopBuilder();

  final _avatarService = AvatarService();
  final _avatarExportService = AvatarExportService();
  final _aiBrief = TextEditingController();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _appearanceController = TextEditingController();
  final _personalityController = TextEditingController();
  final _backgroundController = TextEditingController();
  final _goalsController = TextEditingController();
  bool _saving = false;
  bool _avatarBusy = false;
  bool _aiCardBusy = false;
  bool _compactBusy = false;
  PersonaCollaboratorField? _wandBusy;
  String? _avatarFileName;
  late final String _personaId;

  bool get _isEditing => widget.existing != null;
  bool get _busy =>
      _saving || _avatarBusy || _wandBusy != null || _aiCardBusy || _compactBusy;

  bool get _hasPersonaContent =>
      _descriptionController.text.trim().isNotEmpty ||
      _appearanceController.text.trim().isNotEmpty ||
      _personalityController.text.trim().isNotEmpty ||
      _backgroundController.text.trim().isNotEmpty ||
      _goalsController.text.trim().isNotEmpty;

  Persona _personaFromDraft() {
    return Persona(
      id: _personaId,
      name: _nameController.text.trim(),
      description: _descriptionController.text.trim(),
      appearance: _appearanceController.text.trim(),
      personality: _personalityController.text.trim(),
      background: _backgroundController.text.trim(),
      goals: _goalsController.text.trim(),
      avatarFileName: _avatarFileName,
      sourceWorkshopId: widget.existing?.sourceWorkshopId,
    );
  }

  void _applyPersonaFields(Persona persona) {
    if (persona.name.trim().isNotEmpty) {
      _nameController.text = persona.name.trim();
    }
    _descriptionController.text = persona.description.trim();
    _appearanceController.text = persona.appearance.trim();
    _personalityController.text = persona.personality.trim();
    _backgroundController.text = persona.background.trim();
    _goalsController.text = persona.goals.trim();
  }

  Future<void> _runAiPersonaGenerate() async {
    if (_aiCardBusy || _wandBusy != null) return;
    final brief = _aiBrief.text.trim();
    if (brief.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Describe your persona in plain English first.'),
        ),
      );
      return;
    }

    setState(() => _aiCardBusy = true);
    try {
      final build = await widget.settingsService.resolveCharacterBuild();
      final baseUrl = await widget.settingsService.getApiBaseUrl();
      final messages = _workshopBuilder.buildPlainEnglishPersonaExportMessages(
        userBrief: brief,
        personaName: _nameController.text.trim(),
        buildPromptNote: build.personaPromptNote,
      );

      Persona? draft;
      for (var attempt = 0; attempt < 2; attempt++) {
        final raw = await widget.nanoGptService.complete(
          model: build.model,
          messages: messages,
          baseUrl: baseUrl,
          sampling: WorldWorkshopBuilder.workshopExportSampling(build.sampling),
        );
        try {
          draft = _workshopBuilder.parsePersonaJson(
            raw,
            preferredId: _personaId,
            fallbackName: _nameController.text.trim(),
          );
          break;
        } on FormatException {
          if (attempt == 1) rethrow;
        }
      }
      if (draft == null) {
        throw const FormatException(
          'Could not find persona JSON in the AI reply. Try again.',
        );
      }

      if (!mounted) return;
      setState(() => _applyPersonaFields(draft!));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Filled identity, appearance, personality, background, and goals.',
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
        SnackBar(content: Text('AI persona builder failed: $error')),
      );
    } finally {
      if (mounted) setState(() => _aiCardBusy = false);
    }
  }

  Future<void> _runAiPersonaUpdate() async {
    if (_aiCardBusy || _wandBusy != null) return;
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
      final existing = _personaFromDraft();
      final messages = _workshopBuilder.buildPlainEnglishPersonaUpdateMessages(
        existing: existing,
        userBrief: brief,
        buildPromptNote: build.personaPromptNote,
      );

      Persona? draft;
      for (var attempt = 0; attempt < 2; attempt++) {
        final raw = await widget.nanoGptService.complete(
          model: build.model,
          messages: messages,
          baseUrl: baseUrl,
          sampling: WorldWorkshopBuilder.workshopExportSampling(build.sampling),
        );
        try {
          draft = _workshopBuilder.parsePersonaUpdateJson(
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
          'Could not find persona JSON in the AI reply. Try again.',
        );
      }

      if (!mounted) return;
      setState(() => _applyPersonaFields(draft!));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Merged your notes into the persona fields.'),
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
        SnackBar(content: Text('AI persona update failed: $error')),
      );
    } finally {
      if (mounted) setState(() => _aiCardBusy = false);
    }
  }

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _personaId = existing?.id ?? widget.personaService.newId();
    if (existing != null) {
      _nameController.text = existing.name;
      _descriptionController.text = existing.description;
      _appearanceController.text = existing.appearance;
      _personalityController.text = existing.personality;
      _backgroundController.text = existing.background;
      _goalsController.text = existing.goals;
      _avatarFileName = existing.avatarFileName;
    }
    for (final controller in [
      _nameController,
      _descriptionController,
      _appearanceController,
      _personalityController,
      _backgroundController,
      _goalsController,
    ]) {
      controller.addListener(_onDraftFieldChanged);
    }
  }

  void _onDraftFieldChanged() {
    if (mounted) setState(() {});
  }

  bool _draftHasCompactableContent(PersonaDraftContext draft) {
    return draft.description.trim().isNotEmpty ||
        draft.appearance.trim().isNotEmpty ||
        draft.personality.trim().isNotEmpty ||
        draft.background.trim().isNotEmpty ||
        draft.goals.trim().isNotEmpty;
  }

  Future<void> _runCompactPersona() async {
    if (_compactBusy || _aiCardBusy || _wandBusy != null) return;
    final draft = _draftContext();
    if (!_draftHasCompactableContent(draft)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add some persona details first, then compact.'),
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Compact persona?'),
        content: const Text(
          'AI will shorten fields while keeping important facts. '
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

    setState(() => _compactBusy = true);
    try {
      final before = _personaFromDraft();
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

      Persona? compacted;
      for (var attempt = 0; attempt < 2; attempt++) {
        final raw = await widget.nanoGptService.complete(
          model: model,
          messages: messages,
          baseUrl: baseUrl,
          sampling: sampling,
        );
        try {
          compacted = _workshopBuilder.parsePersonaUpdateJson(
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
          'Could not find persona JSON in the AI reply. Try again.',
        );
      }

      if (!mounted) return;
      final changes = comparePersonaFields(before, compacted);
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
        title: 'Review compacted persona',
        subtitle:
            'Check fields to apply. Tap a row to compare before and after.',
        changes: changes,
        applyLabel: 'Update persona',
      );
      if (selected == null || !mounted) return;

      final merged = mergePersonaChanges(before, compacted, selected);
      setState(() => _applyPersonaFields(merged));
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
      if (mounted) setState(() => _compactBusy = false);
    }
  }

  PersonaDraftContext _draftContext() {
    return PersonaDraftContext(
      name: _nameController.text,
      description: _descriptionController.text,
      appearance: _appearanceController.text,
      personality: _personalityController.text,
      background: _backgroundController.text,
      goals: _goalsController.text,
    );
  }

  TextEditingController _controllerFor(PersonaCollaboratorField field) {
    switch (field) {
      case PersonaCollaboratorField.description:
        return _descriptionController;
      case PersonaCollaboratorField.appearance:
        return _appearanceController;
      case PersonaCollaboratorField.personality:
        return _personalityController;
      case PersonaCollaboratorField.background:
        return _backgroundController;
      case PersonaCollaboratorField.goals:
        return _goalsController;
    }
  }

  Future<void> _runWand(
    PersonaCollaboratorField field, {
    FieldWandChoice choice = const FieldWandChoice(
      expansion: FieldWandExpansion.light,
    ),
  }) async {
    if (_wandBusy != null || _saving || _avatarBusy || _aiCardBusy) return;

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
      final collaborator = await widget.settingsService
          .getCollaboratorSettings();
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
      controller.text = _collaborator.appendGenerated(
        controller.text,
        generated,
      );
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
      // Ignore.
    } on NanoGptException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Wand failed: $error')));
    } finally {
      if (mounted) setState(() => _wandBusy = null);
    }
  }

  Future<void> _showWandMenu(PersonaCollaboratorField field) async {
    if (_wandBusy != null || _saving || _avatarBusy || _aiCardBusy) return;
    final choice = await showFieldWandMenuSheet(
      context: context,
      fieldLabel: _collaborator.fieldLabel(field),
      externalSources: widget.wandExternalSources,
    );
    if (choice == null || !mounted) return;
    await _runWand(field, choice: choice);
  }

  Future<void> _openAvatarHistory() async {
    final picked = await showAvatarHistorySheet(
      context: context,
      avatarService: _avatarService,
      exportService: _avatarExportService,
      stem: _personaId,
      currentFileName: _avatarFileName,
    );
    if (!mounted || picked == null) return;
    if (picked.isEmpty) {
      setState(() => _avatarFileName = null);
      return;
    }
    if (picked != _avatarFileName) {
      setState(() => _avatarFileName = picked);
    }
  }

  Future<void> _applyAvatarBytes(
    Uint8List bytes,
    String extension, {
    required bool exportCopy,
  }) async {
    final saved = await _avatarService.saveHistoryBytes(
      stem: _personaId,
      bytes: bytes,
      extension: extension,
    );
    if (exportCopy) {
      try {
        final msg = await _avatarExportService.exportAvatar(
          bytes: bytes,
          suggestedName: saved,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Avatar updated. $msg')),
          );
        }
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Avatar saved in Anima; could not export copy: $error',
              ),
            ),
          );
        }
      }
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Avatar updated.')),
      );
    }
    if (!mounted) return;
    setState(() => _avatarFileName = saved);
  }

  Future<void> _pickAvatar() async {
    if (_busy) return;

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

    var ext = '.png';
    final name = file.name.toLowerCase();
    if (name.endsWith('.jpg') || name.endsWith('.jpeg')) {
      ext = '.jpg';
    } else if (name.endsWith('.webp')) {
      ext = '.webp';
    }

    final saved = await _avatarService.saveHistoryBytes(
      stem: _personaId,
      bytes: bytes,
      extension: ext,
    );
    if (!mounted) return;
    setState(() => _avatarFileName = saved);
  }

  Future<void> _clearAvatar() async {
    if (_busy) return;
    if (!mounted) return;
    setState(() => _avatarFileName = null);
  }

  Future<void> _generateAvatar() async {
    if (_busy) return;

    final promptController = TextEditingController(
      text: _avatarPromptBuilder.buildPersonaPrompt(
        name: _nameController.text,
        description: _descriptionController.text,
        appearance: _appearanceController.text,
        personality: _personalityController.text,
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
                await _applyAvatarBytes(
                  image.bytes,
                  image.fileExtension,
                  exportCopy: true,
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

  Future<void> _save() async {
    if (_busy) return;
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Give this persona a name.')),
      );
      return;
    }

    setState(() => _saving = true);
    final persona = Persona(
      id: _personaId,
      name: name,
      description: _descriptionController.text.trim(),
      appearance: _appearanceController.text.trim(),
      personality: _personalityController.text.trim(),
      background: _backgroundController.text.trim(),
      goals: _goalsController.text.trim(),
      avatarFileName: _avatarFileName,
      sourceWorkshopId: widget.existing?.sourceWorkshopId,
    );
    if (widget.persistToLibrary) {
      await widget.personaService.upsert(persona);
    }
    if (!mounted) return;
    Navigator.of(context).pop(persona);
  }

  @override
  void dispose() {
    for (final controller in [
      _nameController,
      _descriptionController,
      _appearanceController,
      _personalityController,
      _backgroundController,
      _goalsController,
    ]) {
      controller.removeListener(_onDraftFieldChanged);
    }
    _aiBrief.dispose();
    _nameController.dispose();
    _descriptionController.dispose();
    _appearanceController.dispose();
    _personalityController.dispose();
    _backgroundController.dispose();
    _goalsController.dispose();
    super.dispose();
  }

  Widget _field(
    TextEditingController controller, {
    required String label,
    String? hint,
    int minLines = 1,
    int maxLines = 1,
    PersonaCollaboratorField? wandField,
    TextCapitalization textCapitalization = TextCapitalization.sentences,
    ValueChanged<String>? onChanged,
  }) {
    final wandBusy = wandField != null && _wandBusy == wandField;
    final anyWandBusy = _wandBusy != null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        minLines: minLines,
        maxLines: maxLines,
        scrollPadding: kAnimaKeyboardScrollPadding,
        textCapitalization: textCapitalization,
        onChanged: onChanged,
        decoration: SettingsUi.fieldDecoration(label: label, hintText: hint)
            .copyWith(
              alignLabelWithHint: minLines > 1,
              suffixIcon: wandField == null
                  ? null
                  : FieldWandIconButton(
                      busy: wandBusy,
                      enabled: !anyWandBusy && !_saving && !_avatarBusy,
                      onTap: () => _runWand(wandField),
                      onLongPress: () => _showWandMenu(wandField),
                    ),
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.generatedDraft
              ? 'Review generated persona'
              : (_isEditing ? 'Edit persona' : 'New persona'),
        ),
        actions: [
          PopupMenuButton<String>(
            enabled: !_busy,
            onSelected: (value) {
              if (value == 'compact') _runCompactPersona();
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'compact',
                child: Text('Compact persona…'),
              ),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: SettingsUi.listPadding,
        children: [
          SettingsUi.sectionHint(
            context,
            'This is who you are in chat ({{user}}). You can switch personas '
            'per chat session. Tap the wand on a creative field to append AI '
            'text (uses your NanoGPT model + Settings → AI collaborator).',
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'AI persona builder',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Describe yourself in plain English. Fills identity, appearance, '
                    'personality, background, and goals. Uses Settings → Character builds.',
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
                          'Veteran scout, scarred hands, dry humor, loyal to the crew…',
                      border: OutlineInputBorder(),
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: (_aiCardBusy || _saving || _wandBusy != null)
                        ? null
                        : _runAiPersonaGenerate,
                    icon: _aiCardBusy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.auto_awesome),
                    label: Text(
                      _hasPersonaContent
                          ? 'Replace persona fields from description'
                          : 'Generate from description',
                    ),
                  ),
                  if (_isEditing || _hasPersonaContent) ...[
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: (_aiCardBusy || _saving || _wandBusy != null)
                          ? null
                          : _runAiPersonaUpdate,
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
                  label: _nameController.text,
                  radius: 44,
                  avatarService: _avatarService,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _pickAvatar,
                      icon: const Icon(Icons.photo),
                      label: Text(
                        _avatarFileName == null ? 'Add photo' : 'Change photo',
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _generateAvatar,
                      icon: _avatarBusy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.auto_awesome),
                      label: const Text('Generate avatar'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _openAvatarHistory,
                      icon: const Icon(Icons.collections_outlined),
                      label: const Text('History'),
                    ),
                    if (_avatarFileName != null)
                      TextButton(
                        onPressed: _busy ? null : _clearAvatar,
                        child: const Text('Remove'),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Builder(
                  builder: (context) {
                    final breakdown =
                        _tokenService.breakdown(_personaFromDraft());
                    return Column(
                      children: [
                        CharacterTokenBadge(
                          tokens: breakdown.promptTokens,
                          tooltip: personaTokenTooltip(breakdown),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Injected into every chat as {{user}}',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: Theme.of(context).colorScheme.outline,
                              ),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 8),
                Text(
                  'Pick a photo or generate one with NanoGPT from the name '
                  'and persona details.',
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _field(
            _nameController,
            label: 'Name',
            hint: 'e.g. Sam',
            textCapitalization: TextCapitalization.words,
            onChanged: (_) => setState(() {}),
          ),
          _field(
            _descriptionController,
            label: 'Identity and role (optional)',
            hint: 'Who they are and their place in the setting…',
            minLines: 3,
            maxLines: 6,
            wandField: PersonaCollaboratorField.description,
          ),
          _field(
            _appearanceController,
            label: 'Appearance (optional)',
            hint: 'Physical features, clothing, distinguishing details…',
            minLines: 2,
            maxLines: 5,
            wandField: PersonaCollaboratorField.appearance,
          ),
          _field(
            _personalityController,
            label: 'Personality (optional)',
            hint: 'Traits, habits, temperament, manner of speaking…',
            minLines: 2,
            maxLines: 5,
            wandField: PersonaCollaboratorField.personality,
          ),
          _field(
            _backgroundController,
            label: 'Background (optional)',
            hint: 'History, relationships, abilities, important facts…',
            minLines: 3,
            maxLines: 7,
            wandField: PersonaCollaboratorField.background,
          ),
          _field(
            _goalsController,
            label: 'Goals and motivations (optional)',
            hint: 'What they want, fear, protect, or are working toward…',
            minLines: 2,
            maxLines: 5,
            wandField: PersonaCollaboratorField.goals,
          ),
          const SizedBox(height: 12),
          SettingsUi.saveButton(
            saving: _saving,
            label: widget.generatedDraft
                ? 'Save to Personas'
                : (_isEditing ? 'Save persona' : 'Create persona'),
            onPressed: _busy ? null : _save,
          ),
        ],
      ),
    );
  }
}
