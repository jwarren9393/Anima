import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../models/character.dart';
import '../models/living_world.dart';
import '../services/character_service.dart';
import '../services/living_world_service.dart';

/// Simple notebook editor — lists beat a giant workshop chat for canon.
class LivingWorldEditScreen extends StatefulWidget {
  const LivingWorldEditScreen({
    super.key,
    required this.worldService,
    required this.world,
    this.characterService,
  });

  final LivingWorldService worldService;
  final LivingWorld world;

  /// Optional — enables Pick card… / name suggest for person ↔ character links.
  final CharacterService? characterService;

  @override
  State<LivingWorldEditScreen> createState() => _LivingWorldEditScreenState();
}

class _LivingWorldEditScreenState extends State<LivingWorldEditScreen>
    with SingleTickerProviderStateMixin {
  late LivingWorld _world;
  late final TabController _tabs;
  late final TextEditingController _title;
  late final TextEditingController _genre;
  bool _dirty = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _world = widget.world;
    _title = TextEditingController(text: _world.title);
    _genre = TextEditingController(text: _world.genreNote);
    _tabs = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    _title.dispose();
    _genre.dispose();
    super.dispose();
  }

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

  Future<bool> _confirmLeave() async {
    if (!_dirty) return true;
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text('You have unsaved edits to this world notebook.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return leave == true;
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final next = _world.copyWith(
        title: _title.text.trim().isEmpty ? _world.title : _title.text.trim(),
        genreNote: _genre.text.trim(),
      );
      final saved = await widget.worldService.save(next);
      if (!mounted) return;
      setState(() {
        _world = saved;
        _dirty = false;
        _saving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('World saved')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '$e';
      });
    }
  }

  Future<void> _export() async {
    try {
      final bytes = widget.worldService.exportBytes(_world);
      final fileName = widget.worldService.exportFileName(_world);
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

  Future<void> _editPerson({WorldPerson? existing, int? index}) async {
    final result = await _showPersonDialog(existing);
    if (result == null) return;
    final people = List<WorldPerson>.from(_world.people);
    if (index != null) {
      people[index] = result;
    } else {
      people.add(result);
    }
    setState(() {
      _world = _world.copyWith(people: people);
      _dirty = true;
    });
  }

  Future<void> _editPlace({WorldPlace? existing, int? index}) async {
    final result = await _showPlaceDialog(existing);
    if (result == null) return;
    final places = List<WorldPlace>.from(_world.places);
    if (index != null) {
      places[index] = result;
    } else {
      places.add(result);
    }
    setState(() {
      _world = _world.copyWith(places: places);
      _dirty = true;
    });
  }

  Future<void> _editEvent({WorldEvent? existing, int? index}) async {
    final result = await _showEventDialog(existing);
    if (result == null) return;
    final events = List<WorldEvent>.from(_world.events);
    if (index != null) {
      events[index] = result;
    } else {
      events.add(result);
    }
    setState(() {
      _world = _world.copyWith(events: events);
      _dirty = true;
    });
  }

  Future<void> _editFlag({WorldFlag? existing, int? index}) async {
    final result = await _showFlagDialog(existing);
    if (result == null) return;
    final flags = List<WorldFlag>.from(_world.flags);
    if (index != null) {
      flags[index] = result;
    } else {
      flags.add(result);
    }
    setState(() {
      _world = _world.copyWith(flags: flags);
      _dirty = true;
    });
  }

  Future<void> _editThread({WorldThread? existing, int? index}) async {
    final result = await _showThreadDialog(existing);
    if (result == null) return;
    final threads = List<WorldThread>.from(_world.threads);
    if (index != null) {
      threads[index] = result;
    } else {
      threads.add(result);
    }
    setState(() {
      _world = _world.copyWith(threads: threads);
      _dirty = true;
    });
  }

  Future<void> _editPromise({WorldPromise? existing, int? index}) async {
    final result = await _showPromiseDialog(existing);
    if (result == null) return;
    final promises = List<WorldPromise>.from(_world.promises);
    if (index != null) {
      promises[index] = result;
    } else {
      promises.add(result);
    }
    setState(() {
      _world = _world.copyWith(promises: promises);
      _dirty = true;
    });
  }

  Future<void> _editSecret({WorldSecret? existing, int? index}) async {
    final result = await _showSecretDialog(existing);
    if (result == null) return;
    final secrets = List<WorldSecret>.from(_world.secrets);
    if (index != null) {
      secrets[index] = result;
    } else {
      secrets.add(result);
    }
    setState(() {
      _world = _world.copyWith(secrets: secrets);
      _dirty = true;
    });
  }

  Future<void> _editRelationship({
    WorldRelationship? existing,
    int? index,
  }) async {
    final result = await _showRelationshipDialog(existing);
    if (result == null) return;
    final rels = List<WorldRelationship>.from(_world.relationships);
    if (index != null) {
      rels[index] = result;
    } else {
      rels.add(result);
    }
    setState(() {
      _world = _world.copyWith(relationships: rels);
      _dirty = true;
    });
  }

  int get _canonCount =>
      _world.events.length +
      _world.flags.length +
      _world.threads.length +
      _world.promises.length +
      _world.secrets.length;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        if (await _confirmLeave() && mounted) {
          nav.pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_dirty ? '${_world.title} •' : _world.title),
          actions: [
            IconButton(
              tooltip: 'Save',
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
            ),
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'export') _export();
              },
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: 'export',
                  child: Text('Export JSON…'),
                ),
              ],
            ),
          ],
          bottom: TabBar(
            controller: _tabs,
            isScrollable: true,
            tabs: [
              const Tab(text: 'Overview'),
              Tab(text: 'Places (${_world.places.length})'),
              Tab(text: 'People (${_world.people.length})'),
              Tab(text: 'Links (${_world.relationships.length})'),
              Tab(text: 'Canon ($_canonCount)'),
            ],
          ),
        ),
        body: Column(
          children: [
            if (_error != null)
              Material(
                color: Theme.of(context).colorScheme.errorContainer,
                child: ListTile(
                  dense: true,
                  title: Text(_error!),
                  trailing: IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() => _error = null),
                  ),
                ),
              ),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [
                  _overviewTab(),
                  _placesTab(),
                  _peopleTab(),
                  _linksTab(),
                  _canonTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _overviewTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: _title,
          decoration: const InputDecoration(
            labelText: 'Title',
            border: OutlineInputBorder(),
          ),
          onChanged: (_) => _markDirty(),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _genre,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Setting note',
            hintText: 'Genre-agnostic tone / premise (optional)',
            border: OutlineInputBorder(),
            alignLabelWithHint: true,
          ),
          onChanged: (_) => _markDirty(),
        ),
        const SizedBox(height: 16),
        Text(
          '${_world.people.length} people · ${_world.places.length} places · '
          '${_world.relationships.length} links · ${_world.events.length} events · '
          '${_world.flags.length} flags · ${_world.threads.length} threads · '
          '${_world.promises.length} promises · ${_world.secrets.length} secrets',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        if (_world.liveState?.activePlaceId != null) ...[
          const SizedBox(height: 8),
          Text(
            'Active place: ${_world.liveState!.activePlaceId}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: 12),
        Text(
          'Id: ${_world.id}',
          style: Theme.of(context).textTheme.labelSmall,
        ),
      ],
    );
  }

  Widget _placesTab() {
    return _entityList(
      emptyLabel: 'No places yet. Add one or run the world factory.',
      onAdd: () => _editPlace(),
      children: [
        for (var i = 0; i < _world.places.length; i++)
          ListTile(
            title: Text(_world.places[i].name),
            subtitle: Text(
              _world.places[i].description.trim().isEmpty
                  ? _world.places[i].id
                  : _world.places[i].description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () => _editPlace(existing: _world.places[i], index: i),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () {
                final places = List<WorldPlace>.from(_world.places)..removeAt(i);
                setState(() {
                  _world = _world.copyWith(places: places);
                  _dirty = true;
                });
              },
            ),
          ),
      ],
    );
  }

  Widget _peopleTab() {
    return _entityList(
      emptyLabel: 'No people yet. Add one or run the world factory.',
      onAdd: () => _editPerson(),
      children: [
        for (var i = 0; i < _world.people.length; i++)
          ListTile(
            title: Text(_world.people[i].name),
            subtitle: Text(
              _personSubtitle(_world.people[i]),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () => _editPerson(existing: _world.people[i], index: i),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () {
                final people = List<WorldPerson>.from(_world.people)
                  ..removeAt(i);
                setState(() {
                  _world = _world.copyWith(people: people);
                  _dirty = true;
                });
              },
            ),
          ),
      ],
    );
  }

  String _personSubtitle(WorldPerson person) {
    final bits = <String>[];
    final cardId = person.characterCardId?.trim() ?? '';
    if (cardId.isNotEmpty) bits.add('Linked card: $cardId');
    final summary = person.summary.trim();
    if (summary.isNotEmpty) {
      bits.add(summary);
    } else if (bits.isEmpty) {
      bits.add(person.id);
    }
    return bits.join(' · ');
  }

  Widget _linksTab() {
    String nameOf(String id) {
      for (final p in _world.people) {
        if (p.id == id) return p.name;
      }
      return id;
    }

    return _entityList(
      emptyLabel: 'No relationships yet.',
      onAdd: _world.people.length < 2 ? null : () => _editRelationship(),
      children: [
        for (var i = 0; i < _world.relationships.length; i++)
          ListTile(
            title: Text(
              '${nameOf(_world.relationships[i].fromId)} → '
              '${nameOf(_world.relationships[i].toId)}',
            ),
            subtitle: Text(
              'score ${_world.relationships[i].score}'
              '${_world.relationships[i].labels.isEmpty ? '' : ' · ${_world.relationships[i].labels.join(', ')}'}',
            ),
            onTap: () => _editRelationship(
              existing: _world.relationships[i],
              index: i,
            ),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () {
                final rels = List<WorldRelationship>.from(_world.relationships)
                  ..removeAt(i);
                setState(() {
                  _world = _world.copyWith(relationships: rels);
                  _dirty = true;
                });
              },
            ),
          ),
      ],
    );
  }

  Widget _canonTab() {
    return ListView(
      children: [
        ListTile(
          title: Text(
            'Events',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          trailing: IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _editEvent(),
          ),
        ),
        if (_world.events.isEmpty)
          const ListTile(title: Text('No events yet.')),
        for (var i = 0; i < _world.events.length; i++)
          ListTile(
            title: Text(_world.events[i].text),
            subtitle: Text(_world.events[i].id),
            onTap: () => _editEvent(existing: _world.events[i], index: i),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () {
                final events = List<WorldEvent>.from(_world.events)
                  ..removeAt(i);
                setState(() {
                  _world = _world.copyWith(events: events);
                  _dirty = true;
                });
              },
            ),
          ),
        const Divider(),
        ListTile(
          title: Text(
            'Flags',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          trailing: IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _editFlag(),
          ),
        ),
        if (_world.flags.isEmpty)
          const ListTile(title: Text('No flags yet.')),
        for (var i = 0; i < _world.flags.length; i++)
          ListTile(
            title: Text(_world.flags[i].key),
            subtitle: Text('${_world.flags[i].value}'),
            onTap: () => _editFlag(existing: _world.flags[i], index: i),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () {
                final flags = List<WorldFlag>.from(_world.flags)..removeAt(i);
                setState(() {
                  _world = _world.copyWith(flags: flags);
                  _dirty = true;
                });
              },
            ),
          ),
        const Divider(),
        ListTile(
          title: Text(
            'Threads',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          trailing: IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _editThread(),
          ),
        ),
        if (_world.threads.isEmpty)
          const ListTile(title: Text('No threads yet.')),
        for (var i = 0; i < _world.threads.length; i++)
          ListTile(
            title: Text(
              '[${_world.threads[i].status.wire}] ${_world.threads[i].title}',
            ),
            subtitle: Text(
              _world.threads[i].summary.trim().isEmpty
                  ? _world.threads[i].id
                  : _world.threads[i].summary,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () => _editThread(existing: _world.threads[i], index: i),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () {
                final threads = List<WorldThread>.from(_world.threads)
                  ..removeAt(i);
                setState(() {
                  _world = _world.copyWith(threads: threads);
                  _dirty = true;
                });
              },
            ),
          ),
        const Divider(),
        ListTile(
          title: Text(
            'Promises',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          trailing: IconButton(
            icon: const Icon(Icons.add),
            onPressed:
                _world.people.length < 2 ? null : () => _editPromise(),
          ),
        ),
        if (_world.promises.isEmpty)
          const ListTile(title: Text('No promises yet.')),
        for (var i = 0; i < _world.promises.length; i++)
          ListTile(
            title: Text(
              '[${_world.promises[i].status.wire}] ${_world.promises[i].text}',
            ),
            subtitle: Text(
              '${_world.promises[i].fromId} → ${_world.promises[i].toId}',
            ),
            onTap: () =>
                _editPromise(existing: _world.promises[i], index: i),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () {
                final promises = List<WorldPromise>.from(_world.promises)
                  ..removeAt(i);
                setState(() {
                  _world = _world.copyWith(promises: promises);
                  _dirty = true;
                });
              },
            ),
          ),
        const Divider(),
        ListTile(
          title: Text(
            'Secrets',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          trailing: IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _editSecret(),
          ),
        ),
        if (_world.secrets.isEmpty)
          const ListTile(title: Text('No secrets yet.')),
        for (var i = 0; i < _world.secrets.length; i++)
          ListTile(
            title: Text(
              '[${_world.secrets[i].status.wire}] ${_world.secrets[i].text}',
            ),
            subtitle: Text(_world.secrets[i].id),
            onTap: () =>
                _editSecret(existing: _world.secrets[i], index: i),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () {
                final secrets = List<WorldSecret>.from(_world.secrets)
                  ..removeAt(i);
                setState(() {
                  _world = _world.copyWith(secrets: secrets);
                  _dirty = true;
                });
              },
            ),
          ),
      ],
    );
  }

  Widget _entityList({
    required String emptyLabel,
    required VoidCallback? onAdd,
    required List<Widget> children,
  }) {
    return Column(
      children: [
        if (onAdd != null)
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
              child: TextButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add),
                label: const Text('Add'),
              ),
            ),
          ),
        Expanded(
          child: children.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(emptyLabel, textAlign: TextAlign.center),
                  ),
                )
              : ListView(children: children),
        ),
      ],
    );
  }

  Future<WorldPerson?> _showPersonDialog(WorldPerson? existing) async {
    List<Character> library = const [];
    final characterService = widget.characterService;
    if (characterService != null) {
      try {
        library = await characterService.loadCharacters();
      } catch (_) {
        library = const [];
      }
    }
    if (!mounted) return null;

    return showDialog<WorldPerson>(
      context: context,
      builder: (context) => _PersonEditDialog(
        existing: existing,
        characters: library,
      ),
    );
  }

  Future<WorldPlace?> _showPlaceDialog(WorldPlace? existing) async {
    final id = TextEditingController(
      text: existing?.id ?? 'pl_${DateTime.now().millisecondsSinceEpoch}',
    );
    final name = TextEditingController(text: existing?.name ?? '');
    final description =
        TextEditingController(text: existing?.description ?? '');
    final connected = TextEditingController(
      text: existing?.connectedPlaceIds.join(', ') ?? '',
    );
    return showDialog<WorldPlace>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(existing == null ? 'Add place' : 'Edit place'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: id,
                decoration: const InputDecoration(labelText: 'Id'),
                enabled: existing == null,
              ),
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              TextField(
                controller: description,
                decoration: const InputDecoration(labelText: 'Description'),
                minLines: 2,
                maxLines: 3,
              ),
              TextField(
                controller: connected,
                decoration: const InputDecoration(
                  labelText: 'Connected place ids (comma-separated)',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final n = name.text.trim();
              final i = id.text.trim();
              if (n.isEmpty || i.isEmpty) return;
              Navigator.pop(
                context,
                WorldPlace(
                  id: i,
                  name: n,
                  description: description.text.trim(),
                  connectedPlaceIds: [
                    for (final part in connected.text.split(','))
                      if (part.trim().isNotEmpty) part.trim(),
                  ],
                ),
              );
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<WorldEvent?> _showEventDialog(WorldEvent? existing) async {
    final id = TextEditingController(
      text: existing?.id ?? 'e_${DateTime.now().millisecondsSinceEpoch}',
    );
    final text = TextEditingController(text: existing?.text ?? '');
    final at = TextEditingController(text: existing?.at ?? '');
    final placeId = TextEditingController(text: existing?.placeId ?? '');
    final personIds = TextEditingController(
      text: existing?.personIds.join(', ') ?? '',
    );
    return showDialog<WorldEvent>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(existing == null ? 'Add event' : 'Edit event'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: id,
                decoration: const InputDecoration(labelText: 'Id'),
                enabled: existing == null,
              ),
              TextField(
                controller: text,
                decoration: const InputDecoration(labelText: 'What happened'),
                minLines: 2,
                maxLines: 4,
              ),
              TextField(
                controller: at,
                decoration: const InputDecoration(labelText: 'When (optional)'),
              ),
              TextField(
                controller: placeId,
                decoration:
                    const InputDecoration(labelText: 'Place id (optional)'),
              ),
              TextField(
                controller: personIds,
                decoration: const InputDecoration(
                  labelText: 'Person ids (comma-separated)',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final t = text.text.trim();
              final i = id.text.trim();
              if (t.isEmpty || i.isEmpty) return;
              final place = placeId.text.trim();
              final when = at.text.trim();
              Navigator.pop(
                context,
                WorldEvent(
                  id: i,
                  text: t,
                  at: when.isEmpty ? null : when,
                  placeId: place.isEmpty ? null : place,
                  personIds: [
                    for (final part in personIds.text.split(','))
                      if (part.trim().isNotEmpty) part.trim(),
                  ],
                ),
              );
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<WorldFlag?> _showFlagDialog(WorldFlag? existing) async {
    final id = TextEditingController(
      text: existing?.id ?? 'f_${DateTime.now().millisecondsSinceEpoch}',
    );
    final key = TextEditingController(text: existing?.key ?? '');
    final value = TextEditingController(
      text: existing == null ? 'true' : '${existing.value}',
    );
    return showDialog<WorldFlag>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(existing == null ? 'Add flag' : 'Edit flag'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: id,
              decoration: const InputDecoration(labelText: 'Id'),
              enabled: existing == null,
            ),
            TextField(
              controller: key,
              decoration: const InputDecoration(labelText: 'Key'),
            ),
            TextField(
              controller: value,
              decoration: const InputDecoration(
                labelText: 'Value (true/false or short text)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final k = key.text.trim();
              final i = id.text.trim();
              if (k.isEmpty || i.isEmpty) return;
              final raw = value.text.trim();
              Object parsed = raw;
              if (raw.toLowerCase() == 'true') parsed = true;
              if (raw.toLowerCase() == 'false') parsed = false;
              final asNum = num.tryParse(raw);
              if (asNum != null) parsed = asNum;
              Navigator.pop(context, WorldFlag(id: i, key: k, value: parsed));
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<WorldThread?> _showThreadDialog(WorldThread? existing) async {
    final id = TextEditingController(
      text: existing?.id ?? 'th_${DateTime.now().millisecondsSinceEpoch}',
    );
    final title = TextEditingController(text: existing?.title ?? '');
    final summary = TextEditingController(text: existing?.summary ?? '');
    final placeId = TextEditingController(text: existing?.placeId ?? '');
    final personIds = TextEditingController(
      text: existing?.personIds.join(', ') ?? '',
    );
    final witnessIds = TextEditingController(
      text: existing?.witnessIds.join(', ') ?? '',
    );
    var status = existing?.status ?? WorldContinuityStatus.open;
    return showDialog<WorldThread>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(existing == null ? 'Add thread' : 'Edit thread'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: id,
                  decoration: const InputDecoration(labelText: 'Id'),
                  enabled: existing == null,
                ),
                TextField(
                  controller: title,
                  decoration: const InputDecoration(labelText: 'Title'),
                ),
                TextField(
                  controller: summary,
                  decoration: const InputDecoration(labelText: 'Summary'),
                  minLines: 2,
                  maxLines: 3,
                ),
                DropdownButtonFormField<WorldContinuityStatus>(
                  // ignore: deprecated_member_use
                  value: status,
                  decoration: const InputDecoration(labelText: 'Status'),
                  items: [
                    for (final s in WorldContinuityStatus.values)
                      DropdownMenuItem(value: s, child: Text(s.wire)),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    setLocal(() => status = v);
                  },
                ),
                TextField(
                  controller: placeId,
                  decoration:
                      const InputDecoration(labelText: 'Place id (optional)'),
                ),
                TextField(
                  controller: personIds,
                  decoration: const InputDecoration(
                    labelText: 'Person ids (comma-separated)',
                  ),
                ),
                TextField(
                  controller: witnessIds,
                  decoration: const InputDecoration(
                    labelText: 'Witness ids (comma-separated)',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final t = title.text.trim();
                final i = id.text.trim();
                if (t.isEmpty || i.isEmpty) return;
                final place = placeId.text.trim();
                Navigator.pop(
                  context,
                  WorldThread(
                    id: i,
                    title: t,
                    summary: summary.text.trim(),
                    status: status,
                    placeId: place.isEmpty ? null : place,
                    personIds: [
                      for (final part in personIds.text.split(','))
                        if (part.trim().isNotEmpty) part.trim(),
                    ],
                    witnessIds: [
                      for (final part in witnessIds.text.split(','))
                        if (part.trim().isNotEmpty) part.trim(),
                    ],
                  ),
                );
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<WorldPromise?> _showPromiseDialog(WorldPromise? existing) async {
    if (_world.people.length < 2) return null;
    var fromId = existing?.fromId ?? _world.people.first.id;
    var toId = existing?.toId ?? _world.people[1].id;
    final id = TextEditingController(
      text: existing?.id ?? 'pr_${DateTime.now().millisecondsSinceEpoch}',
    );
    final text = TextEditingController(text: existing?.text ?? '');
    final placeId = TextEditingController(text: existing?.placeId ?? '');
    var status = existing?.status ?? WorldContinuityStatus.open;
    return showDialog<WorldPromise>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(existing == null ? 'Add promise' : 'Edit promise'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: id,
                  decoration: const InputDecoration(labelText: 'Id'),
                  enabled: existing == null,
                ),
                TextField(
                  controller: text,
                  decoration: const InputDecoration(labelText: 'Promise text'),
                  minLines: 2,
                  maxLines: 3,
                ),
                DropdownButtonFormField<String>(
                  // ignore: deprecated_member_use
                  value: fromId,
                  decoration: const InputDecoration(labelText: 'From'),
                  items: [
                    for (final p in _world.people)
                      DropdownMenuItem(value: p.id, child: Text(p.name)),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    setLocal(() => fromId = v);
                  },
                ),
                DropdownButtonFormField<String>(
                  // ignore: deprecated_member_use
                  value: toId,
                  decoration: const InputDecoration(labelText: 'To'),
                  items: [
                    for (final p in _world.people)
                      DropdownMenuItem(value: p.id, child: Text(p.name)),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    setLocal(() => toId = v);
                  },
                ),
                DropdownButtonFormField<WorldContinuityStatus>(
                  // ignore: deprecated_member_use
                  value: status,
                  decoration: const InputDecoration(labelText: 'Status'),
                  items: [
                    for (final s in WorldContinuityStatus.values)
                      DropdownMenuItem(value: s, child: Text(s.wire)),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    setLocal(() => status = v);
                  },
                ),
                TextField(
                  controller: placeId,
                  decoration:
                      const InputDecoration(labelText: 'Place id (optional)'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final t = text.text.trim();
                final i = id.text.trim();
                if (t.isEmpty || i.isEmpty || fromId == toId) return;
                final place = placeId.text.trim();
                Navigator.pop(
                  context,
                  WorldPromise(
                    id: i,
                    text: t,
                    fromId: fromId,
                    toId: toId,
                    status: status,
                    placeId: place.isEmpty ? null : place,
                  ),
                );
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<WorldSecret?> _showSecretDialog(WorldSecret? existing) async {
    final id = TextEditingController(
      text: existing?.id ?? 'sec_${DateTime.now().millisecondsSinceEpoch}',
    );
    final text = TextEditingController(text: existing?.text ?? '');
    final placeId = TextEditingController(text: existing?.placeId ?? '');
    final subjectIds = TextEditingController(
      text: existing?.subjectIds.join(', ') ?? '',
    );
    final witnessIds = TextEditingController(
      text: existing?.witnessIds.join(', ') ?? '',
    );
    var status = existing?.status ?? WorldContinuityStatus.open;
    return showDialog<WorldSecret>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(existing == null ? 'Add secret' : 'Edit secret'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: id,
                  decoration: const InputDecoration(labelText: 'Id'),
                  enabled: existing == null,
                ),
                TextField(
                  controller: text,
                  decoration: const InputDecoration(labelText: 'Secret text'),
                  minLines: 2,
                  maxLines: 4,
                ),
                DropdownButtonFormField<WorldContinuityStatus>(
                  // ignore: deprecated_member_use
                  value: status,
                  decoration: const InputDecoration(labelText: 'Status'),
                  items: [
                    for (final s in WorldContinuityStatus.values)
                      DropdownMenuItem(value: s, child: Text(s.wire)),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    setLocal(() => status = v);
                  },
                ),
                TextField(
                  controller: subjectIds,
                  decoration: const InputDecoration(
                    labelText: 'Subject person ids (comma-separated)',
                  ),
                ),
                TextField(
                  controller: witnessIds,
                  decoration: const InputDecoration(
                    labelText: 'Witness person ids (comma-separated)',
                  ),
                ),
                TextField(
                  controller: placeId,
                  decoration:
                      const InputDecoration(labelText: 'Place id (optional)'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final t = text.text.trim();
                final i = id.text.trim();
                if (t.isEmpty || i.isEmpty) return;
                final place = placeId.text.trim();
                Navigator.pop(
                  context,
                  WorldSecret(
                    id: i,
                    text: t,
                    status: status,
                    placeId: place.isEmpty ? null : place,
                    subjectIds: [
                      for (final part in subjectIds.text.split(','))
                        if (part.trim().isNotEmpty) part.trim(),
                    ],
                    witnessIds: [
                      for (final part in witnessIds.text.split(','))
                        if (part.trim().isNotEmpty) part.trim(),
                    ],
                  ),
                );
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<WorldRelationship?> _showRelationshipDialog(
    WorldRelationship? existing,
  ) async {
    if (_world.people.length < 2) return null;
    var fromId = existing?.fromId ?? _world.people.first.id;
    var toId = existing?.toId ?? _world.people[1].id;
    final score = TextEditingController(
      text: '${existing?.score ?? 0}',
    );
    final labels = TextEditingController(
      text: existing?.labels.join(', ') ?? '',
    );
    return showDialog<WorldRelationship>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(
            existing == null ? 'Add relationship' : 'Edit relationship',
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  // ignore: deprecated_member_use
                  value: fromId,
                  decoration: const InputDecoration(labelText: 'From'),
                  items: [
                    for (final p in _world.people)
                      DropdownMenuItem(value: p.id, child: Text(p.name)),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    setLocal(() => fromId = v);
                  },
                ),
                DropdownButtonFormField<String>(
                  // ignore: deprecated_member_use
                  value: toId,
                  decoration: const InputDecoration(labelText: 'To'),
                  items: [
                    for (final p in _world.people)
                      DropdownMenuItem(value: p.id, child: Text(p.name)),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    setLocal(() => toId = v);
                  },
                ),
                TextField(
                  controller: score,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Score (−100…100)',
                  ),
                ),
                TextField(
                  controller: labels,
                  decoration: const InputDecoration(
                    labelText: 'Labels (comma-separated)',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (fromId == toId) return;
                final s = int.tryParse(score.text.trim()) ?? 0;
                Navigator.pop(
                  context,
                  WorldRelationship(
                    fromId: fromId,
                    toId: toId,
                    score: s.clamp(-100, 100),
                    labels: [
                      for (final part in labels.text.split(','))
                        if (part.trim().isNotEmpty) part.trim(),
                    ],
                  ),
                );
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Person editor with optional character-card picker + name suggest.
class _PersonEditDialog extends StatefulWidget {
  const _PersonEditDialog({
    required this.existing,
    required this.characters,
  });

  final WorldPerson? existing;
  final List<Character> characters;

  @override
  State<_PersonEditDialog> createState() => _PersonEditDialogState();
}

class _PersonEditDialogState extends State<_PersonEditDialog> {
  late final TextEditingController _id;
  late final TextEditingController _name;
  late final TextEditingController _summary;
  late final TextEditingController _notes;
  late final TextEditingController _routine;
  late final TextEditingController _inventory;
  String? _cardId;
  bool _dismissedSuggest = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _id = TextEditingController(
      text: existing?.id ?? 'p_${DateTime.now().millisecondsSinceEpoch}',
    );
    _name = TextEditingController(text: existing?.name ?? '');
    _summary = TextEditingController(text: existing?.summary ?? '');
    _notes = TextEditingController(text: existing?.personalityNotes ?? '');
    _routine = TextEditingController(text: existing?.routineHints ?? '');
    _inventory = TextEditingController(
      text: existing?.inventory.join(', ') ?? '',
    );
    _cardId = existing?.characterCardId?.trim();
    if (_cardId != null && _cardId!.isEmpty) _cardId = null;
    _name.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _id.dispose();
    _name.dispose();
    _summary.dispose();
    _notes.dispose();
    _routine.dispose();
    _inventory.dispose();
    super.dispose();
  }

  Character? _characterById(String? id) {
    final trimmed = id?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    for (final c in widget.characters) {
      if (c.id == trimmed) return c;
    }
    return null;
  }

  List<Character> _nameSuggestions() {
    if (_cardId != null && _cardId!.isNotEmpty) return const [];
    if (_dismissedSuggest) return const [];
    final needle = _name.text.trim().toLowerCase();
    if (needle.length < 2) return const [];
    final hits = <Character>[];
    for (final c in widget.characters) {
      final n = c.name.trim().toLowerCase();
      if (n.isEmpty) continue;
      if (n == needle || n.contains(needle) || needle.contains(n)) {
        hits.add(c);
      }
      if (hits.length >= 5) break;
    }
    return hits;
  }

  Future<void> _pickCard() async {
    if (widget.characters.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No character cards yet — create one in Characters.'),
        ),
      );
      return;
    }
    final picked = await showModalBottomSheet<Character>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: ListView(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Text(
                  'Link character card',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              for (final c in widget.characters)
                ListTile(
                  title: Text(c.name.trim().isEmpty ? c.id : c.name.trim()),
                  subtitle: Text(c.id, maxLines: 1),
                  onTap: () => Navigator.pop(context, c),
                ),
            ],
          ),
        );
      },
    );
    if (picked == null || !mounted) return;
    setState(() {
      _cardId = picked.id;
      _dismissedSuggest = true;
      if (_name.text.trim().isEmpty && picked.name.trim().isNotEmpty) {
        _name.text = picked.name.trim();
      }
    });
  }

  void _save() {
    final n = _name.text.trim();
    final i = _id.text.trim();
    if (n.isEmpty || i.isEmpty) return;
    final card = _cardId?.trim();
    Navigator.pop(
      context,
      WorldPerson(
        id: i,
        name: n,
        summary: _summary.text.trim(),
        personalityNotes: _notes.text.trim(),
        routineHints: _routine.text.trim(),
        inventory: [
          for (final part in _inventory.text.split(','))
            if (part.trim().isNotEmpty) part.trim(),
        ],
        characterCardId: (card == null || card.isEmpty) ? null : card,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final linked = _characterById(_cardId);
    final suggestions = _nameSuggestions();
    final scheme = Theme.of(context).colorScheme;

    return AlertDialog(
      title: Text(widget.existing == null ? 'Add person' : 'Edit person'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _id,
              decoration: const InputDecoration(labelText: 'Id'),
              enabled: widget.existing == null,
            ),
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            TextField(
              controller: _summary,
              decoration: const InputDecoration(labelText: 'Summary'),
              minLines: 2,
              maxLines: 3,
            ),
            TextField(
              controller: _notes,
              decoration:
                  const InputDecoration(labelText: 'Personality notes'),
              minLines: 2,
              maxLines: 3,
            ),
            TextField(
              controller: _routine,
              decoration: const InputDecoration(
                labelText: 'Routine hints (optional)',
                hintText: 'Mornings at the pier; evenings at the inn',
              ),
              minLines: 1,
              maxLines: 2,
            ),
            TextField(
              controller: _inventory,
              decoration: const InputDecoration(
                labelText: 'Inventory (comma-separated, optional)',
                hintText: 'letter, pier ledger',
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Linked character card',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 4),
            if (linked != null)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  linked.name.trim().isEmpty ? linked.id : linked.name.trim(),
                ),
                subtitle: Text(linked.id),
                trailing: IconButton(
                  tooltip: 'Clear link',
                  icon: const Icon(Icons.link_off),
                  onPressed: () => setState(() {
                    _cardId = null;
                    _dismissedSuggest = false;
                  }),
                ),
              )
            else if (_cardId != null && _cardId!.isNotEmpty)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Card id: $_cardId'),
                subtitle: const Text('Card not found in library'),
                trailing: IconButton(
                  tooltip: 'Clear link',
                  icon: const Icon(Icons.link_off),
                  onPressed: () => setState(() {
                    _cardId = null;
                    _dismissedSuggest = false;
                  }),
                ),
              )
            else
              Text(
                widget.characters.isEmpty
                    ? 'No library cards to link yet.'
                    : 'Optional — when this card speaks in chat, the pack '
                        'prioritizes this person.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: widget.characters.isEmpty ? null : _pickCard,
              icon: const Icon(Icons.badge_outlined),
              label: Text(
                linked == null && (_cardId == null || _cardId!.isEmpty)
                    ? 'Pick card…'
                    : 'Change card…',
              ),
            ),
            if (suggestions.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Suggested by name',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
              for (final c in suggestions)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(c.name.trim().isEmpty ? c.id : c.name.trim()),
                  trailing: TextButton(
                    onPressed: () => setState(() {
                      _cardId = c.id;
                      _dismissedSuggest = true;
                    }),
                    child: const Text('Link'),
                  ),
                ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
