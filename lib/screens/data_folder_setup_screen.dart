import 'dart:io';

import 'package:flutter/material.dart';

import '../services/app_data_root.dart';
import '../utils/platform_utils.dart';

/// First-launch chooser for the visible Anima library folder.
class DataFolderSetupScreen extends StatefulWidget {
  const DataFolderSetupScreen({
    super.key,
    required this.dataRoot,
    required this.onReady,
  });

  final AppDataRoot dataRoot;
  final VoidCallback onReady;

  @override
  State<DataFolderSetupScreen> createState() => _DataFolderSetupScreenState();
}

class _DataFolderSetupScreenState extends State<DataFolderSetupScreen>
    with WidgetsBindingObserver {
  String _defaultPath = '';
  String? _portablePath;
  bool _canPortable = false;
  bool _hasAccess = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final defaultPath = await widget.dataRoot.defaultPublicPath();
    final portable = widget.dataRoot.portablePath();
    final canPortable = await widget.dataRoot.canUsePortableFolder;
    var hasAccess = true;
    if (!isDesktopPlatform && Platform.isAndroid) {
      hasAccess = await widget.dataRoot.hasStorageAccess();
    }
    if (!mounted) return;
    setState(() {
      _defaultPath = defaultPath;
      _portablePath = portable;
      _canPortable = canPortable;
      _hasAccess = hasAccess;
    });
  }

  Future<void> _usePath(String path, {required bool migrateLegacy}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (!isDesktopPlatform && Platform.isAndroid) {
        final allowed = await widget.dataRoot.ensureStorageAccess();
        if (!allowed) {
          throw AppDataRootException(
            'Android needs All files access so Anima can use a normal folder '
            'you can open in My Files. Allow it, then return here.',
          );
        }
      }
      await widget.dataRoot.setPath(path, migrateLegacy: migrateLegacy);
      widget.onReady();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _chooseFolder() async {
    final picked = await widget.dataRoot.pickFolder();
    if (picked == null || picked.trim().isEmpty) return;
    await _usePath(picked, migrateLegacy: true);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 12),
            Icon(Icons.folder_open, size: 48, color: scheme.primary),
            const SizedBox(height: 16),
            Text(
              'Your Anima folder',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            Text(
              'Anima keeps characters, chats, avatars, settings, and your API '
              'key in one folder you can open, copy, or move. On Android this '
              'avoids Samsung’s locked app storage.',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 20),
            Text(
              'Suggested location',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 6),
            SelectableText(
              _defaultPath.isEmpty ? '…' : _defaultPath,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontFamily: 'monospace',
                  ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(
                _error!,
                style: TextStyle(color: scheme.error),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy || _defaultPath.isEmpty
                  ? null
                  : () => _usePath(_defaultPath, migrateLegacy: true),
              child: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Use this folder'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _busy ? null : _chooseFolder,
              child: const Text('Choose a different folder'),
            ),
            if (_canPortable && _portablePath != null) ...[
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : () => _usePath(_portablePath!, migrateLegacy: true),
                child: const Text('Keep data next to the app'),
              ),
              const SizedBox(height: 8),
              Text(
                'Best for a portable zip: $_portablePath',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (!_hasAccess && !isDesktopPlatform) ...[
              const SizedBox(height: 16),
              Text(
                'On Android, Anima needs All files access so it can use a '
                'normal folder (Documents/Anima) instead of locked app storage. '
                'You’ll be asked when you tap Use this folder.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 24),
            Text(
              'You can change this later in Settings → Data folder. Existing '
              'Anima files are copied into the folder you pick.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
