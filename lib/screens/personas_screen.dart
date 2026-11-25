import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/persona.dart';
import '../services/nanogpt_service.dart';
import '../services/persona_card_codec.dart';
import '../services/persona_service.dart';
import '../services/persona_token_service.dart';
import '../services/settings_service.dart';
import '../widgets/anima_avatar.dart';
import '../widgets/character_token_badge.dart';
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
  static const _tokenService = PersonaTokenService();
  static const _codec = PersonaCardCodec();

  List<Persona> _personas = [];
  String? _activeId;
  bool _loading = true;
  bool _busy = false;

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
      _activeId = active ?? (personas.isEmpty ? null : personas.first.id);
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
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Default persona: ${persona.name}')));
  }

  Future<void> _duplicate(Persona persona) async {
    final copy = await widget.personaService.duplicate(persona);
    await widget.personaService.upsert(copy);
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Duplicated “${persona.name}” as “${copy.name}”')),
    );
  }

  Future<void> _delete(Persona persona) async {
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

  /// Import one or more persona cards from a JSON file.
  ///
  /// Works with this app's own persona JSON, a persona an AI collaborator
  /// produced (`description`, `identity`, `backstory`, …), a list of personas,
  /// or a whole `.anima-backup` file.
  Future<void> _import() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      Uint8List? bytes = file.bytes;
      if (bytes == null && file.path != null) {
        bytes = await File(file.path!).readAsBytes();
      }
      if (bytes == null) {
        throw const FormatException('Could not read the selected file.');
      }

      final parsed = _codec.parseBytes(
        bytes,
        newId: widget.personaService.newId,
      );
      if (!mounted) return;
      final approved = await _confirmImport(parsed);
      if (approved != true) return;

      for (final persona in parsed) {
        await widget.personaService.upsert(persona);
      }
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            parsed.length == 1
                ? 'Imported “${parsed.first.name}”'
                : 'Imported ${parsed.length} personas',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      final message = error is FormatException ? error.message : '$error';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Import failed: $message')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Shows what was found before anything is saved.
  Future<bool?> _confirmImport(List<Persona> personas) {
    final title = personas.length == 1
        ? 'Import “${personas.first.name}”'
        : 'Import ${personas.length} personas';
    return showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: personas.length,
                itemBuilder: (context, index) {
                  final persona = personas[index];
                  final text = persona.promptText.replaceAll('\n', ' ');
                  return ListTile(
                    dense: true,
                    leading: AnimaAvatar(
                      fileName: persona.avatarFileName,
                      label: persona.name,
                      radius: 18,
                    ),
                    title: Text(persona.name),
                    subtitle: Text(
                      text.isEmpty ? 'No details' : text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: FilledButton.icon(
                onPressed: () => Navigator.pop(context, true),
                icon: const Icon(Icons.download_done),
                label: Text(
                  personas.length == 1
                      ? 'Import'
                      : 'Import all ${personas.length}',
                ),
              ),
            ),
          ],
        ),
      ),
    );
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
        actions: [
          IconButton(
            onPressed: _loading || _busy ? null : _import,
            tooltip: 'Import persona JSON',
            icon: const Icon(Icons.upload_file),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loading ? null : _create,
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('New'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _personas.isEmpty && !widget.pickForChat
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'No personas yet.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Create one to save your name, look, and backstory '
                          'for roleplay — or start chats as plain User.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                )
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
                    itemCount: (widget.pickForChat ? 1 : 0) + _personas.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      if (widget.pickForChat && index == 0) {
                        final anonymous = Persona.anonymous();
                        final selected = anonymous.id == highlightId;
                        return ListTile(
                          selected: selected,
                          selectedTileColor: colorScheme.primaryContainer
                              .withValues(alpha: 0.45),
                          leading: AnimaAvatar(
                            fileName: null,
                            label: anonymous.name,
                            radius: 22,
                          ),
                          title: const Text('Plain User'),
                          subtitle: const Text(
                            'No saved persona details — just {{user}} as User',
                          ),
                          trailing: selected ? const Icon(Icons.check) : null,
                          onTap: () =>
                              Navigator.of(context).pop(anonymous),
                        );
                      }
                      final personaIndex =
                          widget.pickForChat ? index - 1 : index;
                      final persona = _personas[personaIndex];
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
                        title: Row(
                          children: [
                            Expanded(child: Text(persona.name)),
                            if (!persona.isAnonymous) ...[
                              const SizedBox(width: 6),
                              CharacterTokenBadge(
                                tokens: _tokenService.badgeTokens(persona),
                                tooltip: personaTokenTooltip(
                                  _tokenService.breakdown(persona),
                                ),
                              ),
                            ],
                          ],
                        ),
                        subtitle: Text(
                          [
                            if (isDefault && !widget.pickForChat)
                              'Default for new chats',
                            if (persona.promptText.isEmpty)
                              'No persona details'
                            else
                              persona.description.trim().isNotEmpty
                                  ? persona.description.trim()
                                  : persona.promptText.replaceAll('\n', ' '),
                          ].join(' · '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: widget.pickForChat
                            ? (selected ? const Icon(Icons.check) : null)
                            : PopupMenuButton<String>(
                                onSelected: (value) {
                                  if (value == 'edit') _edit(persona);
                                  if (value == 'duplicate') _duplicate(persona);
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
                                  const PopupMenuItem(
                                    value: 'duplicate',
                                    child: Text('Duplicate'),
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
