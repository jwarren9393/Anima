import 'package:flutter/material.dart';

import '../services/api_key_service.dart';

/// Simple settings page where you paste your NanoGPT API key.
///
/// The key is stored only on this device via [ApiKeyService].
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.apiKeyService});

  final ApiKeyService apiKeyService;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _controller = TextEditingController();
  bool _obscure = true;
  bool _loading = true;
  bool _saving = false;
  bool _hasKey = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final key = await widget.apiKeyService.getApiKey();
    if (!mounted) return;
    setState(() {
      _hasKey = key != null;
      // Do not pre-fill the full key into the text field for safety.
      // The user can paste a new one anytime to replace it.
      _loading = false;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await widget.apiKeyService.saveApiKey(_controller.text);
    if (!mounted) return;
    setState(() {
      _saving = false;
      _hasKey = _controller.text.trim().isNotEmpty;
      _controller.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _hasKey ? 'API key saved on this device.' : 'API key cleared.',
        ),
      ),
    );
  }

  Future<void> _clear() async {
    setState(() => _saving = true);
    await widget.apiKeyService.clearApiKey();
    if (!mounted) return;
    setState(() {
      _saving = false;
      _hasKey = false;
      _controller.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('API key removed from this device.')),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
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
                  controller: _controller,
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
                  onPressed: _saving ? null : _save,
                  child: _saving
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
                    onPressed: _saving ? null : _clear,
                    child: const Text('Remove saved key'),
                  ),
                ],
                const SizedBox(height: 24),
                Text(
                  'Get a key at nano-gpt.com, then paste it here. '
                  'Anima never writes your key into project files.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
    );
  }
}
