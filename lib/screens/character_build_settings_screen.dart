import 'package:flutter/material.dart';

import '../services/settings_service.dart';
import 'settings_ui.dart';

/// Model, sampling, and prompt for full character card JSON generation.
class CharacterBuildSettingsScreen extends StatefulWidget {
  const CharacterBuildSettingsScreen({
    super.key,
    required this.settingsService,
  });

  final SettingsService settingsService;

  @override
  State<CharacterBuildSettingsScreen> createState() =>
      _CharacterBuildSettingsScreenState();
}

class _CharacterBuildSettingsScreenState
    extends State<CharacterBuildSettingsScreen> {
  final _modelController = TextEditingController();
  final _maxTokensController = TextEditingController();
  final _temperatureController = TextEditingController();
  final _topPController = TextEditingController();
  final _promptController = TextEditingController();
  bool _useMainChatModel = true;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final settings = await widget.settingsService.getCharacterBuildSettings();
    if (!mounted) return;
    setState(() {
      _useMainChatModel = settings.useMainChatModel;
      _modelController.text = settings.modelId;
      _maxTokensController.text = '${settings.maxTokens}';
      _temperatureController.text = settings.temperature.toString();
      _topPController.text = settings.topP.toString();
      _promptController.text = settings.promptNote;
      _loading = false;
    });
  }

  Future<void> _save() async {
    final maxTokens = int.tryParse(_maxTokensController.text.trim());
    final temperature = double.tryParse(_temperatureController.text.trim());
    final topP = double.tryParse(_topPController.text.trim());
    if (maxTokens == null || temperature == null || topP == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Check max tokens, temperature, and top P are numbers.'),
        ),
      );
      return;
    }

    setState(() => _saving = true);
    await widget.settingsService.saveCharacterBuildSettings(
      CharacterBuildSettings(
        useMainChatModel: _useMainChatModel,
        modelId: _modelController.text,
        maxTokens: maxTokens,
        temperature: temperature,
        topP: topP,
        promptNote: _promptController.text,
      ),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Character build settings saved.')),
    );
  }

  void _resetPrompt() {
    setState(() {
      _promptController.text = CharacterBuildSettings.defaultPromptNote;
    });
  }

  void _resetSampling() {
    setState(() {
      _maxTokensController.text = '${CharacterBuildSettings.defaultMaxTokens}';
      _temperatureController.text =
          CharacterBuildSettings.defaultTemperature.toString();
      _topPController.text = CharacterBuildSettings.defaultTopP.toString();
    });
  }

  @override
  void dispose() {
    _modelController.dispose();
    _maxTokensController.dispose();
    _temperatureController.dispose();
    _topPController.dispose();
    _promptController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Character builds')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: SettingsUi.listPadding,
              children: [
                SettingsUi.sectionTitle(context, 'Model'),
                const SizedBox(height: 8),
                SettingsUi.sectionHint(
                  context,
                  'Used when generating a full character card from chat or '
                  'Creation Center — separate from your main chat model. '
                  'Copy a model id from Settings → API & connection.',
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Use main chat model'),
                  subtitle: const Text(
                    'When off, the model id below is used for card builds only.',
                  ),
                  value: _useMainChatModel,
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _useMainChatModel = value),
                ),
                TextField(
                  controller: _modelController,
                  enabled: !_saving && !_useMainChatModel,
                  scrollPadding: SettingsUi.keyboardScrollPadding,
                  decoration: SettingsUi.fieldDecoration(
                    label: 'Card build model id',
                    hintText: 'e.g. openai/gpt-4o-mini',
                  ),
                ),
                const SizedBox(height: 32),
                SettingsUi.sectionTitle(context, 'Generation parameters'),
                const SizedBox(height: 8),
                SettingsUi.sectionHint(
                  context,
                  'Only apply to full card JSON generation — not normal chat, '
                  'wands, or Paths.',
                ),
                TextField(
                  controller: _maxTokensController,
                  enabled: !_saving,
                  keyboardType: TextInputType.number,
                  scrollPadding: SettingsUi.keyboardScrollPadding,
                  decoration: SettingsUi.fieldDecoration(
                    label: 'Max tokens',
                    hintText: '${CharacterBuildSettings.defaultMaxTokens}',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _temperatureController,
                  enabled: !_saving,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  scrollPadding: SettingsUi.keyboardScrollPadding,
                  decoration: SettingsUi.fieldDecoration(
                    label: 'Temperature',
                    hintText: '${CharacterBuildSettings.defaultTemperature}',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _topPController,
                  enabled: !_saving,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  scrollPadding: SettingsUi.keyboardScrollPadding,
                  decoration: SettingsUi.fieldDecoration(
                    label: 'Top P',
                    hintText: '${CharacterBuildSettings.defaultTopP}',
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: _saving ? null : _resetSampling,
                  child: const Text('Reset parameters to defaults'),
                ),
                const SizedBox(height: 32),
                SettingsUi.sectionTitle(context, 'Build prompt'),
                const SizedBox(height: 8),
                SettingsUi.sectionHint(
                  context,
                  'Extra instructions sent with every full card build request. '
                  'Does not affect per-field wands on the character editor.',
                ),
                TextField(
                  controller: _promptController,
                  enabled: !_saving,
                  minLines: 5,
                  maxLines: 12,
                  scrollPadding: SettingsUi.keyboardScrollPadding,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: SettingsUi.fieldDecoration(
                    label: 'Card build prompt',
                    hintText: 'How card builds should write…',
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: _saving ? null : _resetPrompt,
                  child: const Text('Reset prompt to default'),
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
