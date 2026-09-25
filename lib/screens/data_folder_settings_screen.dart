import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/app_data_root.dart';
import '../utils/platform_utils.dart';
import 'settings_ui.dart';

/// View or move the user-owned Anima library folder.
class DataFolderSettingsScreen extends StatefulWidget {
  const DataFolderSettingsScreen({
    super.key,
    required this.dataRoot,
  });

  final AppDataRoot dataRoot;

  @override
  State<DataFolderSettingsScreen> createState() =>
      _DataFolderSettingsScreenState();
}

class _DataFolderSettingsScreenState extends State<DataFolderSettingsScreen> {
  bool _busy = false;

  String get _path => widget.dataRoot.path ?? 'Not set';

  Future<void> _copyPath() async {
    await Clipboard.setData(ClipboardData(text: _path));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Folder path copied')),
    );
  }

  Future<void> _openFolder() async {
    final path = widget.dataRoot.path;
    if (path == null) return;
    try {
      if (Platform.isLinux) {
        await Process.start('xdg-open', [path]);
      } else if (Platform.isWindows) {
        await Process.start('explorer', [path]);
      } else {
        await _copyPath();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Open My Files and go to Documents → Anima (path copied).',
            ),
          ),
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open folder: $error')),
      );
    }
  }

  Future<void> _usePath(String path) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (!isDesktopPlatform && Platform.isAndroid) {
        final allowed = await widget.dataRoot.ensureStorageAccess();
        if (!allowed) {
          throw AppDataRootException(
            'Allow All files access for Anima, then try again.',
          );
        }
      }
      await widget.dataRoot.changePath(path);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Anima folder is now:\n$path')),
      );
      setState(() {});
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$error')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _chooseFolder() async {
    final picked = await widget.dataRoot.pickFolder();
    if (picked == null || picked.trim().isEmpty) return;
    await _usePath(picked);
  }

  Future<void> _useDefault() async {
    final path = await widget.dataRoot.defaultPublicPath();
    await _usePath(path);
  }

  Future<void> _usePortable() async {
    final path = widget.dataRoot.portablePath();
    if (path == null) return;
    await _usePath(path);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Data folder')),
      body: ListView(
        padding: SettingsUi.listPadding,
        children: [
          SettingsUi.sectionTitle(context, 'Library location'),
          const SizedBox(height: 8),
          SettingsUi.sectionHint(
            context,
            'Everything Anima stores — characters, chats, avatars, lore, '
            'settings, and your API key — lives in this folder. Copy the '
            'folder to back up or move Anima.',
          ),
          const SizedBox(height: 16),
          SelectableText(
            _path,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontFamily: 'monospace',
                ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonal(
                onPressed: _busy ? null : _copyPath,
                child: const Text('Copy path'),
              ),
              FilledButton.tonal(
                onPressed: _busy ? null : _openFolder,
                child: Text(isDesktopPlatform ? 'Open folder' : 'Copy + hint'),
              ),
            ],
          ),
          const SizedBox(height: 28),
          SettingsUi.sectionTitle(context, 'Move library'),
          const SizedBox(height: 8),
          SettingsUi.sectionHint(
            context,
            'Anima copies your files into the new folder, then uses that '
            'location. The old folder is left in place so nothing is deleted.',
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _chooseFolder,
            child: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Choose a different folder'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _busy ? null : _useDefault,
            child: const Text('Use Documents / Anima'),
          ),
          FutureBuilder<bool>(
            future: widget.dataRoot.canUsePortableFolder,
            builder: (context, snapshot) {
              if (snapshot.data != true) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 8),
                child: OutlinedButton(
                  onPressed: _busy ? null : _usePortable,
                  child: const Text('Keep data next to the app'),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
