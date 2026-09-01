import 'package:flutter/material.dart';

import '../services/nanogpt_service.dart';

/// Snapshot card for the currently selected chat model.
class TextModelSummaryCard extends StatelessWidget {
  const TextModelSummaryCard({
    super.key,
    required this.model,
    this.runtimeStats = const NanoGptModelRuntimeStats(),
    this.loadingRuntime = false,
    this.onBrowse,
  });

  final NanoGptModelInfo model;
  final NanoGptModelRuntimeStats runtimeStats;
  final bool loadingRuntime;
  final VoidCallback? onBrowse;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final description = model.description.trim();
    final statLine = model.statChipLine(runtime: runtimeStats);
    final pricing = model.pricingLine;
    final caps = model.capabilities.shortLabels;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        model.displayName,
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        model.id,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (onBrowse != null)
                  TextButton(
                    onPressed: onBrowse,
                    child: const Text('Browse'),
                  ),
              ],
            ),
            if (statLine.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final label in statLine.split(' · '))
                    _StatChip(label: label),
                  if (loadingRuntime)
                    _StatChip(
                      label: 'Loading stats…',
                      muted: true,
                    ),
                ],
              ),
            ],
            if (caps.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final cap in caps) _StatChip(label: cap, outline: true),
                ],
              ),
            ],
            if (description.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                description,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium,
              ),
            ],
            if (pricing != null) ...[
              const SizedBox(height: 8),
              Text(
                pricing,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.label,
    this.muted = false,
    this.outline = false,
  });

  final String label;
  final bool muted;
  final bool outline;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = muted
        ? theme.colorScheme.surfaceContainerHighest
        : outline
            ? theme.colorScheme.surface
            : theme.colorScheme.primaryContainer.withValues(alpha: 0.55);
    final fg = muted
        ? theme.colorScheme.onSurfaceVariant
        : outline
            ? theme.colorScheme.onSurfaceVariant
            : theme.colorScheme.onPrimaryContainer;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: outline
            ? Border.all(color: theme.colorScheme.outlineVariant)
            : null,
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: fg,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Full-screen-ish sheet to browse models with stats at a glance.
Future<String?> showTextModelPickerSheet({
  required BuildContext context,
  required List<NanoGptModelInfo> models,
  required String? selectedId,
  required NanoGptService nanoGptService,
  String initialContextFilter = NanoGptTextModelPerformanceFilter.contextAllId,
  Set<String> favoriteIds = const {},
  Future<void> Function(NanoGptModelInfo model)? onToggleFavorite,
}) {
  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) {
      return _TextModelPickerSheet(
        models: models,
        selectedId: selectedId,
        nanoGptService: nanoGptService,
        initialContextFilter: initialContextFilter,
        favoriteIds: favoriteIds,
        onToggleFavorite: onToggleFavorite,
      );
    },
  );
}

class _TextModelPickerSheet extends StatefulWidget {
  const _TextModelPickerSheet({
    required this.models,
    required this.selectedId,
    required this.nanoGptService,
    required this.initialContextFilter,
    this.favoriteIds = const {},
    this.onToggleFavorite,
  });

  final List<NanoGptModelInfo> models;
  final String? selectedId;
  final NanoGptService nanoGptService;
  final String initialContextFilter;
  final Set<String> favoriteIds;
  final Future<void> Function(NanoGptModelInfo model)? onToggleFavorite;

  @override
  State<_TextModelPickerSheet> createState() => _TextModelPickerSheetState();
}

class _TextModelPickerSheetState extends State<_TextModelPickerSheet> {
  late final TextEditingController _searchController;
  late String _contextFilter;
  String _minTpsFilter = NanoGptTextModelPerformanceFilter.tpsAllId;
  String _maxTtftFilter = NanoGptTextModelPerformanceFilter.ttftAllId;
  TextModelSortMode _sortMode = TextModelSortMode.catalog;
  bool _loadingStats = false;
  late final Set<String> _favoriteIds = Set.of(widget.favoriteIds);
  bool _favoritesOnly = false;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _contextFilter = widget.initialContextFilter;
    _prefetchStats();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _prefetchStats() async {
    setState(() => _loadingStats = true);
    await widget.nanoGptService.prefetchModelRuntimeStats(
      widget.models.map((m) => m.id).toList(),
    );
    if (mounted) setState(() => _loadingStats = false);
  }

  List<NanoGptModelInfo> _filteredModels(String query) {
    var filtered = NanoGptTextModelPerformanceFilter.applyAll(
      models: widget.models,
      contextFilterId: _contextFilter,
      minTpsFilterId: _minTpsFilter,
      maxTtftFilterId: _maxTtftFilter,
      sortMode: _sortMode,
      statsSource: widget.nanoGptService,
    );
    if (_favoritesOnly) {
      filtered = [
        for (final model in filtered)
          if (_favoriteIds.contains(model.id)) model,
      ];
    }
    final lower = query.trim().toLowerCase();
    if (lower.isEmpty) return filtered;
    return [
      for (final model in filtered)
        if (model.displayName.toLowerCase().contains(lower) ||
            model.id.toLowerCase().contains(lower) ||
            model.description.toLowerCase().contains(lower) ||
            (model.category?.toLowerCase().contains(lower) ?? false))
          model,
    ];
  }

  Widget _filterDropdown({
    required String label,
    required String value,
    required List<String> options,
    required String Function(String) labelFor,
    required ValueChanged<String?> onChanged,
  }) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: options.contains(value) ? value : options.first,
          isExpanded: true,
          isDense: true,
          items: [
            for (final option in options)
              DropdownMenuItem(
                value: option,
                child: Text(labelFor(option), overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text;
    final visible = _filteredModels(query);
    final height = MediaQuery.sizeOf(context).height * 0.88;

    return SafeArea(
      child: SizedBox(
        height: height,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Browse models',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  if (_loadingStats)
                    Text(
                      'Loading stats…',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _searchController,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search name, id, category, description…',
                  isDense: true,
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _filterDropdown(
                          label: 'Context',
                          value: _contextFilter,
                          options: NanoGptTextModelPerformanceFilter.contextFilterIds,
                          labelFor: NanoGptTextModelPerformanceFilter.labelForContext,
                          onChanged: (value) {
                            if (value == null) return;
                            setState(() => _contextFilter = value);
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _filterDropdown(
                          label: 'Min speed',
                          value: _minTpsFilter,
                          options: NanoGptTextModelPerformanceFilter.tpsFilterIds,
                          labelFor: NanoGptTextModelPerformanceFilter.labelForTps,
                          onChanged: (value) {
                            if (value == null) return;
                            setState(() => _minTpsFilter = value);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _filterDropdown(
                          label: 'List',
                          value: _favoritesOnly ? 'favorites' : 'all',
                          options: const ['all', 'favorites'],
                          labelFor: (value) => value == 'favorites'
                              ? 'Starred only'
                              : 'All models',
                          onChanged: (value) {
                            if (value == null) return;
                            setState(
                              () => _favoritesOnly = value == 'favorites',
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _filterDropdown(
                          label: 'Max TTFT',
                          value: _maxTtftFilter,
                          options: NanoGptTextModelPerformanceFilter.ttftFilterIds,
                          labelFor: NanoGptTextModelPerformanceFilter.labelForTtft,
                          onChanged: (value) {
                            if (value == null) return;
                            setState(() => _maxTtftFilter = value);
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _filterDropdown(
                          label: 'Sort',
                          value: _sortMode.name,
                          options: TextModelSortMode.values
                              .map((mode) => mode.name)
                              .toList(),
                          labelFor: (name) =>
                              NanoGptTextModelPerformanceFilter.labelForSort(
                            TextModelSortMode.values.byName(name),
                          ),
                          onChanged: (value) {
                            if (value == null) return;
                            setState(
                              () => _sortMode = TextModelSortMode.values.byName(
                                value,
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${visible.length} of ${widget.models.length} models',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
            Expanded(
              child: visible.isEmpty
                  ? Center(
                      child: Text(
                        'No models match these filters.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    )
                  : ListView.builder(
                      itemCount: visible.length,
                      itemBuilder: (context, index) {
                        final model = visible[index];
                        final selected = model.id == widget.selectedId;
                        final runtime = widget.nanoGptService.cachedRuntimeStats(
                          model.id,
                        );
                        final statLine = model.statChipLine(runtime: runtime);
                        final description = model.description.trim();

                        return ListTile(
                          selected: selected,
                          title: Text(model.displayName),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (statLine.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  statLine,
                                  style: Theme.of(context).textTheme.labelMedium,
                                ),
                              ],
                              if (description.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  description,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                              const SizedBox(height: 4),
                              Text(
                                model.id,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                          isThreeLine: true,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (widget.onToggleFavorite != null)
                                IconButton(
                                  tooltip: _favoriteIds.contains(model.id)
                                      ? 'Remove favorite'
                                      : 'Save as favorite',
                                  icon: Icon(
                                    _favoriteIds.contains(model.id)
                                        ? Icons.star
                                        : Icons.star_border,
                                    color: _favoriteIds.contains(model.id)
                                        ? Theme.of(
                                            context,
                                          ).colorScheme.tertiary
                                        : null,
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      if (!_favoriteIds.remove(model.id)) {
                                        _favoriteIds.add(model.id);
                                      }
                                    });
                                    widget.onToggleFavorite!(model);
                                  },
                                ),
                              if (selected)
                                Icon(
                                  Icons.check_circle,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                            ],
                          ),
                          onTap: () => Navigator.pop(context, model.id),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
