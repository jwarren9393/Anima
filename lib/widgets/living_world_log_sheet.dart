import 'package:flutter/material.dart';

import '../models/turn_resolution.dart';
import '../services/living_world_log_service.dart';
import '../services/living_world_service.dart';
import '../services/living_world_undo_service.dart';

/// Owner-visible timeline of what the Living World engine applied.
Future<void> showLivingWorldLogSheet({
  required BuildContext context,
  required String worldId,
  required String worldTitle,
  LivingWorldLogService? logService,
  LivingWorldUndoService? undoService,
  LivingWorldService? worldService,
  bool showRevert = false,
  VoidCallback? onReverted,
}) {
  final logs = logService ?? LivingWorldLogService();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _LivingWorldLogSheet(
      worldId: worldId,
      worldTitle: worldTitle,
      logService: logs,
      undoService: undoService,
      worldService: worldService,
      showRevert: showRevert,
      onReverted: onReverted,
    ),
  );
}

class _LivingWorldLogSheet extends StatefulWidget {
  const _LivingWorldLogSheet({
    required this.worldId,
    required this.worldTitle,
    required this.logService,
    this.undoService,
    this.worldService,
    this.showRevert = false,
    this.onReverted,
  });

  final String worldId;
  final String worldTitle;
  final LivingWorldLogService logService;
  final LivingWorldUndoService? undoService;
  final LivingWorldService? worldService;
  final bool showRevert;
  final VoidCallback? onReverted;

  @override
  State<_LivingWorldLogSheet> createState() => _LivingWorldLogSheetState();
}

class _LivingWorldLogSheetState extends State<_LivingWorldLogSheet> {
  List<TurnResolution>? _entries;
  String? _error;
  bool _loading = true;
  bool _canUndo = false;
  bool _undoBusy = false;

  bool get _revertEnabled =>
      widget.showRevert &&
      widget.undoService != null &&
      widget.worldService != null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final entries = await widget.logService.listEntries(widget.worldId);
      var canUndo = false;
      if (_revertEnabled) {
        canUndo = await widget.undoService!.canUndo(widget.worldId);
      }
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _canUndo = canUndo;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  Future<void> _clear() async {
    await widget.logService.clear(widget.worldId);
    await _load();
  }

  Future<void> _undoLast() async {
    if (!_revertEnabled || _undoBusy) return;
    setState(() => _undoBusy = true);
    try {
      final restored = await widget.undoService!.undoLast(
        worldService: widget.worldService!,
        worldId: widget.worldId,
      );
      if (!mounted) return;
      setState(() => _undoBusy = false);
      widget.onReverted?.call();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            restored == null
                ? 'Nothing to undo for this notebook.'
                : 'Reverted last applied pack.',
          ),
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _undoBusy = false;
        _error = 'Undo failed: $e';
      });
    }
  }

  String _formatWhen(DateTime at) {
    final local = at.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final entries = _entries ?? const <TurnResolution>[];
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.65,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'World timeline — ${widget.worldTitle}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  if (_revertEnabled && _canUndo)
                    TextButton(
                      onPressed: _undoBusy ? null : _undoLast,
                      child: const Text('Undo last'),
                    ),
                  if (entries.isNotEmpty)
                    TextButton(
                      onPressed: _clear,
                      child: const Text('Clear'),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'Shared across every chat bound to this notebook. What the '
                'engine applied on recent turns (resolve-before, after-turn, '
                'near-scene ticks). Newest first.'
                '${_revertEnabled ? ' Undo last restores the notebook before '
                    'the most recent applied pack (same as chat ⋮).' : ''}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ),
            if (_loading)
              const Expanded(
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error!, textAlign: TextAlign.center),
                  ),
                ),
              )
            else if (entries.isEmpty)
              const Expanded(
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'No world updates logged yet for this notebook.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                  itemCount: entries.length,
                  separatorBuilder: (context, index) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    return ListTile(
                      dense: true,
                      title: Text(entry.kindLabel),
                      subtitle: Text(
                        [
                          _formatWhen(entry.at),
                          ...entry.logLines,
                        ].join('\n'),
                      ),
                      isThreeLine: true,
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
