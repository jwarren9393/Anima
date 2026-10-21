import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/living_world.dart';
import '../models/living_world_update_policy.dart';
import '../services/living_world_service.dart';
import '../services/nanogpt_service.dart';
import '../services/settings_service.dart';
import '../widgets/living_world_factory_sheet.dart';
import '../widgets/living_world_picker.dart';
import 'living_world_edit_screen.dart';

/// Living Worlds hub — list / create / factory / import notebooks.
///
/// Separate from Creation Center (workshop chat). This is the warehouse +
/// multi-pass world factory for structured canon JSON.
class WorldsHubScreen extends StatefulWidget {
  WorldsHubScreen({
    super.key,
    required this.settingsService,
    required this.nanoGptService,
    LivingWorldService? worldService,
  }) : worldService = worldService ?? LivingWorldService();

  final SettingsService settingsService;
  final NanoGptService nanoGptService;
  final LivingWorldService worldService;

  @override
  State<WorldsHubScreen> createState() => _WorldsHubScreenState();
}

class _WorldsHubScreenState extends State<WorldsHubScreen> {
  List<LivingWorldSummary> _worlds = [];
  bool _loading = true;
  String? _error;
  LivingWorldUpdatePolicy _policy = LivingWorldUpdatePolicy.manual;
  bool _resolveBeforeNarrate = false;

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
      final worlds = await widget.worldService.listSummaries();
      final policy = await widget.settingsService.getLivingWorldUpdatePolicy();
      final livingMode =
          await widget.settingsService.getLivingWorldResolveBeforeNarrate();
      if (!mounted) return;
      setState(() {
        _worlds = worlds;
        _policy = policy;
        _resolveBeforeNarrate = livingMode;
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

  Future<void> _setPolicy(LivingWorldUpdatePolicy policy) async {
    await widget.settingsService.setLivingWorldUpdatePolicy(policy);
    if (!mounted) return;
    setState(() => _policy = policy);
  }

  Future<void> _setResolveBeforeNarrate(bool enabled) async {
    await widget.settingsService.setLivingWorldResolveBeforeNarrate(enabled);
    if (!mounted) return;
    setState(() => _resolveBeforeNarrate = enabled);
  }

  Future<void> _open(LivingWorldSummary summary) async {
    final world = await widget.worldService.getById(summary.id);
    if (world == null || !mounted) {
      setState(() => _error = 'Could not open that world file.');
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LivingWorldEditScreen(
          worldService: widget.worldService,
          world: world,
        ),
      ),
    );
    await _load();
  }

  Future<void> _createEmpty() async {
    final world = await widget.worldService.createEmpty(title: 'New world');
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LivingWorldEditScreen(
          worldService: widget.worldService,
          world: world,
        ),
      ),
    );
    await _load();
  }

  Future<void> _createSample() async {
    final world = await widget.worldService.save(buildSampleHarborWorld());
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LivingWorldEditScreen(
          worldService: widget.worldService,
          world: world,
        ),
      ),
    );
    await _load();
  }

  Future<void> _import() async {
    try {
      final pick = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json'],
        withData: true,
      );
      if (pick == null || !mounted) return;
      final file = pick.files.single;
      final bytes =
          file.bytes ??
          (file.path != null ? await File(file.path!).readAsBytes() : null);
      if (bytes == null) {
        setState(() => _error = 'Could not read that file.');
        return;
      }
      final world = await widget.worldService.importFromBytes(
        bytes,
        fileName: file.name,
      );
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => LivingWorldEditScreen(
            worldService: widget.worldService,
            world: world,
          ),
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Import failed: $e');
    }
  }

  Future<void> _runFactory() async {
    final world = await showLivingWorldFactorySheet(
      context: context,
      worldService: widget.worldService,
      nanoGptService: widget.nanoGptService,
      settingsService: widget.settingsService,
    );
    if (world == null || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LivingWorldEditScreen(
          worldService: widget.worldService,
          world: world,
        ),
      ),
    );
    await _load();
  }

  Future<void> _delete(LivingWorldSummary summary) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete world?'),
        content: Text(
          'Delete “${summary.title}”? Chats bound to it will keep the id '
          'until you turn Living World off in those chats.',
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
    if (ok != true) return;
    await widget.worldService.delete(summary.id);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Living Worlds'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _runFactory,
        icon: const Icon(Icons.auto_awesome),
        label: const Text('World factory'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(0, 8, 0, 88),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: Text(
                      'Structured world notebooks for chat-native Living World '
                      'play. The factory builds one on disk in passes — this is '
                      'not Creation Center workshop chat.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Text(
                      'During play',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  for (final policy in LivingWorldUpdatePolicy.values)
                    ListTile(
                      leading: Icon(
                        policy == _policy
                            ? Icons.check_circle
                            : Icons.circle_outlined,
                      ),
                      title: Text(policy.menuLabel),
                      subtitle: Text(policy.helpText),
                      onTap: () => _setPolicy(policy),
                    ),
                  SwitchListTile(
                    secondary: const Icon(Icons.sync_alt),
                    title: const Text('Resolve before reply (Living mode)'),
                    subtitle: const Text(
                      'Extra API call: decide safe facts, save them, then '
                      'roleplay from the updated world. Needs Propose or '
                      'Auto-safe play mode. Off = Phase 5 after-turn only.',
                    ),
                    value: _resolveBeforeNarrate,
                    onChanged: _setResolveBeforeNarrate,
                  ),
                  const Divider(),
                  if (_error != null)
                    ListTile(
                      leading: Icon(
                        Icons.error_outline,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      title: Text(_error!),
                      trailing: IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() => _error = null),
                      ),
                    ),
                  ListTile(
                    leading: const Icon(Icons.note_add_outlined),
                    title: const Text('Create empty world'),
                    onTap: _createEmpty,
                  ),
                  ListTile(
                    leading: const Icon(Icons.holiday_village_outlined),
                    title: const Text('Create sample harbor town'),
                    subtitle: const Text('Tiny demo for retrieval'),
                    onTap: _createSample,
                  ),
                  ListTile(
                    leading: const Icon(Icons.upload_file_outlined),
                    title: const Text('Import world JSON'),
                    onTap: _import,
                  ),
                  const Divider(),
                  if (_worlds.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'No worlds yet. Run the world factory, create a sample, '
                        'or import a JSON notebook.',
                        textAlign: TextAlign.center,
                      ),
                    )
                  else
                    for (final world in _worlds)
                      ListTile(
                        leading: const Icon(Icons.public_outlined),
                        title: Text(world.title),
                        subtitle: Text(
                          '${world.personCount} people · '
                          '${world.placeCount} places',
                        ),
                        onTap: () => _open(world),
                        trailing: IconButton(
                          tooltip: 'Delete',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _delete(world),
                        ),
                      ),
                ],
              ),
            ),
    );
  }
}
