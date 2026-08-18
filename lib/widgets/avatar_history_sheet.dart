import 'dart:io';

import 'package:flutter/material.dart';

import '../models/avatar_history_entry.dart';
import '../services/avatar_export_service.dart';
import '../services/avatar_service.dart';

/// Pick a previous portrait for this character/persona, or export/delete one.
Future<String?> showAvatarHistorySheet({
  required BuildContext context,
  required AvatarService avatarService,
  required AvatarExportService exportService,
  required String stem,
  String? currentFileName,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => AvatarHistorySheet(
      avatarService: avatarService,
      exportService: exportService,
      stem: stem,
      currentFileName: currentFileName,
    ),
  );
}

class AvatarHistorySheet extends StatefulWidget {
  const AvatarHistorySheet({
    super.key,
    required this.avatarService,
    required this.exportService,
    required this.stem,
    this.currentFileName,
  });

  final AvatarService avatarService;
  final AvatarExportService exportService;
  final String stem;
  final String? currentFileName;

  @override
  State<AvatarHistorySheet> createState() => _AvatarHistorySheetState();
}

class _AvatarHistorySheetState extends State<AvatarHistorySheet> {
  bool _loading = true;
  List<_HistoryRow> _rows = const [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final entries = await widget.avatarService.listHistoryForStem(widget.stem);
      final rows = <_HistoryRow>[];
      for (final entry in entries) {
        final path = await widget.avatarService.resolvePath(entry.fileName);
        if (path == null) continue;
        rows.add(_HistoryRow(entry: entry, path: path));
      }
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
        _loading = false;
      });
    }
  }

  Future<void> _export(_HistoryRow row) async {
    try {
      final bytes = await widget.avatarService.readBytes(row.entry.fileName);
      if (bytes == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('That portrait file is missing.')),
        );
        return;
      }
      final message = await widget.exportService.exportAvatar(
        bytes: bytes,
        suggestedName: row.entry.fileName,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: $error')),
      );
    }
  }

  Future<void> _delete(_HistoryRow row) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete portrait?'),
        content: const Text(
          'This removes the file from Anima. It cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await widget.avatarService.delete(row.entry.fileName);
    if (!mounted) return;
    if (row.entry.fileName == widget.currentFileName) {
      Navigator.pop(context, '');
      return;
    }
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 8, 16, bottomInset + 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Avatar history', style: theme.textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(
              'Past generations stay here. Tap to use one again. Long-press to '
              'export or delete.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Text(_error!, style: TextStyle(color: theme.colorScheme.error))
            else if (_rows.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'No saved portraits yet. Generate or pick a photo to start history.',
                  style: theme.textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
              )
            else
              SizedBox(
                height: 280,
                child: GridView.builder(
                  shrinkWrap: true,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: _rows.length,
                  itemBuilder: (context, index) {
                    final row = _rows[index];
                    final selected = row.entry.fileName == widget.currentFileName;
                    return Material(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => Navigator.pop(context, row.entry.fileName),
                        onLongPress: () => _showRowMenu(row),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.file(File(row.path), fit: BoxFit.cover),
                            if (selected)
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: theme.colorScheme.primary,
                                    width: 3,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showRowMenu(_HistoryRow row) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.check_circle_outline),
              title: const Text('Use as avatar'),
              onTap: () => Navigator.pop(context, 'use'),
            ),
            ListTile(
              leading: const Icon(Icons.download_outlined),
              title: const Text('Export copy'),
              subtitle: const Text('Gallery on phone · Downloads on PC'),
              onTap: () => Navigator.pop(context, 'export'),
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
              title: Text(
                'Delete file',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'use':
        Navigator.pop(context, row.entry.fileName);
      case 'export':
        await _export(row);
      case 'delete':
        await _delete(row);
    }
  }
}

class _HistoryRow {
  const _HistoryRow({required this.entry, required this.path});

  final AvatarHistoryEntry entry;
  final String path;
}
