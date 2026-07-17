import 'package:flutter/material.dart';

import '../services/api_key_service.dart';
import '../services/nanogpt_service.dart';
import '../services/settings_service.dart';
import 'settings_ui.dart';

/// API key, model catalog dropdowns, and subscription endpoint toggle.
class ApiSettingsScreen extends StatefulWidget {
  const ApiSettingsScreen({
    super.key,
    required this.apiKeyService,
    required this.settingsService,
    required this.nanoGptService,
  });

  final ApiKeyService apiKeyService;
  final SettingsService settingsService;
  final NanoGptService nanoGptService;

  @override
  State<ApiSettingsScreen> createState() => _ApiSettingsScreenState();
}

class _ApiSettingsScreenState extends State<ApiSettingsScreen> {
  final _keyController = TextEditingController();
  final _modelController = TextEditingController();
  bool _obscure = true;
  bool _loading = true;
  bool _savingKey = false;
  bool _savingModel = false;
  bool _hasKey = false;
  bool _useSubscription = false;

  bool _loadingModels = false;
  String? _modelsError;
  List<NanoGptModelInfo> _models = const [];
  String? _selectedProvider;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final key = await widget.apiKeyService.getApiKey();
    final model = await widget.settingsService.getModel();
    final subscription = await widget.settingsService.getUseSubscriptionApi();
    if (!mounted) return;
    setState(() {
      _hasKey = key != null;
      _modelController.text = model;
      _useSubscription = subscription;
      _loading = false;
    });
    await _loadModels();
  }

  String _baseUrlForCatalog() => _useSubscription
      ? SettingsService.subscriptionBaseUrl
      : SettingsService.defaultBaseUrl;

  Future<void> _loadModels() async {
    setState(() {
      _loadingModels = true;
      _modelsError = null;
    });
    try {
      final models = await widget.nanoGptService.listModels(
        baseUrl: _baseUrlForCatalog(),
      );
      if (!mounted) return;
      setState(() {
        _models = models;
        _loadingModels = false;
        _selectedProvider = _providerForCurrentModel();
      });
    } on NanoGptException catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingModels = false;
        _modelsError = error.message;
        _models = const [];
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingModels = false;
        _modelsError = 'Could not load models: $error';
        _models = const [];
      });
    }
  }

  String? _providerForCurrentModel() {
    final current = _modelController.text.trim();
    if (current.isEmpty || _models.isEmpty) {
      return _models.isEmpty ? null : _providers.first;
    }
    for (final model in _models) {
      if (model.id == current) return model.ownedBy;
    }
    return _providers.isEmpty ? null : _providers.first;
  }

  List<String> get _providers {
    final seen = <String>{};
    final list = <String>[];
    for (final model in _models) {
      if (seen.add(model.ownedBy)) list.add(model.ownedBy);
    }
    // Auto first, then A–Z (catalog is already sorted this way; keep stable).
    list.sort((a, b) {
      if (a == NanoGptService.autoProviderLabel &&
          b != NanoGptService.autoProviderLabel) {
        return -1;
      }
      if (b == NanoGptService.autoProviderLabel &&
          a != NanoGptService.autoProviderLabel) {
        return 1;
      }
      return a.toLowerCase().compareTo(b.toLowerCase());
    });
    return list;
  }

  List<NanoGptModelInfo> get _modelsForProvider {
    final provider = _selectedProvider;
    if (provider == null) return const [];
    return _models.where((m) => m.ownedBy == provider).toList();
  }

  String? get _selectedModelId {
    final current = _modelController.text.trim();
    if (current.isEmpty) return null;
    for (final model in _modelsForProvider) {
      if (model.id == current) return current;
    }
    return null;
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
    await _loadModels();
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
        const SnackBar(content: Text('Enter or pick a model before saving.')),
      );
      return;
    }
    setState(() => _savingModel = true);
    await widget.settingsService.saveModel(model);
    await widget.settingsService.saveUseSubscriptionApi(_useSubscription);
    if (!mounted) return;
    setState(() => _savingModel = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Model & connection saved: $model')),
    );
  }

  Future<void> _onSubscriptionChanged(bool value) async {
    setState(() => _useSubscription = value);
    await _loadModels();
  }

  @override
  void dispose() {
    _keyController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final providers = _providers;
    final modelsForProvider = _modelsForProvider;

    return Scaffold(
      appBar: AppBar(title: const Text('API & connection')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: SettingsUi.listPadding,
              children: [
                SettingsUi.sectionTitle(context, 'NanoGPT API key'),
                const SizedBox(height: 8),
                SettingsUi.sectionHint(
                  context,
                  _hasKey
                      ? 'A key is saved on this device. Paste a new one below to replace it.'
                      : 'Paste your NanoGPT API key below. It stays on this phone only — never in GitHub.',
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
                SettingsUi.saveButton(
                  saving: _savingKey,
                  label: 'Save API key',
                  onPressed: _savingKey ? null : _saveKey,
                ),
                if (_hasKey) ...[
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: _savingKey ? null : _clearKey,
                    child: const Text('Remove saved key'),
                  ),
                ],
                const SizedBox(height: 32),
                SettingsUi.sectionTitle(context, 'AI model'),
                const SizedBox(height: 8),
                SettingsUi.sectionHint(
                  context,
                  'Pick a provider (Auto is NanoGPT’s automatic router), then a '
                  'model. Lists are sorted A–Z. You can still type a custom '
                  'model id below.',
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _loadingModels
                            ? 'Loading models from NanoGPT…'
                            : _modelsError != null
                                ? 'Could not load catalog'
                                : '${_models.length} models · ${providers.length} providers',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Refresh model list',
                      onPressed: _loadingModels ? null : _loadModels,
                      icon: _loadingModels
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh),
                    ),
                  ],
                ),
                if (_modelsError != null) ...[
                  Text(
                    _modelsError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (!_loadingModels && _models.isNotEmpty) ...[
                  DropdownButtonFormField<String>(
                    key: ValueKey('provider-$_selectedProvider'),
                    initialValue: _selectedProvider != null &&
                            providers.contains(_selectedProvider)
                        ? _selectedProvider
                        : null,
                    isExpanded: true,
                    decoration: SettingsUi.fieldDecoration(
                      label: 'Provider',
                      helperText: 'Auto first, then A–Z by provider',
                    ),
                    items: [
                      for (final provider in providers)
                        DropdownMenuItem(
                          value: provider,
                          child: Text(provider),
                        ),
                    ],
                    onChanged: (provider) {
                      if (provider == null) return;
                      setState(() {
                        _selectedProvider = provider;
                        final forProvider = _models
                            .where((m) => m.ownedBy == provider)
                            .toList();
                        if (forProvider.isEmpty) return;
                        final stillValid = forProvider.any(
                          (m) => m.id == _modelController.text.trim(),
                        );
                        if (!stillValid) {
                          _modelController.text = forProvider.first.id;
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    key: ValueKey(
                      'model-$_selectedProvider-$_selectedModelId',
                    ),
                    initialValue: _selectedModelId,
                    isExpanded: true,
                    decoration: SettingsUi.fieldDecoration(
                      label: 'Model',
                      helperText: modelsForProvider.isEmpty
                          ? 'Pick a provider first'
                          : '${modelsForProvider.length} models from $_selectedProvider',
                    ),
                    items: [
                      for (final model in modelsForProvider)
                        DropdownMenuItem(
                          value: model.id,
                          child: Text(
                            model.displayName,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: modelsForProvider.isEmpty
                        ? null
                        : (id) {
                            if (id == null) return;
                            setState(() => _modelController.text = id);
                          },
                  ),
                  const SizedBox(height: 16),
                ],
                TextField(
                  controller: _modelController,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: SettingsUi.fieldDecoration(
                    label: 'Model id (saved value)',
                    hintText: SettingsService.defaultModel,
                    helperText:
                        'Filled by the dropdowns, or type a custom id yourself',
                  ),
                  onChanged: (_) {
                    setState(() {
                      _selectedProvider = _providerForCurrentModel();
                    });
                  },
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
                  onChanged: _loadingModels ? null : _onSubscriptionChanged,
                ),
                SettingsUi.sectionHint(
                  context,
                  'Turn this on if you have a NanoGPT subscription and want '
                  'requests limited to subscription-included models. The model '
                  'list refreshes for that catalog.',
                ),
                const SizedBox(height: 16),
                SettingsUi.saveButton(
                  saving: _savingModel,
                  label: 'Save model & connection',
                  onPressed: _savingModel ? null : _saveModel,
                ),
              ],
            ),
    );
  }
}
