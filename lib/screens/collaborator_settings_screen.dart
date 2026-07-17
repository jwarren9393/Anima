import 'package:flutter/material.dart';

import '../models/anima_presets.dart';
import '../services/settings_service.dart';
import '../widgets/preset_picker.dart';
import 'settings_ui.dart';

/// Settings for the character-editor AI wand (guidance note).
class CollaboratorSettingsScreen extends StatefulWidget {
  const CollaboratorSettingsScreen({
    super.key,
    required this.settingsService,
  });

  final SettingsService settingsService;

  @override
  State<CollaboratorSettingsScreen> createState() =>
      _CollaboratorSettingsScreenState();
}

class _CollaboratorSettingsScreenState
    extends State<CollaboratorSettingsScreen> {
  final _guidanceController = TextEditingController();
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final settings = await widget.settingsService.getCollaboratorSettings();
    if (!mounted) return;
    setState(() {
      _guidanceController.text = settings.guidanceNote;
      _loading = false;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await widget.settingsService.saveCollaboratorSettings(
      CollaboratorSettings(guidanceNote: _guidanceController.text),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('AI collaborator settings saved.')),
    );
  }

  Future<void> _resetDefault() async {
    setState(() {
      _guidanceController.text = CollaboratorSettings.defaultGuidanceNote;
    });
  }

  Future<void> _pickPreset() async {
    final preset = await pickTextPreset(
      context: context,
      title: 'Guidance presets',
      presets: AnimaPresets.collaboratorGuidance,
    );
    if (preset == null || !mounted) return;
    setState(() => _guidanceController.text = preset.text);
  }

  @override
  void dispose() {
    _guidanceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AI collaborator')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: SettingsUi.listPadding,
              children: [
                SettingsUi.sectionTitle(context, 'Wand guidance note'),
                const SizedBox(height: 8),
                SettingsUi.sectionHint(
                  context,
                  'Sent with every character-editor wand tap and with '
                  'Creation Center chats (like an Author’s Note for writing). '
                  'Use this to steer tone — for example, tell it not to '
                  'sanitize replies.',
                ),
                PresetButton(
                  label: 'Guidance presets',
                  onPressed: _pickPreset,
                ),
                TextField(
                  controller: _guidanceController,
                  minLines: 5,
                  maxLines: 12,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: SettingsUi.fieldDecoration(
                    label: 'Guidance note',
                    hintText: 'How the wand should write…',
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: _saving ? null : _resetDefault,
                  child: const Text('Reset to default note'),
                ),
                const SizedBox(height: 8),
                Text(
                  'The wand uses your normal NanoGPT model and generation '
                  'parameters from Settings.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 24),
                SettingsUi.saveButton(
                  saving: _saving,
                  label: 'Save',
                  onPressed: _saving ? null : _save,
                ),
                const SizedBox(height: 24),
              ],
            ),
    );
  }
}
