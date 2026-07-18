import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/persona.dart';
import '../services/avatar_prompt_builder.dart';
import '../services/avatar_service.dart';
import '../services/nanogpt_service.dart';
import '../services/persona_service.dart';
import '../services/settings_service.dart';
import '../widgets/anima_avatar.dart';
import '../widgets/generate_avatar_sheet.dart';
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

  final _avatarService = AvatarService();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _appearanceController = TextEditingController();
  final _personalityController = TextEditingController();
  final _backgroundController = TextEditingController();
  final _goalsController = TextEditingController();
  bool _saving = false;
  bool _avatarBusy = false;
  String? _avatarFileName;
  late final String _personaId;

  bool get _isEditing => widget.existing != null;

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

  Future<void> _pickAvatar() async {
    if (_avatarBusy || _saving) return;

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
    if (_avatarBusy || _saving) return;
    final previous = _avatarFileName;
    if (previous != null) {
      await _avatarService.delete(previous);
    }
    if (!mounted) return;
    setState(() => _avatarFileName = null);
  }

  Future<void> _generateAvatar() async {
    if (_avatarBusy || _saving) return;

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
            'per chat session.',
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
                      onPressed: (_avatarBusy || _saving) ? null : _pickAvatar,
                      icon: const Icon(Icons.photo),
                      label: Text(
                        _avatarFileName == null ? 'Add photo' : 'Change photo',
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: (_avatarBusy || _saving)
                          ? null
                          : _generateAvatar,
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
                        onPressed: (_avatarBusy || _saving)
                            ? null
                            : _clearAvatar,
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
          TextField(
            controller: _nameController,
            textCapitalization: TextCapitalization.words,
            onChanged: (_) => setState(() {}),
            decoration: SettingsUi.fieldDecoration(
              label: 'Name',
              hintText: 'e.g. Sam',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _descriptionController,
            minLines: 3,
            maxLines: 6,
            decoration: SettingsUi.fieldDecoration(
              label: 'Identity and role (optional)',
              hintText: 'Who they are and their place in the setting…',
            ).copyWith(alignLabelWithHint: true),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _appearanceController,
            minLines: 2,
            maxLines: 5,
            decoration: SettingsUi.fieldDecoration(
              label: 'Appearance (optional)',
              hintText: 'Physical features, clothing, distinguishing details…',
            ).copyWith(alignLabelWithHint: true),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _personalityController,
            minLines: 2,
            maxLines: 5,
            decoration: SettingsUi.fieldDecoration(
              label: 'Personality (optional)',
              hintText: 'Traits, habits, temperament, manner of speaking…',
            ).copyWith(alignLabelWithHint: true),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _backgroundController,
            minLines: 3,
            maxLines: 7,
            decoration: SettingsUi.fieldDecoration(
              label: 'Background (optional)',
              hintText: 'History, relationships, abilities, important facts…',
            ).copyWith(alignLabelWithHint: true),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _goalsController,
            minLines: 2,
            maxLines: 5,
            decoration: SettingsUi.fieldDecoration(
              label: 'Goals and motivations (optional)',
              hintText: 'What they want, fear, protect, or are working toward…',
            ).copyWith(alignLabelWithHint: true),
          ),
          const SizedBox(height: 24),
          SettingsUi.saveButton(
            saving: _saving,
            label: widget.generatedDraft
                ? 'Save to Personas'
                : (_isEditing ? 'Save persona' : 'Create persona'),
            onPressed: (_saving || _avatarBusy) ? null : _save,
          ),
        ],
      ),
    );
  }
}
