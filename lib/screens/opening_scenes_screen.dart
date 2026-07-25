import 'package:flutter/material.dart';

import '../models/saved_opening_scene.dart';
import '../services/opening_scene_service.dart';
import '../services/world_workshop_service.dart';

/// Browse, create, and edit saved opening scenes for new chats.
class OpeningScenesScreen extends StatefulWidget {
  const OpeningScenesScreen({
    super.key,
    required this.openingSceneService,
    required this.workshopService,
    this.pickMode = false,
  });

  final OpeningSceneService openingSceneService;
  final WorldWorkshopService workshopService;
  final bool pickMode;

  @override
  State<OpeningScenesScreen> createState() => _OpeningScenesScreenState();
}

class _OpeningScenesScreenState extends State<OpeningScenesScreen> {
  List<SavedOpeningScene> _scenes = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final workshops = await widget.workshopService.loadWorkshops();
    await widget.openingSceneService.importMissingFromWorkshops(workshops);
    final scenes = await widget.openingSceneService.loadScenes();
    if (!mounted) return;
    setState(() {
      _scenes = scenes;
      _loading = false;
    });
  }

  Future<void> _editScene({SavedOpeningScene? existing}) async {
    final titleController = TextEditingController(text: existing?.title ?? '');
    final textController = TextEditingController(text: existing?.text ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            existing == null ? 'New opening scene' : 'Edit opening scene',
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(
                    labelText: 'Title',
                    hintText: 'e.g. Harbor night',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: textController,
                  minLines: 5,
                  maxLines: 12,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Opening scene',
                    hintText: 'Narrator setup prose…',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                ),
              ],
            ),
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
        );
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      titleController.dispose();
      textController.dispose();
    });
    if (saved != true || !mounted) return;

    final title = titleController.text.trim();
    final text = textController.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Opening scene text cannot be empty.')),
      );
      return;
    }

    await widget.openingSceneService.upsert(
      SavedOpeningScene(
        id: existing?.id ?? SavedOpeningScene.newId(),
        title: title.isEmpty ? 'Opening scene' : title,
        text: text,
        updatedAt: DateTime.now(),
        workshopId: existing?.workshopId,
      ),
    );
    await _load();
  }

  Future<void> _delete(SavedOpeningScene scene) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete opening scene?'),
        content: Text('Remove “${scene.title}” from your library?'),
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
    if (ok != true || !mounted) return;
    await widget.openingSceneService.delete(scene.id);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.pickMode ? 'Choose opening scene' : 'Opening scenes',
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editScene(),
        icon: const Icon(Icons.add),
        label: const Text('New'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _scenes.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'No saved opening scenes yet.\n\n'
                      'Create one here, or generate one in Creation Center — '
                      'workshop scenes are saved to this library automatically.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
                  itemCount: _scenes.length,
                  itemBuilder: (context, index) {
                    final scene = _scenes[index];
                    final fromWorkshop = scene.workshopId != null;
                    return Card(
                      child: ListTile(
                        leading: Icon(
                          fromWorkshop
                              ? Icons.travel_explore_outlined
                              : Icons.auto_stories_outlined,
                        ),
                        title: Text(scene.title),
                        subtitle: Text(
                          [
                            scene.preview,
                            if (fromWorkshop) 'From Creation Center',
                          ].join('\n'),
                        ),
                        isThreeLine: scene.preview.length > 48,
                        onTap: widget.pickMode
                            ? () => Navigator.pop(context, scene)
                            : () => _editScene(existing: scene),
                        onLongPress:
                            widget.pickMode ? null : () => _delete(scene),
                        trailing: widget.pickMode
                            ? const Icon(Icons.chevron_right)
                            : const Icon(Icons.edit_outlined),
                      ),
                    );
                  },
                ),
    );
  }
}
