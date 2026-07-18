import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/persona.dart';
import '../services/avatar_prompt_builder.dart';
import '../services/avatar_service.dart';
import '../services/nanogpt_service.dart';
import '../services/persona_collaborator.dart';
import '../services/persona_service.dart';
import '../services/settings_service.dart';
import '../widgets/anima_avatar.dart';
import '../widgets/generate_avatar_sheet.dart';
import '../widgets/keyboard_inset.dart';
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
  });

  final PersonaService personaService;
  final SettingsService settingsService;
  final NanoGptService nanoGptService;
  final Persona? existing;
  final bool generatedDraft;

  @override
  State<PersonaEditScreen> createState() => _PersonaEditScreenState();
}

class _PersonaEditScreenState extends State<PersonaEditScreen> {
  static const _avatarPromptBuilder = AvatarPromptBuilder();
  static const _collaborator = PersonaCollaborator();

  final _avatarService = AvatarService();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _appearanceController = TextEditingController();
  final _personalityController = TextEditingController();
  final _backgroundController = TextEditingController();
  final _goalsController = TextEditingController();
  bool _saving = false;
  bool _avatarBusy = false;
  PersonaCollaboratorField? _wandBusy;
  String? _avatarFileName;
  late final String _personaId;

  bool get _isEditing => widget.existing != null;
  bool get _busy => _saving || _avatarBusy || _wandBusy != null;

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

  Future<void> _runWand(PersonaCollaboratorField field) async {
    if (_wandBusy != null || _saving || _avatarBusy) return;

    setState(() => _wandBusy = field);
    try {
      final collaborator = await widget.settingsService
          .getCollaboratorSettings();
      final messages = _collaborator.buildMessages(
        field: field,
        draft: _draftContext(),
        guidanceNote: collaborator.guidanceNote,
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
            'Appended AI text to ${_collaborator.fieldLabel(field)}.',
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

    final previous = _avatarFileName;
    final saved = await _avatarService.saveBytes(
      stem: _personaId,
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
    if (_busy) return;
    final previous = _avatarFileName;
    if (previous != null) {
      await _avatarService.delete(previous);
    }
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
                final previous = _avatarFileName;
                final saved = await _avatarService.saveBytes(
                  stem: _personaId,
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
    );
    await widget.personaService.upsert(persona);
    if (!mounted) return;
    Navigator.of(context).pop(persona);
  }

  @override
  void dispose() {
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
                  : IconButton(
                      tooltip: 'AI wand — expand this field',
                      onPressed: anyWandBusy || _saving || _avatarBusy
                          ? null
                          : () => _runWand(wandField),
                      icon: wandBusy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.auto_awesome),
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
                    if (_avatarFileName != null)
                      TextButton(
                        onPressed: _busy ? null : _clearAvatar,
                        child: const Text('Remove'),
                      ),
                  ],
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
