import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/api_key_service.dart';
import '../services/settings_service.dart';

/// Settings: API key, model, sampling, persona, theme, TTS.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.apiKeyService,
    required this.settingsService,
  });

  final ApiKeyService apiKeyService;
  final SettingsService settingsService;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _keyController = TextEditingController();
  final _modelController = TextEditingController();
  final _userNameController = TextEditingController();
  final _personaController = TextEditingController();
  final _temperatureController = TextEditingController();
  final _topPController = TextEditingController();
  final _maxTokensController = TextEditingController();
  bool _obscure = true;
  bool _loading = true;
  bool _savingKey = false;
  bool _savingModel = false;
  bool _savingPersona = false;
  bool _savingSampling = false;
  bool _savingLook = false;
  bool _hasKey = false;
  bool _useSubscription = false;
  bool _ttsEnabled = false;
  String _themeMode = 'system';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final key = await widget.apiKeyService.getApiKey();
    final model = await widget.settingsService.getModel();
    final userName = await widget.settingsService.getUserName();
    final persona = await widget.settingsService.getUserPersona();
    final sampling = await widget.settingsService.getSampling();
    final subscription = await widget.settingsService.getUseSubscriptionApi();
    final themeMode = await widget.settingsService.getThemeModeName();
    final tts = await widget.settingsService.getTtsEnabled();
    if (!mounted) return;
    setState(() {
      _hasKey = key != null;
      _modelController.text = model;
      _userNameController.text = userName;
      _personaController.text = persona;
      _temperatureController.text = sampling.temperature.toString();
      _topPController.text = sampling.topP.toString();
      _maxTokensController.text =
          sampling.maxTokens == null ? '' : '${sampling.maxTokens}';
      _useSubscription = subscription;
      _themeMode = themeMode;
      _ttsEnabled = tts;
      _loading = false;
    });
  }

  Future<void> _saveKey() async {
    setState(() => _savingKey = true);
    await widget.apiKeyService.saveApiKey(_keyController.text);
    if (!mounted) return;
    setState(() {
      _savingKey = false;
      _hasKey = _keyController.text.trim().isNotEmpty;
      _keyController.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _hasKey ? 'API key saved on this device.' : 'API key cleared.',
        ),
      ),
    );
  }

  Future<void> _clearKey() async {
    setState(() => _savingKey = true);
    await widget.apiKeyService.clearApiKey();
    if (!mounted) return;
    setState(() {
      _savingKey = false;
      _hasKey = false;
      _keyController.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('API key removed from this device.')),
    );
  }

  Future<void> _saveModel() async {
    final model = _modelController.text.trim();
    if (model.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a model name before saving.')),
      );
      return;
    }
    setState(() => _savingModel = true);
    await widget.settingsService.saveModel(model);
    if (!mounted) return;
    setState(() => _savingModel = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Model saved: $model')),
    );
  }

  Future<void> _savePersona() async {
    setState(() => _savingPersona = true);
    await widget.settingsService.saveUserName(_userNameController.text);
    await widget.settingsService.saveUserPersona(_personaController.text);
    if (!mounted) return;
    setState(() => _savingPersona = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Persona saved.')),
    );
  }

  Future<void> _saveSampling() async {
    final temperature =
        double.tryParse(_temperatureController.text.trim()) ??
            SamplingSettings.defaultTemperature;
    final topP = double.tryParse(_topPController.text.trim()) ??
        SamplingSettings.defaultTopP;
    final maxRaw = _maxTokensController.text.trim();
    final maxParsed = maxRaw.isEmpty ? null : int.tryParse(maxRaw);
    if (maxRaw.isNotEmpty && (maxParsed == null || maxParsed <= 0)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Max tokens must be a positive number, or blank.'),
        ),
      );
      return;
    }

    setState(() => _savingSampling = true);
    await widget.settingsService.saveSampling(
      SamplingSettings(
        temperature: temperature.clamp(0.0, 2.0),
        topP: topP.clamp(0.0, 1.0),
        maxTokens: maxParsed,
      ),
    );
    await widget.settingsService.saveUseSubscriptionApi(_useSubscription);
    if (!mounted) return;
    setState(() {
      _savingSampling = false;
      _temperatureController.text = temperature.clamp(0.0, 2.0).toString();
      _topPController.text = topP.clamp(0.0, 1.0).toString();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Sampling & API settings saved.')),
    );
  }

  Future<void> _saveLook() async {
    setState(() => _savingLook = true);
    await widget.settingsService.saveThemeModeName(_themeMode);
    await widget.settingsService.saveTtsEnabled(_ttsEnabled);
    if (!mounted) return;
    setState(() => _savingLook = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Look & sound saved.')),
    );
    Navigator.of(context).pop(true);
  }

  @override
  void dispose() {
    _keyController.dispose();
    _modelController.dispose();
    _userNameController.dispose();
    _personaController.dispose();
    _temperatureController.dispose();
    _topPController.dispose();
    _maxTokensController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  'NanoGPT API key',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  _hasKey
                      ? 'A key is saved on this device. Paste a new one below to replace it.'
                      : 'Paste your NanoGPT API key below. It stays on this phone/computer only — never in GitHub.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _keyController,
                  obscureText: _obscure,
                  autocorrect: false,
                  enableSuggestions: false,
                  keyboardType: TextInputType.visiblePassword,
                  decoration: InputDecoration(
                    labelText: 'API key',
                    hintText: 'sk-...',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      tooltip: _obscure ? 'Show' : 'Hide',
                      onPressed: () => setState(() => _obscure = !_obscure),
                      icon: Icon(
                        _obscure ? Icons.visibility : Icons.visibility_off,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _savingKey ? null : _saveKey,
                  child: _savingKey
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save API key'),
                ),
                if (_hasKey) ...[
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: _savingKey ? null : _clearKey,
                    child: const Text('Remove saved key'),
                  ),
                ],
                const SizedBox(height: 32),
                Text(
                  'AI model',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _modelController,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(
                    labelText: 'Model',
                    hintText: SettingsService.defaultModel,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _savingModel ? null : _saveModel,
                  child: _savingModel
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save model'),
                ),
                const SizedBox(height: 32),
                Text(
                  'Sampling',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'Controls how creative or focused replies feel (SillyTavern-style knobs).',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _temperatureController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Temperature (0–2)',
                    helperText: 'Higher = more creative / random. Default 0.8',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _topPController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Top P (0–1)',
                    helperText: 'Nucleus sampling. Default 0.95',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _maxTokensController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Max tokens (optional)',
                    helperText: 'Leave blank to use the model default',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Use subscription API'),
                  subtitle: Text(
                    _useSubscription
                        ? SettingsService.subscriptionBaseUrl
                        : SettingsService.defaultBaseUrl,
                  ),
                  value: _useSubscription,
                  onChanged: (v) => setState(() => _useSubscription = v),
                ),
                Text(
                  'Turn this on if you have a NanoGPT subscription and want '
                  'requests limited to subscription-included models.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _savingSampling ? null : _saveSampling,
                  child: _savingSampling
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save sampling & API'),
                ),
                const SizedBox(height: 32),
                Text(
                  'Look & sound',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                Text('Theme', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'system', label: Text('System')),
                    ButtonSegment(value: 'light', label: Text('Light')),
                    ButtonSegment(value: 'dark', label: Text('Dark')),
                  ],
                  selected: {_themeMode},
                  onSelectionChanged: (selected) {
                    setState(() => _themeMode = selected.first);
                  },
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Read replies aloud (TTS)'),
                  subtitle: const Text(
                    'Uses your phone’s voice. Long-press a message → Speak.',
                  ),
                  value: _ttsEnabled,
                  onChanged: (v) => setState(() => _ttsEnabled = v),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _savingLook ? null : _saveLook,
                  child: _savingLook
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save look & sound'),
                ),
                const SizedBox(height: 32),
                Text(
                  'Your persona',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'Used for {{user}} in character cards (SillyTavern-style).',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _userNameController,
                  textCapitalization: .words,
                  decoration: const InputDecoration(
                    labelText: 'Your name',
                    hintText: SettingsService.defaultUserName,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _personaController,
                  minLines: 3,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    labelText: 'About you (optional)',
                    hintText: 'Short description the AI should know…',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _savingPersona ? null : _savePersona,
                  child: _savingPersona
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save persona'),
                ),
                const SizedBox(height: 24),
                Text(
                  'Get a key at nano-gpt.com. Anima never writes secrets into project files.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
    );
  }
}
