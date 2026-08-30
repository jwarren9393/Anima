import 'package:flutter/material.dart';

import '../services/nanogpt_service.dart';
import 'minimal_chip_button.dart';

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
      );
    },
  );
}

class _TextModelPickerSheet extends StatefulWidget {
  const _TextModelPickerSheet({
    required this.models,
    required this.selectedId,
    required this.nanoGptService,
  });

  final List<NanoGptModelInfo> models;
  final String? selectedId;
  final NanoGptService nanoGptService;

  @override
  State<_TextModelPickerSheet> createState() => _TextModelPickerSheetState();
}

class _TextModelPickerSheetState extends State<_TextModelPickerSheet> {
  late final TextEditingController _searchController;
  bool _loadingStats = false;
  NanoGptModelBrowseFilters _browseFilters = const NanoGptModelBrowseFilters();
  String _sortId = NanoGptModelBrowseFilters.sortDefault;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
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

  NanoGptModelRuntimeStats _runtimeFor(String modelId) {
    return widget.nanoGptService.cachedRuntimeStats(modelId);
  }

  void _toggleLowLatency() {
    setState(() {
      if (_browseFilters.maxTtftMs != null) {
        _browseFilters = _browseFilters.copyWith(clearMaxTtft: true);
      } else {
        _browseFilters = _browseFilters.copyWith(
          maxTtftMs: NanoGptModelBrowseFilters.lowLatencyTtftMs,
        );
        if (_sortId == NanoGptModelBrowseFilters.sortDefault) {
          _sortId = NanoGptModelBrowseFilters.sortLatency;
        }
      }
    });
  }

  void _toggleFastTps() {
    setState(() {
      if (_browseFilters.minTps != null) {
        _browseFilters = _browseFilters.copyWith(clearMinTps: true);
      } else {
        _browseFilters = _browseFilters.copyWith(
          minTps: NanoGptModelBrowseFilters.fastTpsThreshold,
        );
        if (_sortId == NanoGptModelBrowseFilters.sortDefault) {
          _sortId = NanoGptModelBrowseFilters.sortSpeed;
        }
      }
    });
  }

  void _toggle128kContext() {
    setState(() {
      if (_browseFilters.minContextTokens != null) {
        _browseFilters = _browseFilters.copyWith(clearMinContext: true);
      } else {
        _browseFilters = _browseFilters.copyWith(
          minContextTokens: NanoGptModelBrowseFilters.context128kTokens,
        );
      }
    });
  }

  void _toggleIncludedOnly() {
    setState(() {
      _browseFilters = _browseFilters.copyWith(
        includedOnly: !_browseFilters.includedOnly,
      );
    });
  }

  List<NanoGptModelInfo> _filteredModels(String query) {
    final lower = query.trim().toLowerCase();
    var list = NanoGptModelBrowseFilters.applyAndSort(
      models: widget.models,
      filters: _browseFilters,
      sortId: _sortId,
      runtimeFor: _runtimeFor,
    );
    if (lower.isEmpty) return list;
    return [
      for (final model in list)
        if (model.displayName.toLowerCase().contains(lower) ||
            model.id.toLowerCase().contains(lower) ||
            model.description.toLowerCase().contains(lower) ||
            (model.category?.toLowerCase().contains(lower) ?? false))
          model,
    ];
  }

  String _sortLabel(String sortId) {
    switch (sortId) {
      case NanoGptModelBrowseFilters.sortLatency:
        return 'Lowest latency';
      case NanoGptModelBrowseFilters.sortSpeed:
        return 'Fastest (TPS)';
      case NanoGptModelBrowseFilters.sortContext:
        return 'Largest context';
      case NanoGptModelBrowseFilters.sortName:
        return 'Name A–Z';
      default:
        return 'Default order';
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text;
    final visible = _filteredModels(query);
    final height = MediaQuery.sizeOf(context).height * 0.88;
    final needsStats = _browseFilters.maxTtftMs != null ||
        _browseFilters.minTps != null ||
        _sortId == NanoGptModelBrowseFilters.sortLatency ||
        _sortId == NanoGptModelBrowseFilters.sortSpeed;

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
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: MinimalChipRow(
                children: [
                  MinimalChipButton(
                    label: 'Low latency',
                    icon: Icons.bolt_outlined,
                    selected: _browseFilters.maxTtftMs != null,
                    onPressed: _toggleLowLatency,
                  ),
                  MinimalChipButton(
                    label: 'Fast',
                    icon: Icons.speed_outlined,
                    selected: _browseFilters.minTps != null,
                    onPressed: _toggleFastTps,
                  ),
                  MinimalChipButton(
                    label: '128K+ ctx',
                    icon: Icons.memory_outlined,
                    selected: _browseFilters.minContextTokens != null,
                    onPressed: _toggle128kContext,
                  ),
                  MinimalChipButton(
                    label: 'Included',
                    icon: Icons.card_membership_outlined,
                    selected: _browseFilters.includedOnly,
                    onPressed: _toggleIncludedOnly,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${visible.length} of ${widget.models.length} models'
                      '${needsStats && _loadingStats ? ' · loading latency…' : ''}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _sortId,
                      isDense: true,
                      items: [
                        for (final id in [
                          NanoGptModelBrowseFilters.sortDefault,
                          NanoGptModelBrowseFilters.sortLatency,
                          NanoGptModelBrowseFilters.sortSpeed,
                          NanoGptModelBrowseFilters.sortContext,
                          NanoGptModelBrowseFilters.sortName,
                        ])
                          DropdownMenuItem(
                            value: id,
                            child: Text(_sortLabel(id)),
                          ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() => _sortId = value);
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: visible.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _loadingStats && needsStats
                              ? 'Loading speed stats for filters…'
                              : 'No models match these filters.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: visible.length,
                      itemBuilder: (context, index) {
                        final model = visible[index];
                        final selected = model.id == widget.selectedId;
                        final runtime = _runtimeFor(model.id);
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
                                  style:
                                      Theme.of(context).textTheme.labelMedium,
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
                          trailing: selected
                              ? Icon(
                                  Icons.check_circle,
                                  color: Theme.of(context).colorScheme.primary,
                                )
                              : null,
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
