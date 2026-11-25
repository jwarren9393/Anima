import 'package:flutter/material.dart';

import '../services/api_key_service.dart';
import '../services/nanogpt_service.dart';
import '../services/settings_service.dart';
import '../widgets/text_model_catalog_widgets.dart';
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
  final _imageModelController = TextEditingController();
  bool _obscure = true;
  bool _loading = true;
  bool _savingKey = false;
  bool _savingModel = false;
  bool _checkingCredits = false;
  bool _hasKey = false;
  bool _useSubscription = false;

  bool _loadingModels = false;
  String? _modelsError;
  List<NanoGptModelInfo> _models = const [];
  String? _selectedProvider;
  String _selectedCategoryFilter = NanoGptTextModelCatalogFilter.allId;
  String _selectedContextFilter = NanoGptTextModelPerformanceFilter.contextAllId;

  bool _loadingImageModels = false;
  String? _imageModelsError;
  List<NanoGptImageModelInfo> _imageModels = const [];
  bool _loadingSelectedRuntime = false;
  List<FavoriteModel> _favorites = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final key = await widget.apiKeyService.getApiKey();
    final model = await widget.settingsService.getModel();
    final imageModel = await widget.settingsService.getImageModel();
    final subscription = await widget.settingsService.getUseSubscriptionApi();
    final favorites = await widget.settingsService.getFavoriteModels();
    if (!mounted) return;
    setState(() {
      _hasKey = key != null;
      _modelController.text = model;
      _imageModelController.text = imageModel;
      _useSubscription = subscription;
      _favorites = favorites;
      _loading = false;
    });
    await Future.wait([_loadModels(), _loadImageModels()]);
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
        if (!NanoGptTextModelCatalogFilter.categoryFilterIds(models)
            .contains(_selectedCategoryFilter)) {
          _selectedCategoryFilter = NanoGptTextModelCatalogFilter.allId;
        }
        _selectedProvider = _providerForCurrentModel();
        _syncProviderAfterCatalogChange();
      });
      await _refreshSelectedRuntimeStats();
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

  List<NanoGptModelInfo> get _modelsForCategory {
    return NanoGptTextModelCatalogFilter.apply(
      _models,
      _selectedCategoryFilter,
    );
  }

  List<NanoGptModelInfo> get _modelsAfterContext {
    return NanoGptTextModelPerformanceFilter.applyContext(
      _modelsForCategory,
      _selectedContextFilter,
    );
  }

  List<String> get _categoryFilters =>
      NanoGptTextModelCatalogFilter.categoryFilterIds(_models);

  List<String> get _providers {
    final seen = <String>{};
    final list = <String>[];
    for (final model in _modelsAfterContext) {
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
    return _modelsAfterContext.where((m) => m.ownedBy == provider).toList();
  }

  void _syncProviderAfterCatalogChange() {
    final providers = _providers;
    if (providers.isEmpty) {
      _selectedProvider = null;
      return;
    }
    if (_selectedProvider == null || !providers.contains(_selectedProvider)) {
      _selectedProvider = providers.first;
    }
    final forProvider = _modelsForProvider;
    if (forProvider.isEmpty) return;
    final current = _modelController.text.trim();
    final stillValid = forProvider.any((m) => m.id == current);
    if (!stillValid) {
      _modelController.text = forProvider.first.id;
    }
  }

  void _onContextFilterChanged(String? filterId) {
    if (filterId == null) return;
    setState(() {
      _selectedContextFilter = filterId;
      _syncProviderAfterCatalogChange();
    });
  }

  void _onCategoryFilterChanged(String? filterId) {
    if (filterId == null) return;
    setState(() {
      _selectedCategoryFilter = filterId;
      _syncProviderAfterCatalogChange();
    });
  }

  NanoGptModelInfo? get _selectedModelInfo {
    final id = _modelController.text.trim();
    if (id.isEmpty) return null;
    for (final model in _models) {
      if (model.id == id) return model;
    }
    return null;
  }

  Set<String> get _favoriteIds =>
      {for (final favorite in _favorites) favorite.id};

  /// Star / unstar the model currently in the id field.
  Future<void> _toggleFavoriteCurrent() async {
    final model = _modelController.text.trim();
    if (model.isEmpty) return;
    final provider = _selectedModelInfo?.ownedBy ?? '';
    await widget.settingsService.toggleFavoriteModel(
      model,
      provider: provider,
    );
    final favorites = await widget.settingsService.getFavoriteModels();
    if (!mounted) return;
    setState(() => _favorites = favorites);
  }

  /// Apply a favorited model id to the field (not saved until Save).
  Future<void> _onPickFavorite(String id) async {
    setState(() {
      _modelController.text = id;
      _selectedProvider = _providerForCurrentModel();
    });
    await _refreshSelectedRuntimeStats();
  }

  Future<void> _refreshSelectedRuntimeStats() async {
    final id = _modelController.text.trim();
    if (id.isEmpty) return;
    setState(() => _loadingSelectedRuntime = true);
    await widget.nanoGptService.fetchModelRuntimeStats(id);
    if (!mounted) return;
    setState(() => _loadingSelectedRuntime = false);
  }

  Future<void> _openModelPicker() async {
    final models = _modelsForProvider;
    if (models.isEmpty) return;
    final picked = await showTextModelPickerSheet(
      context: context,
      models: models,
      selectedId: _modelController.text.trim(),
      nanoGptService: widget.nanoGptService,
      initialContextFilter: _selectedContextFilter,
      favoriteIds: _favoriteIds,
      onToggleFavorite: (model) async {
        await widget.settingsService.toggleFavoriteModel(
          model.id,
          provider: model.ownedBy,
        );
        final favorites = await widget.settingsService.getFavoriteModels();
        if (!mounted) return;
        setState(() => _favorites = favorites);
      },
    );
    if (picked == null || !mounted) return;
    setState(() => _modelController.text = picked);
    await _refreshSelectedRuntimeStats();
  }

  Future<void> _loadImageModels() async {
    setState(() {
      _loadingImageModels = true;
      _imageModelsError = null;
    });
    try {
      final models = await widget.nanoGptService.listImageModels(
        subscriptionOnly: _useSubscription,
      );
      if (!mounted) return;
      setState(() {
        _imageModels = models;
        _loadingImageModels = false;
        final current = _imageModelController.text.trim();
        final known = models.any((m) => m.id == current);
        if (!known) {
          _imageModelController.text = models.isNotEmpty
              ? models.first.id
              : SettingsService.defaultImageModel;
        }
      });
    } on NanoGptException catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingImageModels = false;
        _imageModelsError = error.message;
        _imageModels = const [];
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingImageModels = false;
        _imageModelsError = 'Could not load image models: $error';
        _imageModels = const [];
      });
    }
  }

  String? get _selectedImageModelId {
    final current = _imageModelController.text.trim();
    if (current.isEmpty) return null;
    for (final model in _imageModels) {
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
    await _loadImageModels();
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
    await widget.settingsService.saveImageModel(
      _imageModelController.text.trim(),
    );
    await widget.settingsService.saveUseSubscriptionApi(_useSubscription);
    if (!mounted) return;
    setState(() => _savingModel = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Model & connection saved: $model')),
    );
  }

  Future<void> _onSubscriptionChanged(bool value) async {
    setState(() => _useSubscription = value);
    await Future.wait([_loadModels(), _loadImageModels()]);
  }

  Future<void> _showCredits() async {
    if (_checkingCredits || !_hasKey) return;
    setState(() => _checkingCredits = true);
    try {
      final credits = await widget.nanoGptService.getCredits();
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (context) => _CreditsSheet(credits: credits),
      );
    } on NanoGptException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not check NanoGPT credits: $error')),
      );
    } finally {
      if (mounted) setState(() => _checkingCredits = false);
    }
  }

  @override
  void dispose() {
    _keyController.dispose();
    _modelController.dispose();
    _imageModelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final providers = _providers;
    final modelsForProvider = _modelsForProvider;
    final categoryFilters = _categoryFilters;
    final filteredModelCount = _modelsAfterContext.length;

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
                  OutlinedButton.icon(
                    onPressed: (_savingKey || _checkingCredits)
                        ? null
                        : _showCredits,
                    icon: _checkingCredits
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.account_balance_wallet_outlined),
                    label: Text(
                      _checkingCredits
                          ? 'Checking credits…'
                          : 'See remaining credits',
                    ),
                  ),
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
                  'Filter by category, context size, then provider. In Browse models, '
                  'filter or sort by TPS and TTFT (latency) after stats load. Custom '
                  'model id still works below.',
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
                                : '$filteredModelCount of ${_models.length} models · '
                                    '${providers.length} providers',
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
                    key: ValueKey('category-$_selectedCategoryFilter'),
                    initialValue: categoryFilters.contains(
                      _selectedCategoryFilter,
                    )
                        ? _selectedCategoryFilter
                        : NanoGptTextModelCatalogFilter.allId,
                    isExpanded: true,
                    decoration: SettingsUi.fieldDecoration(
                      label: 'Category',
                      helperText: _selectedCategoryFilter ==
                              NanoGptTextModelCatalogFilter.uncensoredFriendlyId
                          ? 'NanoGPT Uncensored category + any id/name with '
                              'uncensored, abliterated, or derestricted'
                          : '$filteredModelCount models in this filter',
                    ),
                    items: [
                      for (final filterId in categoryFilters)
                        DropdownMenuItem(
                          value: filterId,
                          child: Text(
                            NanoGptTextModelCatalogFilter.labelFor(filterId),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: _onCategoryFilterChanged,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    key: ValueKey('context-$_selectedContextFilter'),
                    initialValue: NanoGptTextModelPerformanceFilter.contextFilterIds
                            .contains(_selectedContextFilter)
                        ? _selectedContextFilter
                        : NanoGptTextModelPerformanceFilter.contextAllId,
                    isExpanded: true,
                    decoration: SettingsUi.fieldDecoration(
                      label: 'Min context',
                      helperText: '$filteredModelCount models meet this window',
                    ),
                    items: [
                      for (final filterId
                          in NanoGptTextModelPerformanceFilter.contextFilterIds)
                        DropdownMenuItem(
                          value: filterId,
                          child: Text(
                            NanoGptTextModelPerformanceFilter.labelForContext(
                              filterId,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: _onContextFilterChanged,
                  ),
                  const SizedBox(height: 12),
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
                        final forProvider = _modelsForProvider;
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
                  if (modelsForProvider.isEmpty)
                    Text(
                      'No models for this provider in the current category filter.',
                      style: Theme.of(context).textTheme.bodySmall,
                    )
                  else ...[
                    if (_selectedModelInfo != null)
                      TextModelSummaryCard(
                        model: _selectedModelInfo!,
                        runtimeStats: widget.nanoGptService.cachedRuntimeStats(
                          _selectedModelInfo!.id,
                        ),
                        loadingRuntime: _loadingSelectedRuntime,
                        onBrowse: _openModelPicker,
                      )
                    else if (_modelController.text.trim().isNotEmpty)
                      Card(
                        margin: EdgeInsets.zero,
                        child: ListTile(
                          title: Text(_modelController.text.trim()),
                          subtitle: const Text(
                            'Custom model id — stats load when NanoGPT recognizes it',
                          ),
                        ),
                      ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _openModelPicker,
                      icon: const Icon(Icons.view_list_outlined),
                      label: Text(
                        'Browse ${modelsForProvider.length} models',
                      ),
                    ),
                  ],
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
                    suffixIcon: IconButton(
                      tooltip: _favoriteIds.contains(
                            _modelController.text.trim(),
                          )
                          ? 'Remove from favorites'
                          : 'Save as favorite',
                      onPressed: _modelController.text.trim().isEmpty
                          ? null
                          : _toggleFavoriteCurrent,
                      icon: Icon(
                        _favoriteIds.contains(_modelController.text.trim())
                            ? Icons.star
                            : Icons.star_border,
                        color: _favoriteIds.contains(
                              _modelController.text.trim(),
                            )
                            ? Theme.of(context).colorScheme.tertiary
                            : null,
                      ),
                    ),
                  ),
                  onChanged: (_) {
                    setState(() {
                      _selectedProvider = _providerForCurrentModel();
                    });
                    _refreshSelectedRuntimeStats();
                  },
                ),
                if (_favorites.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    key: ValueKey('fav-${_modelController.text.trim()}'),
                    initialValue:
                        _favoriteIds.contains(_modelController.text.trim())
                            ? _modelController.text.trim()
                            : null,
                    isExpanded: true,
                    decoration: SettingsUi.fieldDecoration(
                      label: 'Favorite models',
                      helperText: 'Your starred models — tap to switch',
                    ),
                    items: [
                      for (final favorite in _favorites)
                        DropdownMenuItem(
                          value: favorite.id,
                          child: Text(
                            favorite.provider.isEmpty
                                ? favorite.id
                                : '${favorite.id}  ·  ${favorite.provider}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (id) {
                      if (id == null || id == _modelController.text.trim()) {
                        return;
                      }
                      _onPickFavorite(id);
                    },
                  ),
                ] else ...[
                  const SizedBox(height: 8),
                  Text(
                    'No favorite models yet — tap the star to remember the '
                    'current model, or star rows in Browse models.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
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
                const SizedBox(height: 32),
                SettingsUi.sectionTitle(context, 'Image model (avatars)'),
                const SizedBox(height: 8),
                SettingsUi.sectionHint(
                  context,
                  _useSubscription
                      ? 'Use subscription API is ON — only NanoGPT subscription '
                          'image models are listed (uses your image allowance, '
                          'not wallet money).'
                      : 'Use subscription API is OFF — the full image catalog is '
                          'shown. Paid models can charge wallet money. Turn the '
                          'toggle on above to hide them.',
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _loadingImageModels
                            ? 'Loading image models…'
                            : _imageModelsError != null
                                ? 'Could not load image catalog'
                                : _useSubscription
                                    ? '${_imageModels.length} subscription image models'
                                    : '${_imageModels.length} image models',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Refresh image models',
                      onPressed:
                          _loadingImageModels ? null : _loadImageModels,
                      icon: _loadingImageModels
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh),
                    ),
                  ],
                ),
                if (_imageModelsError != null) ...[
                  Text(
                    _imageModelsError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (!_loadingImageModels && _imageModels.isNotEmpty) ...[
                  DropdownButtonFormField<String>(
                    key: ValueKey(
                      'image-model-$_useSubscription-$_selectedImageModelId',
                    ),
                    initialValue: _selectedImageModelId,
                    isExpanded: true,
                    decoration: SettingsUi.fieldDecoration(
                      label: 'Image model',
                      helperText: _useSubscription
                          ? 'Subscription-included only'
                          : 'Included models listed first',
                    ),
                    items: [
                      for (final model in _imageModels)
                        DropdownMenuItem(
                          value: model.id,
                          child: Text(
                            _imageModelLabel(model),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (id) {
                      if (id == null) return;
                      setState(() => _imageModelController.text = id);
                    },
                  ),
                  const SizedBox(height: 16),
                ],
                TextField(
                  controller: _imageModelController,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: SettingsUi.fieldDecoration(
                    label: 'Image model id (saved value)',
                    hintText: SettingsService.defaultImageModel,
                    helperText: _useSubscription
                        ? 'Must be a subscription image model while the toggle is on'
                        : 'Filled by the dropdown, or type a custom image model id',
                  ),
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

  String _imageModelLabel(NanoGptImageModelInfo model) {
    final bits = <String>[model.displayName];
    if (model.subscriptionIncluded) {
      bits.add('Included');
    } else if (!_useSubscription) {
      bits.add('Paid');
    }
    if (model.nsfw) bits.add('NSFW');
    if (!model.subscriptionIncluded && model.pricePerImageUsd != null) {
      bits.add('\$${model.pricePerImageUsd!.toStringAsFixed(3)}');
    }
    return bits.join(' · ');
  }
}

class _CreditsSheet extends StatelessWidget {
  const _CreditsSheet({required this.credits});

  final NanoGptCredits credits;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final usage = <Widget>[
      if (credits.weeklyTokens != null)
        _UsageCard(
          title: 'Weekly input credits',
          usage: credits.weeklyTokens!,
        ),
      if (credits.dailyTokens != null)
        _UsageCard(
          title: 'Daily input credits',
          usage: credits.dailyTokens!,
        ),
      if (credits.dailyImages != null)
        _UsageCard(
          title: 'Daily images',
          usage: credits.dailyImages!,
        ),
      if (credits.monthlyUsage != null)
        _UsageCard(
          title: 'Monthly usage',
          usage: credits.monthlyUsage!,
        ),
    ];

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.82,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Text('NanoGPT credits', style: theme.textTheme.titleLarge),
            const SizedBox(height: 16),
            Text('Wallet', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            if (credits.balanceUnavailable)
              const Text('Wallet balance is temporarily unavailable.')
            else
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Icon(Icons.account_balance_wallet_outlined),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          credits.usdBalance == null
                              ? 'USD balance unavailable'
                              : '\$${credits.usdBalance!.toStringAsFixed(2)}',
                          style: theme.textTheme.headlineSmall,
                        ),
                      ),
                      if (credits.nanoBalance != null)
                        Text(
                          '${_compact(credits.nanoBalance!)} NANO',
                          style: theme.textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Subscription usage',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                Text(
                  credits.subscriptionActive
                      ? 'Active'
                      : (credits.subscriptionState.isEmpty
                          ? 'Not active'
                          : credits.subscriptionState),
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: credits.subscriptionActive
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (credits.subscriptionUnavailable)
              const Text('Subscription usage is temporarily unavailable.')
            else if (usage.isEmpty)
              Text(
                credits.subscriptionActive
                    ? 'NanoGPT did not return allowance details for this plan.'
                    : 'No active subscription allowance was found.',
              )
            else
              ...usage,
            if (credits.currentPeriodEnd != null) ...[
              const SizedBox(height: 8),
              Text(
                'Current period ends ${_date(credits.currentPeriodEnd!)}',
                style: theme.textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 16),
            Text(
              'Values come directly from NanoGPT and refresh each time you '
              'open this sheet.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _compact(double value) {
    if (value == value.roundToDouble()) return _whole(value);
    return value.toStringAsFixed(3).replaceFirst(RegExp(r'0+$'), '');
  }

  static String _whole(double value) {
    final raw = value.round().toString();
    return raw.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
  }

  static String _date(DateTime value) {
    final local = value.toLocal();
    return '${local.month}/${local.day}/${local.year} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }
}

class _UsageCard extends StatelessWidget {
  const _UsageCard({required this.title, required this.usage});

  final String title;
  final NanoGptUsageWindow usage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: usage.percentUsed),
            const SizedBox(height: 8),
            Text(
              '${_CreditsSheet._whole(usage.used)} used · '
              '${_CreditsSheet._whole(usage.remaining)} remaining',
            ),
            Text(
              '${_CreditsSheet._whole(usage.limit)} total · '
              '${(usage.percentUsed * 100).toStringAsFixed(1)}% used',
              style: theme.textTheme.bodySmall,
            ),
            if (usage.resetAt != null)
              Text(
                'Resets ${_CreditsSheet._date(usage.resetAt!)}',
                style: theme.textTheme.bodySmall,
              ),
          ],
        ),
      ),
    );
  }
}
