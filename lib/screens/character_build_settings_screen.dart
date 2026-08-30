import 'package:flutter/material.dart';

import '../services/settings_service.dart';
import 'settings_ui.dart';

/// Shared model, sampling, and build prompts for character + persona JSON generation.
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
  final _characterPromptController = TextEditingController();
  final _personaPromptController = TextEditingController();
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
      _characterPromptController.text = settings.promptNote;
      _personaPromptController.text = settings.personaPromptNote;
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
        promptNote: _characterPromptController.text,
        personaPromptNote: _personaPromptController.text,
      ),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Character & persona build settings saved.')),
    );
  }

  void _resetCharacterPrompt() {
    setState(() {
      _characterPromptController.text =
          CharacterBuildSettings.defaultPromptNote;
    });
  }

  void _resetPersonaPrompt() {
    setState(() {
      _personaPromptController.text =
          CharacterBuildSettings.defaultPersonaPromptNote;
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
    _characterPromptController.dispose();
    _personaPromptController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Character & persona builds')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: SettingsUi.listPadding,
              children: [
                SettingsUi.sectionHint(
                  context,
                  'One place for full JSON card generation: character cards and '
                  'user personas from Creation Center, chat import, and the AI '
                  'builders on the character/persona editors. Field wands use '
                  'Settings → AI collaborator instead.',
                ),
                const SizedBox(height: 24),
                SettingsUi.sectionTitle(context, 'Model'),
                const SizedBox(height: 8),
                SettingsUi.sectionHint(
                  context,
                  'Shared by character and persona builds — separate from your '
                  'main chat model. Copy a model id from Settings → API & connection.',
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Use main chat model'),
                  subtitle: const Text(
                    'When off, the model id below is used for all card builds.',
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
                    label: 'Build model id',
                    hintText: 'e.g. openai/gpt-4o-mini',
                  ),
                ),
                const SizedBox(height: 32),
                SettingsUi.sectionTitle(context, 'Generation parameters'),
                const SizedBox(height: 8),
                SettingsUi.sectionHint(
                  context,
                  'Shared max tokens, temperature, and top P for character and '
                  'persona JSON builds — not normal chat, wands, or Paths.',
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
                SettingsUi.sectionTitle(context, 'Character card build prompt'),
                const SizedBox(height: 8),
                SettingsUi.sectionHint(
                  context,
                  'Extra instructions for full character card JSON (description, '
                  'personality, mes_example, tags). Used by Creation Center, chat '
                  'import, and the character editor AI builder.',
                ),
                TextField(
                  controller: _characterPromptController,
                  enabled: !_saving,
                  minLines: 5,
                  maxLines: 12,
                  scrollPadding: SettingsUi.keyboardScrollPadding,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: SettingsUi.fieldDecoration(
                    label: 'Character build prompt',
                    hintText: 'How character card builds should write…',
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: _saving ? null : _resetCharacterPrompt,
                  child: const Text('Reset character prompt to default'),
                ),
                const SizedBox(height: 32),
                SettingsUi.sectionTitle(context, 'Persona build prompt'),
                const SizedBox(height: 8),
                SettingsUi.sectionHint(
                  context,
                  'Extra instructions for full persona JSON (identity, appearance, '
                  'personality, background, goals). Used by Creation Center and the '
                  'persona editor AI builder. Leave empty to reuse the character '
                  'build prompt above.',
                ),
                TextField(
                  controller: _personaPromptController,
                  enabled: !_saving,
                  minLines: 5,
                  maxLines: 12,
                  scrollPadding: SettingsUi.keyboardScrollPadding,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: SettingsUi.fieldDecoration(
                    label: 'Persona build prompt (optional)',
                    hintText: 'How persona builds should write…',
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: _saving ? null : _resetPersonaPrompt,
                  child: const Text('Reset persona prompt to default'),
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
