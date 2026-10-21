import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../models/living_world.dart';
import '../models/living_world_tick_settings.dart';
import '../models/living_world_update_policy.dart';
import '../models/turn_resolution.dart';
import '../services/character_service.dart';
import '../services/living_world_log_service.dart';
import '../services/living_world_pending_service.dart';
import '../services/living_world_service.dart';
import '../services/living_world_simulator.dart';
import '../services/living_world_undo_service.dart';
import '../services/living_world_update_service.dart';
import '../services/nanogpt_service.dart';
import '../services/settings_service.dart';
import '../widgets/living_world_factory_sheet.dart';
import '../widgets/living_world_log_sheet.dart';
import '../widgets/living_world_picker.dart';
import '../widgets/living_world_update_sheet.dart';
import 'living_world_edit_screen.dart';
import 'settings_ui.dart';

/// Living Worlds hub — list / create / factory / import notebooks.
///
/// Separate from Creation Center (workshop chat). This is the warehouse +
/// multi-pass world factory for structured canon JSON.
class WorldsHubScreen extends StatefulWidget {
  WorldsHubScreen({
    super.key,
    required this.settingsService,
    required this.nanoGptService,
    this.characterService,
    LivingWorldService? worldService,
  }) : worldService = worldService ?? LivingWorldService();

  final SettingsService settingsService;
  final NanoGptService nanoGptService;
  final CharacterService? characterService;
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
  LivingWorldTickSettings _tickSettings = LivingWorldTickSettings.defaults;
  bool _tickBusy = false;
  Map<String, int> _pendingCounts = {};

  final _simulator = const LivingWorldSimulator();
  final _updates = const LivingWorldUpdateService();
  final _undo = LivingWorldUndoService();
  final _log = LivingWorldLogService();
  final _pending = LivingWorldPendingService();

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
      final tick = await widget.settingsService.getLivingWorldTickSettings();
      final pending = <String, int>{};
      for (final w in worlds) {
        pending[w.id] = await _pending.count(w.id);
      }
      if (!mounted) return;
      setState(() {
        _worlds = worlds;
        _policy = policy;
        _resolveBeforeNarrate = livingMode;
        _tickSettings = tick;
        _pendingCounts = pending;
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

  Future<void> _setTickSettings(LivingWorldTickSettings settings) async {
    final next = settings.clamped();
    await widget.settingsService.setLivingWorldTickSettings(next);
    if (!mounted) return;
    setState(() => _tickSettings = next);
  }

  Future<void> _advanceBeat(LivingWorldSummary summary) async {
    if (_tickBusy) return;
    setState(() {
      _tickBusy = true;
      _error = null;
    });
    try {
      final world = await widget.worldService.getById(summary.id);
      if (world == null || !mounted) {
        setState(() {
          _tickBusy = false;
          _error = 'Could not open that world file.';
        });
        return;
      }
      final plan = _simulator.planTick(world, settings: _tickSettings);
      if (!mounted) return;
      if (plan.isEmpty) {
        setState(() => _tickBusy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Nothing nearby to advance — set an active place or add people.',
            ),
          ),
        );
        return;
      }
      setState(() => _tickBusy = false);
      final selected = await showLivingWorldUpdateSheet(
        context: context,
        updates: plan.ops,
        title: 'Advance a beat — ${world.title}',
      );
      if (selected == null || selected.isEmpty || !mounted) return;

      setState(() => _tickBusy = true);
      await _undo.pushSnapshot(world);
      final updated = _updates.applyUpdates(world, selected);
      await widget.worldService.save(updated);
      await _log.append(
        TurnResolution(
          worldId: world.id,
          at: DateTime.now(),
          kind: TurnResolutionKind.nearSceneTick,
          proposed: plan.ops,
          applied: selected,
        ),
      );
      if (!mounted) return;
      setState(() => _tickBusy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Advanced ${selected.length} near-scene '
            '${selected.length == 1 ? 'change' : 'changes'}.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _tickBusy = false;
        _error = 'Advance beat failed: $e';
      });
    }
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
          characterService: widget.characterService,
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
          characterService: widget.characterService,
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
          characterService: widget.characterService,
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
            characterService: widget.characterService,
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
      characterService: widget.characterService,
    );
    if (world == null || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LivingWorldEditScreen(
          worldService: widget.worldService,
          world: world,
          characterService: widget.characterService,
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

  Future<void> _showTimeline(LivingWorldSummary summary) async {
    await showLivingWorldLogSheet(
      context: context,
      worldId: summary.id,
      worldTitle: summary.title,
      logService: _log,
      undoService: _undo,
      worldService: widget.worldService,
      showRevert: true,
      onReverted: () => _load(),
    );
  }

  Future<void> _undoLastPack(LivingWorldSummary summary) async {
    final can = await _undo.canUndo(summary.id);
    if (!can) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nothing to undo for this notebook yet.'),
        ),
      );
      return;
    }
    final restored = await _undo.undoLast(
      worldService: widget.worldService,
      worldId: summary.id,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          restored == null
              ? 'Undo failed.'
              : 'Reverted last applied pack for “${summary.title}”.',
        ),
      ),
    );
    await _load();
  }

  Future<void> _exportWorld(LivingWorldSummary summary) async {
    try {
      final world = await widget.worldService.getById(summary.id);
      if (world == null || !mounted) {
        setState(() => _error = 'Could not open that world file.');
        return;
      }
      final bytes = widget.worldService.exportBytes(world);
      final fileName = widget.worldService.exportFileName(world);
      String? initialDirectory;
      try {
        initialDirectory = (await getDownloadsDirectory())?.path;
      } catch (_) {}
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Export Living World',
        fileName: fileName,
        initialDirectory: initialDirectory,
        type: FileType.any,
        bytes: bytes,
      );
      if (path == null || !mounted) return;
      await File(path).writeAsBytes(bytes, flush: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Exported · $path')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Export failed: $e');
    }
  }

  Future<void> _reviewPending(LivingWorldSummary summary) async {
    final pending = await _pending.list(summary.id);
    if (pending.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No pending changes for this world.')),
      );
      await _load();
      return;
    }
    final world = await widget.worldService.getById(summary.id);
    if (world == null || !mounted) return;
    final selected = await showLivingWorldUpdateSheet(
      context: context,
      updates: pending,
      title: 'Review pending — ${world.title}',
    );
    if (selected == null || selected.isEmpty || !mounted) return;
    await _undo.pushSnapshot(world);
    final updated = _updates.applyUpdates(world, selected);
    await widget.worldService.save(updated);
    await _log.append(
      TurnResolution(
        worldId: world.id,
        at: DateTime.now(),
        kind: TurnResolutionKind.afterTurn,
        proposed: pending,
        applied: selected,
      ),
    );
    await _pending.removeApplied(summary.id, selected);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Saved ${selected.length} pending '
          '${selected.length == 1 ? 'update' : 'updates'}.',
        ),
      ),
    );
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
                    child: SettingsUi.sectionHint(
                      context,
                      'Structured world notebooks for chat-native Living World '
                      'play. The factory builds one on disk in passes — this is '
                      'not Creation Center workshop chat. Unbound chats stay '
                      'classic Anima.',
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: SettingsUi.sectionTitle(context, 'During play'),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: SettingsUi.sectionHint(
                      context,
                      'Pick how chat writes into the notebook. Auto-safe is the '
                      '“invisible engine” feel: safe facts save quietly; '
                      'relationships wait on Review pending. You can always '
                      'undo the last pack or edit the notebook by hand.',
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
                      'Extra API call: decide and save safe facts first, then '
                      'the AI speaks from that updated truth. Needs Propose or '
                      'Auto-safe. Off = update after the reply only. Reply '
                      'starts a little later when this is on.',
                    ),
                    value: _resolveBeforeNarrate,
                    onChanged: _setResolveBeforeNarrate,
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                    child: SettingsUi.sectionTitle(context, 'Near-scene ticks'),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: SettingsUi.sectionHint(
                      context,
                      'Tiny shifts around the active place and its neighbors '
                      '(not the whole cast). Unbound chats never tick. '
                      'Default is off — use Advance world a beat… when you want one.',
                    ),
                  ),
                  for (final trigger in LivingWorldTickTrigger.values)
                    ListTile(
                      leading: Icon(
                        trigger == _tickSettings.trigger
                            ? Icons.check_circle
                            : Icons.circle_outlined,
                      ),
                      title: Text(trigger.menuLabel),
                      subtitle: Text(trigger.helpText),
                      onTap: () => _setTickSettings(
                        _tickSettings.copyWith(trigger: trigger),
                      ),
                    ),
                  if (_tickSettings.trigger == LivingWorldTickTrigger.everyN)
                    ListTile(
                      leading: const Icon(Icons.repeat),
                      title: Text('Every ${_tickSettings.everyN} turns'),
                      subtitle: const Text('Tap to pick 2–10'),
                      onTap: () async {
                        final picked = await showDialog<int>(
                          context: context,
                          builder: (context) => SimpleDialog(
                            title: const Text('Tick every N turns'),
                            children: [
                              for (final n in [2, 3, 4, 5, 6, 8, 10])
                                SimpleDialogOption(
                                  onPressed: () => Navigator.pop(context, n),
                                  child: Text('Every $n turns'),
                                ),
                            ],
                          ),
                        );
                        if (picked == null || !mounted) return;
                        await _setTickSettings(
                          _tickSettings.copyWith(everyN: picked),
                        );
                      },
                    ),
                  ListTile(
                    leading: const Icon(Icons.groups_outlined),
                    title: Text(
                      'Max ${_tickSettings.maxPeople} people · '
                      '${_tickSettings.maxOps} ops · '
                      '${_tickSettings.radiusHops}-hop radius',
                    ),
                    subtitle: const Text('Tap to adjust tick caps'),
                    onTap: () async {
                      var people = _tickSettings.maxPeople;
                      var ops = _tickSettings.maxOps;
                      var hops = _tickSettings.radiusHops;
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (context) => StatefulBuilder(
                          builder: (context, setLocal) => AlertDialog(
                            title: const Text('Tick caps'),
                            content: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('People touched: $people'),
                                Slider(
                                  value: people.toDouble(),
                                  min: 1,
                                  max: 12,
                                  divisions: 11,
                                  label: '$people',
                                  onChanged: (v) =>
                                      setLocal(() => people = v.round()),
                                ),
                                Text('Max ops: $ops'),
                                Slider(
                                  value: ops.toDouble(),
                                  min: 1,
                                  max: 12,
                                  divisions: 11,
                                  label: '$ops',
                                  onChanged: (v) =>
                                      setLocal(() => ops = v.round()),
                                ),
                                Text('Place radius hops: $hops'),
                                Slider(
                                  value: hops.toDouble(),
                                  min: 0,
                                  max: 2,
                                  divisions: 2,
                                  label: '$hops',
                                  onChanged: (v) =>
                                      setLocal(() => hops = v.round()),
                                ),
                              ],
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('Cancel'),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text('Save'),
                              ),
                            ],
                          ),
                        ),
                      );
                      if (ok != true || !mounted) return;
                      await _setTickSettings(
                        _tickSettings.copyWith(
                          maxPeople: people,
                          maxOps: ops,
                          radiusHops: hops,
                        ),
                      );
                    },
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
                          [
                            '${world.personCount} people · '
                                '${world.placeCount} places',
                            if ((_pendingCounts[world.id] ?? 0) > 0)
                              '${_pendingCounts[world.id]} pending review',
                          ].join(' · '),
                        ),
                        onTap: () => _open(world),
                        trailing: PopupMenuButton<String>(
                          enabled: !_tickBusy,
                          onSelected: (value) {
                            if (value == 'timeline') _showTimeline(world);
                            if (value == 'pending') _reviewPending(world);
                            if (value == 'undo') _undoLastPack(world);
                            if (value == 'export') _exportWorld(world);
                            if (value == 'advance') _advanceBeat(world);
                            if (value == 'delete') _delete(world);
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'timeline',
                              child: Text('Timeline…'),
                            ),
                            if ((_pendingCounts[world.id] ?? 0) > 0)
                              PopupMenuItem(
                                value: 'pending',
                                child: Text(
                                  'Review pending '
                                  '(${_pendingCounts[world.id]})…',
                                ),
                              ),
                            const PopupMenuItem(
                              value: 'undo',
                              child: Text('Undo last pack'),
                            ),
                            const PopupMenuItem(
                              value: 'export',
                              child: Text('Export JSON…'),
                            ),
                            const PopupMenuItem(
                              value: 'advance',
                              child: Text('Advance world a beat…'),
                            ),
                            const PopupMenuItem(
                              value: 'delete',
                              child: Text('Delete'),
                            ),
                          ],
                        ),
                      ),
                ],
              ),
            ),
    );
  }
}
