import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/persona.dart';
import '../services/avatar_service.dart';
import '../services/persona_service.dart';
import '../widgets/anima_avatar.dart';
import 'settings_ui.dart';

/// Create or edit one user persona.
class PersonaEditScreen extends StatefulWidget {
  const PersonaEditScreen({
    super.key,
    required this.personaService,
    this.existing,
  });

  final PersonaService personaService;
  final Persona? existing;

  @override
  State<PersonaEditScreen> createState() => _PersonaEditScreenState();
}

class _PersonaEditScreenState extends State<PersonaEditScreen> {
  final _avatarService = AvatarService();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  bool _saving = false;
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
      _avatarFileName = existing.avatarFileName;
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
    final previous = _avatarFileName;
    if (previous != null) {
      await _avatarService.delete(previous);
    }
    if (!mounted) return;
    setState(() => _avatarFileName = null);
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit persona' : 'New persona'),
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
                  alignment: WrapAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _pickAvatar,
                      icon: const Icon(Icons.photo),
                      label: Text(
                        _avatarFileName == null ? 'Add photo' : 'Change photo',
                      ),
                    ),
                    if (_avatarFileName != null)
                      TextButton(
                        onPressed: _clearAvatar,
                        child: const Text('Remove'),
                      ),
                  ],
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
            maxLines: 8,
            decoration: SettingsUi.fieldDecoration(
              label: 'About this persona (optional)',
              hintText: 'Short description the AI should know…',
            ).copyWith(alignLabelWithHint: true),
          ),
          const SizedBox(height: 24),
          SettingsUi.saveButton(
            saving: _saving,
            label: _isEditing ? 'Save persona' : 'Create persona',
            onPressed: _saving ? null : _save,
          ),
        ],
      ),
    );
  }
}
