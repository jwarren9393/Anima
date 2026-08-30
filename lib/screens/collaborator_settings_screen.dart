import 'package:flutter/material.dart';

import '../models/anima_presets.dart';
import '../services/settings_service.dart';
import '../utils/platform_utils.dart';
import '../widgets/preset_picker.dart';
import 'settings_ui.dart';

/// Settings for character/lore wand guidance + chat composer options.
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
  final _roadwayController = TextEditingController();
  final _narratorController = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  bool _enterToSend = true;
  bool _autoWrapDialogueOnSend = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final settings = await widget.settingsService.getCollaboratorSettings();
    final enterToSend = await widget.settingsService.getEnterToSendComposer();
    final autoWrapDialogue =
        await widget.settingsService.getAutoWrapDialogueOnSend();
    if (!mounted) return;
    setState(() {
      _guidanceController.text = settings.guidanceNote;
      _roadwayController.text = settings.roadwayNote;
      _narratorController.text = settings.narratorNote;
      _enterToSend = enterToSend;
      _autoWrapDialogueOnSend = autoWrapDialogue;
      _loading = false;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await widget.settingsService.saveCollaboratorSettings(
      CollaboratorSettings(
        guidanceNote: _guidanceController.text,
        roadwayNote: _roadwayController.text,
        narratorNote: _narratorController.text,
      ),
    );
    await widget.settingsService.saveEnterToSendComposer(_enterToSend);
    await widget.settingsService.saveAutoWrapDialogueOnSend(
      _autoWrapDialogueOnSend,
    );
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
                  'Sent with per-field sparkle wands on character, persona, and '
                  'World Info editors — one field at a time, not full card builds. '
                  'Also steers Creation Center brainstorming chat. Full character '
                  'and persona JSON builds use Settings → Character & persona builds.',
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
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Auto-wrap dialogue on send'),
                  subtitle: const Text(
                    'Wraps plain text in "quotes" on send — *actions* stay as '
                    'asterisks. No AI, no extra taps. Turn off if you prefer '
                    'raw text.',
                  ),
                  value: _autoWrapDialogueOnSend,
                  onChanged: (value) =>
                      setState(() => _autoWrapDialogueOnSend = value),
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
                  'Wand, Paths, and Narrator use your main chat model and '
                  'generation parameters from Settings → Generation parameters.',
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
