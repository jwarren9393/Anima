import 'package:flutter/material.dart';

import '../models/turn_resolution.dart';
import '../services/living_world_log_service.dart';

/// Simple owner-visible list of what the Living World engine applied.
Future<void> showLivingWorldLogSheet({
  required BuildContext context,
  required String worldId,
  required String worldTitle,
  LivingWorldLogService? logService,
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
    ),
  );
}

class _LivingWorldLogSheet extends StatefulWidget {
  const _LivingWorldLogSheet({
    required this.worldId,
    required this.worldTitle,
    required this.logService,
  });

  final String worldId;
  final String worldTitle;
  final LivingWorldLogService logService;

  @override
  State<_LivingWorldLogSheet> createState() => _LivingWorldLogSheetState();
}

class _LivingWorldLogSheetState extends State<_LivingWorldLogSheet> {
  List<TurnResolution>? _entries;
  String? _error;
  bool _loading = true;

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
      if (!mounted) return;
      setState(() {
        _entries = entries;
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
                      'World log — ${widget.worldTitle}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
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
                'What the engine applied on recent turns (resolve-before and '
                'after-turn packs). Newest first.',
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
