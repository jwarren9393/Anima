import 'package:flutter/material.dart';

import '../screens/api_settings_screen.dart';
import '../screens/settings_ui.dart';
import '../services/api_key_service.dart';
import '../services/nanogpt_service.dart';
import '../services/settings_service.dart';
import 'text_model_catalog_widgets.dart';

/// Compact model picker from chat menus — same filters as API settings.
Future<bool?> showQuickApiConnectionSheet({
  required BuildContext context,
  required ApiKeyService apiKeyService,
  required SettingsService settingsService,
  required NanoGptService nanoGptService,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) {
      return _QuickApiConnectionSheet(
        apiKeyService: apiKeyService,
        settingsService: settingsService,
        nanoGptService: nanoGptService,
      );
    },
  );
}

class _QuickApiConnectionSheet extends StatefulWidget {
  const _QuickApiConnectionSheet({
    required this.apiKeyService,
    required this.settingsService,
    required this.nanoGptService,
  });

  final ApiKeyService apiKeyService;
  final SettingsService settingsService;
  final NanoGptService nanoGptService;

  @override
  State<_QuickApiConnectionSheet> createState() =>
      _QuickApiConnectionSheetState();
}

class _QuickApiConnectionSheetState extends State<_QuickApiConnectionSheet> {
  final _modelController = TextEditingController();
  bool _loading = true;
  bool _loadingModels = false;
  bool _saving = false;
  String? _modelsError;
  List<NanoGptModelInfo> _models = const [];
  String _selectedCategoryFilter = NanoGptTextModelCatalogFilter.allId;
  String? _selectedProvider;
  bool _loadingSelectedRuntime = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _modelController.dispose();
    super.dispose();
  }

  Future<String> _baseUrlForCatalog() async {
    final subscription = await widget.settingsService.getUseSubscriptionApi();
    return subscription
        ? SettingsService.subscriptionBaseUrl
        : SettingsService.defaultBaseUrl;
  }

  Future<void> _load() async {
    final model = await widget.settingsService.getModel();
    final category = await widget.settingsService.getModelCatalogCategoryFilter();
    final provider = await widget.settingsService.getModelCatalogProvider();
    if (!mounted) return;
    setState(() {
      _modelController.text = model;
      _selectedCategoryFilter = category;
      _selectedProvider = provider;
      _loading = false;
    });
    await _loadModels();
  }

  Future<void> _loadModels() async {
    setState(() {
      _loadingModels = true;
      _modelsError = null;
    });
    try {
      final baseUrl = await _baseUrlForCatalog();
      final models = await widget.nanoGptService.listModels(baseUrl: baseUrl);
      if (!mounted) return;
      setState(() {
        _models = models;
        _loadingModels = false;
        if (!NanoGptTextModelCatalogFilter.categoryFilterIds(models)
            .contains(_selectedCategoryFilter)) {
          _selectedCategoryFilter = NanoGptTextModelCatalogFilter.allId;
        }
        _restoreProviderFilter();
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

  List<NanoGptModelInfo> get _modelsForCategory {
    return NanoGptTextModelCatalogFilter.apply(
      _models,
      _selectedCategoryFilter,
    );
  }

  List<String> get _providers {
    final seen = <String>{};
    final list = <String>[];
    for (final model in _modelsForCategory) {
      if (seen.add(model.ownedBy)) list.add(model.ownedBy);
    }
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
    return _modelsForCategory.where((m) => m.ownedBy == provider).toList();
  }

  void _restoreProviderFilter() {
    final providers = _providers;
    if (providers.isEmpty) {
      _selectedProvider = null;
      return;
    }
    if (_selectedProvider != null && providers.contains(_selectedProvider)) {
      return;
    }
    _selectedProvider = providers.first;
    widget.settingsService.saveModelCatalogProvider(_selectedProvider);
  }

  void _onCategoryFilterChanged(String? filterId) {
    if (filterId == null) return;
    setState(() {
      _selectedCategoryFilter = filterId;
      _restoreProviderFilter();
    });
    widget.settingsService.saveModelCatalogCategoryFilter(filterId);
  }

  void _onProviderChanged(String? provider) {
    if (provider == null) return;
    setState(() {
      _selectedProvider = provider;
      final forProvider = _modelsForProvider;
      if (forProvider.isEmpty) return;
      final current = _modelController.text.trim();
      final stillValid = forProvider.any((m) => m.id == current);
      if (!stillValid) {
        _modelController.text = forProvider.first.id;
      }
    });
    widget.settingsService.saveModelCatalogProvider(provider);
    _refreshSelectedRuntimeStats();
  }

  NanoGptModelInfo? get _selectedModelInfo {
    final id = _modelController.text.trim();
    if (id.isEmpty) return null;
    for (final model in _models) {
      if (model.id == id) return model;
    }
    return null;
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
    );
    if (picked == null || !mounted) return;
    setState(() => _modelController.text = picked);
    await _refreshSelectedRuntimeStats();
  }

  Future<void> _applyModel() async {
    final model = _modelController.text.trim();
    if (model.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick or enter a model id first.')),
      );
      return;
    }
    setState(() => _saving = true);
    await widget.settingsService.saveModel(model);
    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.pop(context, true);
  }

  void _openFullApiSettings() {
    Navigator.pop(context);
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ApiSettingsScreen(
          apiKeyService: widget.apiKeyService,
          settingsService: widget.settingsService,
          nanoGptService: widget.nanoGptService,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * 0.82;
    final providers = _providers;
    final modelsForProvider = _modelsForProvider;
    final categoryFilters =
        NanoGptTextModelCatalogFilter.categoryFilterIds(_models);

    return SafeArea(
      child: SizedBox(
        height: height,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: SettingsUi.listPadding,
                children: [
                  Text(
                    'API & model',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Switch chat model without leaving this screen. Category and '
                    'provider filters stay saved.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 16),
                  if (_loadingModels)
                    const LinearProgressIndicator(minHeight: 2),
                  if (_modelsError != null) ...[
                    Text(
                      _modelsError!,
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: _loadModels,
                      child: const Text('Retry'),
                    ),
                  ],
                  if (!_loadingModels && _models.isNotEmpty) ...[
                    DropdownButtonFormField<String>(
                      key: ValueKey('quick-category-$_selectedCategoryFilter'),
                      initialValue: categoryFilters.contains(
                        _selectedCategoryFilter,
                      )
                          ? _selectedCategoryFilter
                          : NanoGptTextModelCatalogFilter.allId,
                      isExpanded: true,
                      decoration: SettingsUi.fieldDecoration(label: 'Category'),
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
                      key: ValueKey('quick-provider-$_selectedProvider'),
                      initialValue: _selectedProvider != null &&
                              providers.contains(_selectedProvider)
                          ? _selectedProvider
                          : null,
                      isExpanded: true,
                      decoration: SettingsUi.fieldDecoration(label: 'Provider'),
                      items: [
                        for (final provider in providers)
                          DropdownMenuItem(
                            value: provider,
                            child: Text(provider),
                          ),
                      ],
                      onChanged: _onProviderChanged,
                    ),
                    const SizedBox(height: 12),
                    if (_selectedModelInfo != null)
                      TextModelSummaryCard(
                        model: _selectedModelInfo!,
                        runtimeStats: widget.nanoGptService.cachedRuntimeStats(
                          _selectedModelInfo!.id,
                        ),
                        loadingRuntime: _loadingSelectedRuntime,
                        onBrowse: modelsForProvider.isEmpty
                            ? null
                            : _openModelPicker,
                      )
                    else if (_modelController.text.trim().isNotEmpty)
                      Card(
                        margin: EdgeInsets.zero,
                        child: ListTile(
                          title: Text(_modelController.text.trim()),
                          subtitle: const Text('Custom model id'),
                        ),
                      ),
                    const SizedBox(height: 8),
                    if (modelsForProvider.isNotEmpty)
                      OutlinedButton.icon(
                        onPressed: _openModelPicker,
                        icon: const Icon(Icons.view_list_outlined),
                        label: Text(
                          'Browse ${modelsForProvider.length} models',
                        ),
                      ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _modelController,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: SettingsUi.fieldDecoration(
                        label: 'Model id',
                        helperText: 'Applied to this chat when you tap Use model',
                      ),
                      onChanged: (_) => _refreshSelectedRuntimeStats(),
                    ),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _saving ? null : _applyModel,
                    child: _saving
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Use model'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _openFullApiSettings,
                    child: const Text('Full API settings (key, subscription…)'),
                  ),
                ],
              ),
      ),
    );
  }
}
