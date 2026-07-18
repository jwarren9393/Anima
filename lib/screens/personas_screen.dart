import 'package:flutter/material.dart';

import '../models/persona.dart';
import '../services/nanogpt_service.dart';
import '../services/persona_service.dart';
import '../services/settings_service.dart';
import '../widgets/anima_avatar.dart';
import 'persona_edit_screen.dart';

/// List / create / edit personas and pick the app default for new chats.
class PersonasScreen extends StatefulWidget {
  const PersonasScreen({
    super.key,
    required this.personaService,
    required this.settingsService,
    required this.nanoGptService,
    this.pickForChat = false,
    this.selectedPersonaId,
  });

  final PersonaService personaService;
  final SettingsService settingsService;
  final NanoGptService nanoGptService;

  /// When true, tapping a row returns that persona (for chat switching).
  final bool pickForChat;

  final String? selectedPersonaId;

  @override
  State<PersonasScreen> createState() => _PersonasScreenState();
}

class _PersonasScreenState extends State<PersonasScreen> {
  List<Persona> _personas = [];
  String? _activeId;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final personas = await widget.personaService.loadPersonas();
    final active = await widget.personaService.getActivePersonaId();
    if (!mounted) return;
    setState(() {
      _personas = personas;
      _activeId = active ?? personas.first.id;
      _loading = false;
    });
  }

  Future<void> _create() async {
    final created = await Navigator.of(context).push<Persona>(
      MaterialPageRoute(
        builder: (_) => PersonaEditScreen(
          personaService: widget.personaService,
          settingsService: widget.settingsService,
          nanoGptService: widget.nanoGptService,
        ),
      ),
    );
    if (created == null) return;
    await _load();
  }

  Future<void> _edit(Persona persona) async {
    await Navigator.of(context).push<Persona>(
      MaterialPageRoute(
        builder: (_) => PersonaEditScreen(
          personaService: widget.personaService,
          settingsService: widget.settingsService,
          nanoGptService: widget.nanoGptService,
          existing: persona,
        ),
      ),
    );
    await _load();
  }

  Future<void> _setDefault(Persona persona) async {
    await widget.personaService.setActivePersonaId(persona.id);
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Default persona: ${persona.name}')),
    );
  }

  Future<void> _delete(Persona persona) async {
    if (_personas.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Keep at least one persona.')),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete persona?'),
        content: Text('Remove “${persona.name}” from this device?'),
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
    await widget.personaService.delete(persona.id);
    await _load();
  }

  void _onTap(Persona persona) {
    if (widget.pickForChat) {
      Navigator.of(context).pop(persona);
      return;
    }
    _edit(persona);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final highlightId = widget.pickForChat
        ? (widget.selectedPersonaId ?? _activeId)
        : _activeId;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.pickForChat ? 'Choose persona' : 'Personas'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loading ? null : _create,
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('New'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text(
                    widget.pickForChat
                        ? 'This chat will use the persona you pick. '
                            'New messages will use that name and description.'
                        : 'Create multiple versions of yourself. The default '
                            'is used for new chats; you can switch per chat.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
                    itemCount: _personas.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final persona = _personas[index];
                      final selected = persona.id == highlightId;
                      final isDefault = persona.id == _activeId;
                      return ListTile(
                        selected: selected,
                        selectedTileColor: colorScheme.primaryContainer
                            .withValues(alpha: 0.45),
                        leading: AnimaAvatar(
                          fileName: persona.avatarFileName,
                          label: persona.name,
                          radius: 22,
                        ),
                        title: Text(persona.name),
                        subtitle: Text(
                          [
                            if (isDefault && !widget.pickForChat)
                              'Default for new chats',
                            if (persona.description.trim().isEmpty)
                              'No description'
                            else
                              persona.description.trim(),
                          ].join(' · '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: widget.pickForChat
                            ? (selected
                                ? const Icon(Icons.check)
                                : null)
                            : PopupMenuButton<String>(
                                onSelected: (value) {
                                  if (value == 'edit') _edit(persona);
                                  if (value == 'default') {
                                    _setDefault(persona);
                                  }
                                  if (value == 'delete') _delete(persona);
                                },
                                itemBuilder: (context) => [
                                  const PopupMenuItem(
                                    value: 'edit',
                                    child: Text('Edit'),
                                  ),
                                  if (!isDefault)
                                    const PopupMenuItem(
                                      value: 'default',
                                      child: Text('Set as default'),
                                    ),
                                  const PopupMenuItem(
                                    value: 'delete',
                                    child: Text('Delete'),
                                  ),
                                ],
                              ),
                        onTap: () => _onTap(persona),
                        onLongPress: widget.pickForChat
                            ? null
                            : () => _setDefault(persona),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}
