import 'package:flutter/material.dart';

import '../models/world_workshop.dart';
import '../services/nanogpt_service.dart';
import '../services/settings_service.dart';
import '../services/world_info_service.dart';
import '../services/world_workshop_service.dart';
import 'world_workshop_chat_screen.dart';

/// Settings → Creation Center: list of world-building workshop chats.
class WorldWorkshopListScreen extends StatefulWidget {
  const WorldWorkshopListScreen({
    super.key,
    required this.workshopService,
    required this.worldInfoService,
    required this.settingsService,
    required this.nanoGptService,
  });

  final WorldWorkshopService workshopService;
  final WorldInfoService worldInfoService;
  final SettingsService settingsService;
  final NanoGptService nanoGptService;

  @override
  State<WorldWorkshopListScreen> createState() =>
      _WorldWorkshopListScreenState();
}

class _WorldWorkshopListScreenState extends State<WorldWorkshopListScreen> {
  List<WorldWorkshop> _workshops = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final workshops = await widget.workshopService.loadWorkshops();
    if (!mounted) return;
    setState(() {
      _workshops = workshops;
      _loading = false;
    });
  }

  Future<void> _open(WorldWorkshop workshop) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WorldWorkshopChatScreen(
          workshop: workshop,
          workshopService: widget.workshopService,
          worldInfoService: widget.worldInfoService,
          settingsService: widget.settingsService,
          nanoGptService: widget.nanoGptService,
        ),
      ),
    );
    await _load();
  }

  Future<void> _create() async {
    final workshop = await widget.workshopService.upsert(WorldWorkshop.empty());
    if (!mounted) return;
    await _open(workshop);
  }

  Future<void> _delete(WorldWorkshop workshop) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete workshop?'),
        content: Text(
          'Remove “${workshop.title}”? '
          'Any lorebook you already saved to World Info stays there.',
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
    await widget.workshopService.delete(workshop.id);
    await _load();
  }

  String _subtitle(WorldWorkshop workshop) {
    final count = workshop.messages.length;
    final exported = workshop.exportedLorebookId != null
        ? ' · Saved to World Info'
        : '';
    if (count == 0) return 'No messages yet$exported';
    return '$count messages$exported';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Creation Center')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.add),
        label: const Text('New workshop'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _workshops.isEmpty
              ? ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    Text(
                      'Build a world by chatting with the AI. '
                      'When you’re ready, tap Create lorebook — it becomes a '
                      'global lorebook under World Info (same as one you made '
                      'by hand).',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'One workshop chat = one lorebook.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                )
              : ListView.builder(
                  itemCount: _workshops.length,
                  itemBuilder: (context, index) {
                    final workshop = _workshops[index];
                    return ListTile(
                      leading: const Icon(Icons.travel_explore),
                      title: Text(workshop.title),
                      subtitle: Text(_subtitle(workshop)),
                      trailing: PopupMenuButton<String>(
                        onSelected: (value) {
                          if (value == 'delete') _delete(workshop);
                        },
                        itemBuilder: (context) => const [
                          PopupMenuItem(
                            value: 'delete',
                            child: Text('Delete'),
                          ),
                        ],
                      ),
                      onTap: () => _open(workshop),
                    );
                  },
                ),
    );
  }
}
