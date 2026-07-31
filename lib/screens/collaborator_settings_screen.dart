import 'package:flutter/material.dart';

import '../models/anima_presets.dart';
import '../services/settings_service.dart';
import '../utils/platform_utils.dart';
import '../widgets/preset_picker.dart';
import 'settings_ui.dart';

/// Settings for character/lore wand guidance + composer Format note.
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
  final _composerFormatController = TextEditingController();
  final _roadwayController = TextEditingController();
  final _narratorController = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  bool _enterToSend = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final settings = await widget.settingsService.getCollaboratorSettings();
    final enterToSend = await widget.settingsService.getEnterToSendComposer();
    if (!mounted) return;
    setState(() {
      _guidanceController.text = settings.guidanceNote;
      _composerFormatController.text = settings.composerFormatNote;
      _roadwayController.text = settings.roadwayNote;
      _narratorController.text = settings.narratorNote;
      _enterToSend = enterToSend;
      _loading = false;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await widget.settingsService.saveCollaboratorSettings(
      CollaboratorSettings(
        guidanceNote: _guidanceController.text,
        composerFormatNote: _composerFormatController.text,
        roadwayNote: _roadwayController.text,
        narratorNote: _narratorController.text,
      ),
    );
    await widget.settingsService.saveEnterToSendComposer(_enterToSend);
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('AI collaborator settings saved.')),
    );
  }

  Future<void> _resetWandDefault() async {
    setState(() {
      _guidanceController.text = CollaboratorSettings.defaultGuidanceNote;
    });
  }

  Future<void> _resetComposerDefault() async {
    setState(() {
      _composerFormatController.text =
          CollaboratorSettings.defaultComposerFormatNote;
    });
  }

  Future<void> _resetRoadwayDefault() async {
    setState(() {
      _roadwayController.text = CollaboratorSettings.defaultRoadwayNote;
    });
  }

  Future<void> _resetNarratorDefault() async {
    setState(() {
      _narratorController.text = CollaboratorSettings.defaultNarratorNote;
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
    _composerFormatController.dispose();
    _roadwayController.dispose();
    _narratorController.dispose();
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
                  'Sent with character-editor and World Info entry wand taps, '
                  'and with Creation Center chats. Use this to steer creative '
                  'writing — for example, tell it not to sanitize replies.',
                ),
                PresetButton(
                  label: 'Guidance presets',
                  onPressed: _pickPreset,
                ),
                TextField(
                  controller: _guidanceController,
                  minLines: 5,
                  maxLines: 12,
                  scrollPadding: SettingsUi.keyboardScrollPadding,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: SettingsUi.fieldDecoration(
                    label: 'Wand guidance note',
                    hintText: 'How the wand should write…',
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: _saving ? null : _resetWandDefault,
                  child: const Text('Reset wand note to default'),
                ),
                const SizedBox(height: 32),
                SettingsUi.sectionTitle(context, 'Chat composer'),
                const SizedBox(height: 8),
                SettingsUi.sectionHint(
                  context,
                  isDesktopPlatform
                      ? 'On desktop, Enter sends your message (or Continue when '
                          'the field is empty). Shift+Enter starts a new line.'
                      : 'When you use a hardware keyboard on a phone or tablet, '
                          'Enter can send instead of starting a new line.',
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Enter to send'),
                  subtitle: const Text(
                    'Off = Enter always starts a new line. On = Enter sends when '
                    'typed, or Continue when empty.',
                  ),
                  value: _enterToSend,
                  onChanged: (value) => setState(() => _enterToSend = value),
                ),
                const SizedBox(height: 32),
                SettingsUi.sectionTitle(context, 'Composer Format'),
                const SizedBox(height: 8),
                SettingsUi.sectionHint(
                  context,
                  'Used only by the ✨ Format button next to Send in chat. '
                  'Default behavior: fix caps/punctuation and add *asterisks* '
                  'and "quotes" — without rewording what you typed.',
                ),
                TextField(
                  controller: _composerFormatController,
                  minLines: 4,
                  maxLines: 10,
                  scrollPadding: SettingsUi.keyboardScrollPadding,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: SettingsUi.fieldDecoration(
                    label: 'Composer format note',
                    hintText: 'How Format should treat your draft…',
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: _saving ? null : _resetComposerDefault,
                  child: const Text('Reset Format note to default'),
                ),
                const SizedBox(height: 32),
                SettingsUi.sectionTitle(context, 'Roadway / Paths'),
                const SizedBox(height: 8),
                SettingsUi.sectionHint(
                  context,
                  'Used by the Paths button in chat. Asks the AI for several '
                  '“what could {{user}} do next?” options you can tap into '
                  'the composer and edit before sending.',
                ),
                TextField(
                  controller: _roadwayController,
                  minLines: 4,
                  maxLines: 10,
                  scrollPadding: SettingsUi.keyboardScrollPadding,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: SettingsUi.fieldDecoration(
                    label: 'Roadway note',
                    hintText: 'How Paths should brainstorm…',
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: _saving ? null : _resetRoadwayDefault,
                  child: const Text('Reset Roadway note to default'),
                ),
                const SizedBox(height: 32),
                SettingsUi.sectionTitle(context, 'Narrator'),
                const SizedBox(height: 8),
                SettingsUi.sectionHint(
                  context,
                  'Used when you tap the Narrator button in chat (not Creation '
                  'Center). Steers AI-generated omniscient scene lines.',
                ),
                TextField(
                  controller: _narratorController,
                  minLines: 4,
                  maxLines: 10,
                  scrollPadding: SettingsUi.keyboardScrollPadding,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: SettingsUi.fieldDecoration(
                    label: 'Narrator note',
                    hintText: 'How the Narrator should write…',
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: _saving ? null : _resetNarratorDefault,
                  child: const Text('Reset Narrator note to default'),
                ),
                const SizedBox(height: 8),
                Text(
                  'Wand, Format, Paths, and Narrator use your normal NanoGPT '
                  'model and generation parameters from Settings. Format also '
                  'cools temperature slightly so it stays closer to your words.',
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
