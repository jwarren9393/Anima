import 'package:flutter/material.dart';

import '../services/api_key_service.dart';
import '../services/settings_service.dart';

/// Settings: API key, model, and your persona (for {{user}} macros).
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
  bool _obscure = true;
  bool _loading = true;
  bool _savingKey = false;
  bool _savingModel = false;
  bool _savingPersona = false;
  bool _hasKey = false;

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
    if (!mounted) return;
    setState(() {
      _hasKey = key != null;
      _modelController.text = model;
      _userNameController.text = userName;
      _personaController.text = persona;
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

  @override
  void dispose() {
    _keyController.dispose();
    _modelController.dispose();
    _userNameController.dispose();
    _personaController.dispose();
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
