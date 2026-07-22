import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../services/app_backup_service.dart';
import '../services/appearance_controller.dart';
import '../services/persona_service.dart';
import '../services/settings_service.dart';

/// Export / restore all Anima data (except the API key) as one file.
class BackupRestoreScreen extends StatefulWidget {
  const BackupRestoreScreen({
    super.key,
    required this.settingsService,
    required this.personaService,
    this.appearanceController,
    this.backupService,
  });

  final SettingsService settingsService;
  final PersonaService personaService;
  final AppearanceController? appearanceController;
  final AppBackupService? backupService;

  @override
  State<BackupRestoreScreen> createState() => _BackupRestoreScreenState();
}

class _BackupRestoreScreenState extends State<BackupRestoreScreen> {
  late final AppBackupService _backup =
      widget.backupService ??
      AppBackupService(
        settingsService: widget.settingsService,
        personaService: widget.personaService,
      );

  bool _busy = false;

  bool get _useDesktopSaveDialog =>
      Platform.isLinux || Platform.isWindows || Platform.isMacOS;

  Future<void> _createBackup() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final bundle = await _backup.createBackup();
      final stamp = DateTime.now()
          .toUtc()
          .toIso8601String()
          .replaceAll(':', '-')
          .split('.')
          .first;
      final fileName =
          'anima_backup_$stamp.${AppBackupService.fileExtension}';

      if (_useDesktopSaveDialog) {
        await _saveBackupOnDesktop(
          bytes: bundle.bytes,
          fileName: fileName,
          summary: bundle.summary.shortDescription,
        );
      } else {
        await _shareBackupOnMobile(
          bytes: bundle.bytes,
          fileName: fileName,
          summary: bundle.summary.shortDescription,
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Backup failed: $error')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveBackupOnDesktop({
    required Uint8List bytes,
    required String fileName,
    required String summary,
  }) async {
    String? initialDirectory;
    try {
      final downloads = await getDownloadsDirectory();
      initialDirectory = downloads?.path;
    } catch (_) {
      // Fall back to the system default save location.
    }

    final pickedPath = await FilePicker.platform.saveFile(
      dialogTitle: 'Save Anima backup',
      fileName: fileName,
      initialDirectory: initialDirectory,
      type: FileType.any,
      bytes: bytes,
    );
    if (pickedPath == null) return;

    final savedPath = _ensureBackupExtension(pickedPath);
    final file = File(savedPath);
    // Desktop pickers usually write [bytes], but always rewrite so a missing
    // extension rename still lands a complete backup file.
    await file.writeAsBytes(bytes, flush: true);
    if (savedPath != pickedPath) {
      final leftover = File(pickedPath);
      if (await leftover.exists()) {
        try {
          await leftover.delete();
        } catch (_) {
          // Ignore cleanup failures; the complete backup file still exists.
        }
      }
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Backup saved · $summary\n$savedPath')),
    );
  }

  Future<void> _shareBackupOnMobile({
    required Uint8List bytes,
    required String fileName,
    required String summary,
  }) async {
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/$fileName';
    final file = File(path);
    await file.writeAsBytes(bytes, flush: true);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Backup ready · $summary')),
    );

    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile(
            path,
            mimeType: 'application/json',
            name: fileName,
          ),
        ],
        subject: 'Anima backup',
      ),
    );
  }

  String _ensureBackupExtension(String path) {
    final extension = '.${AppBackupService.fileExtension}';
    if (path.toLowerCase().endsWith(extension)) return path;
    return '$path$extension';
  }

  Future<void> _restoreBackup() async {
    if (_busy) return;

    final pick = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: true,
      allowMultiple: false,
    );
    if (pick == null || pick.files.isEmpty) return;

    final picked = pick.files.single;
    Uint8List? bytes = picked.bytes;
    if (bytes == null && picked.path != null) {
      bytes = await File(picked.path!).readAsBytes();
    }
    if (bytes == null || bytes.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not read that backup file.')),
      );
      return;
    }

    late final AppBackupSummary summary;
    try {
      final inspected = await _backup.inspectBackup(bytes);
      summary = inspected.summary;
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$error')));
      return;
    }

    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Replace everything?'),
        content: Text(
          'This replaces chats, characters, personas, lorebooks, '
          'Creation Center workshops, drafts, avatars, and settings on this '
          'device with the backup.\n\n'
          '${summary.shortDescription}\n\n'
          'Your NanoGPT API key is not changed.\n\n'
          'This cannot be undone unless you have another backup.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Replace everything'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      final restored = await _backup.restoreBackup(bytes);
      await widget.appearanceController?.reload();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Restored · ${restored.shortDescription}')),
      );
      // Pop back to Home so open screens cannot overwrite restored data.
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Restore failed: $error')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Backup & restore')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          Text(
            'Save a single file with your chats, characters, personas, '
            'lorebooks, Creation Center workshops, drafts, avatars, and '
            'settings. Use it after reinstalling Anima.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          Text(
            _useDesktopSaveDialog
                ? 'On this computer, Create backup opens a Save dialog '
                    '(Downloads is suggested). Pick a folder you can find later.'
                : 'On your phone, Create backup opens the system share sheet so '
                    'you can save the file to Files, Drive, or another app.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'The NanoGPT API key is not included — enter it again in '
            'API & connection after a restore.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 28),
          FilledButton.icon(
            onPressed: _busy ? null : _createBackup,
            icon: const Icon(Icons.upload_file),
            label: Text(_busy ? 'Working…' : 'Create backup'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _busy ? null : _restoreBackup,
            icon: const Icon(Icons.download),
            label: const Text('Restore backup'),
          ),
        ],
      ),
    );
  }
}
