import 'package:flutter/material.dart';

import '../models/anima_presets.dart';
import '../services/settings_service.dart';
import '../widgets/preset_picker.dart';
import 'settings_ui.dart';

/// App-wide system prompt + post-history for every chat.
class GlobalChatPromptsScreen extends StatefulWidget {
  const GlobalChatPromptsScreen({
    super.key,
    required this.settingsService,
  });

  final SettingsService settingsService;

  @override
  State<GlobalChatPromptsScreen> createState() =>
      _GlobalChatPromptsScreenState();
}

class _GlobalChatPromptsScreenState extends State<GlobalChatPromptsScreen> {
  final _systemController = TextEditingController();
  final _postHistoryController = TextEditingController();
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final settings = await widget.settingsService.getGlobalChatPromptSettings();
    if (!mounted) return;
    setState(() {
      _systemController.text = settings.systemPrompt;
      _postHistoryController.text = settings.postHistoryInstructions;
      _loading = false;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await widget.settingsService.saveGlobalChatPromptSettings(
      GlobalChatPromptSettings(
        systemPrompt: _systemController.text,
        postHistoryInstructions: _postHistoryController.text,
      ),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Global chat prompts saved.')),
    );
  }

  Future<void> _pickSystemPreset() async {
    final preset = await pickTextPreset(
      context: context,
      title: 'System prompt presets',
      presets: AnimaPresets.systemPrompts,
    );
    if (preset == null || !mounted) return;
    setState(() => _systemController.text = preset.text);
  }

  Future<void> _pickPostHistoryPreset() async {
    final preset = await pickTextPreset(
      context: context,
      title: 'Post-history presets',
      presets: AnimaPresets.postHistory,
    );
    if (preset == null || !mounted) return;
    setState(() => _postHistoryController.text = preset.text);
  }

  void _clearAll() {
    setState(() {
      _systemController.clear();
      _postHistoryController.clear();
    });
  }

  @override
  void dispose() {
    _systemController.dispose();
    _postHistoryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Global chat prompts')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: SettingsUi.listPadding,
              children: [
                SettingsUi.sectionHint(
                  context,
                  'These apply to every chat and merge with each character card. '
                  'Card fields are kept — global text is added on top. '
                  'Per-chat Author\'s Note still applies too. '
                  'Supports {{user}} and {{char}}.',
                ),
                const SizedBox(height: 24),
                SettingsUi.sectionTitle(context, 'Global system prompt'),
                const SizedBox(height: 8),
                SettingsUi.sectionHint(
                  context,
                  'Added to the system message on every reply (after the card '
                  'and your persona). Same role as a card\'s System prompt field.',
                ),
                PresetButton(
                  label: 'System prompt presets',
                  onPressed: _pickSystemPreset,
                ),
                TextField(
                  controller: _systemController,
                  enabled: !_saving,
                  minLines: 5,
                  maxLines: 14,
                  scrollPadding: SettingsUi.keyboardScrollPadding,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: SettingsUi.fieldDecoration(
                    label: 'Global system prompt (optional)',
                    hintText: 'Formatting rules, roleplay style, etc.',
                  ),
                ),
                const SizedBox(height: 32),
                SettingsUi.sectionTitle(context, 'Global post-history'),
                const SizedBox(height: 8),
                SettingsUi.sectionHint(
                  context,
                  'Injected after chat history each turn — before the card\'s '
                  'Post-history instructions and this chat\'s Author\'s Note.',
                ),
                PresetButton(
                  label: 'Post-history presets',
                  onPressed: _pickPostHistoryPreset,
                ),
                TextField(
                  controller: _postHistoryController,
                  enabled: !_saving,
                  minLines: 5,
                  maxLines: 14,
                  scrollPadding: SettingsUi.keyboardScrollPadding,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: SettingsUi.fieldDecoration(
                    label: 'Global post-history (optional)',
                    hintText: 'Length limits, dialogue priority, etc.',
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: _saving ? null : _clearAll,
                  child: const Text('Clear both fields'),
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
