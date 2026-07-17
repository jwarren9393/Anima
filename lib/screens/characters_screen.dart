import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/character.dart';
import '../services/character_card_codec.dart';
import '../services/character_service.dart';
import '../services/settings_service.dart';
import 'character_edit_screen.dart';

/// List of saved characters with SillyTavern card import/export.
class CharactersScreen extends StatefulWidget {
  const CharactersScreen({
    super.key,
    required this.characterService,
    required this.settingsService,
  });

  final CharacterService characterService;
  final SettingsService settingsService;

  @override
  State<CharactersScreen> createState() => _CharactersScreenState();
}

class _CharactersScreenState extends State<CharactersScreen> {
  final _codec = CharacterCardCodec();
  List<Character> _characters = [];
  String? _selectedId;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final characters = await widget.characterService.loadCharacters();
    var selectedId = await widget.settingsService.getSelectedCharacterId();
    final ids = characters.map((c) => c.id).toSet();
    if (selectedId == null || !ids.contains(selectedId)) {
      selectedId = characters.first.id;
      await widget.settingsService.saveSelectedCharacterId(selectedId);
    }
    if (!mounted) return;
    setState(() {
      _characters = characters;
      _selectedId = selectedId;
      _loading = false;
    });
  }

  String _subtitle(Character character) {
    final text = character.description.trim().isNotEmpty
        ? character.description
        : character.personality.trim().isNotEmpty
            ? character.personality
            : character.creatorNotes;
    return text.trim().isEmpty ? 'No description yet' : text.trim();
  }

  Future<void> _select(Character character) async {
    await widget.settingsService.saveSelectedCharacterId(character.id);
    if (!mounted) return;
    setState(() => _selectedId = character.id);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Now chatting with ${character.name}')),
    );
    Navigator.of(context).pop(character);
  }

  Future<void> _create() async {
    final created = await Navigator.of(context).push<Character>(
      MaterialPageRoute(
        builder: (_) => CharacterEditScreen(
          characterService: widget.characterService,
        ),
      ),
    );
    if (created == null) return;
    await widget.settingsService.saveSelectedCharacterId(created.id);
    await _load();
    if (!mounted) return;
    Navigator.of(context).pop(created);
  }

  Future<void> _edit(Character character) async {
    final updated = await Navigator.of(context).push<Character>(
      MaterialPageRoute(
        builder: (_) => CharacterEditScreen(
          characterService: widget.characterService,
          existing: character,
        ),
      ),
    );
    if (updated == null) return;
    await _load();
  }

  Future<void> _delete(Character character) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete character?'),
        content: Text(
          'Remove “${character.name}” from this device? '
          'This cannot be undone.',
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
    final remaining = await widget.characterService.delete(character.id);
    if (_selectedId == character.id) {
      await widget.settingsService.saveSelectedCharacterId(remaining.first.id);
    }
    await _load();
  }

  Future<void> _importCard() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: .custom,
        allowedExtensions: const ['json', 'png'],
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

      final imported = _codec.parseBytes(
        bytes,
        preferredId: widget.characterService.newId(),
      );
      if (imported.name.trim().isEmpty) {
        throw const FormatException('That card has no character name.');
      }

      await widget.characterService.upsert(imported);
      await widget.settingsService.saveSelectedCharacterId(imported.id);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Imported “${imported.name}”')),
      );
      Navigator.of(context).pop(imported);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Import failed: $error')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportCard(Character character) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final format = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: Column(
            mainAxisSize: .min,
            children: [
              ListTile(
                title: const Text('Export as Card V2 JSON'),
                subtitle: const Text('Best compatibility with SillyTavern'),
                onTap: () => Navigator.pop(context, 'v2'),
              ),
              ListTile(
                title: const Text('Export as Card V3 JSON'),
                subtitle: const Text('Newer SillyTavern format'),
                onTap: () => Navigator.pop(context, 'v3'),
              ),
            ],
          ),
        ),
      );
      if (format == null) return;

      final json = format == 'v3'
          ? _codec.toCardV3Json(character)
          : _codec.toCardV2Json(character);

      final dir = await getTemporaryDirectory();
      final safeName = character.name
          .replaceAll(RegExp(r'[^\w\-]+'), '_')
          .replaceAll(RegExp(r'_+'), '_');
      final file = File(
        '${dir.path}/${safeName.isEmpty ? 'character' : safeName}_card_$format.json',
      );
      await file.writeAsString(json);

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'application/json')],
          subject: '${character.name} character card',
          text: 'SillyTavern-compatible character card ($format)',
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: $error')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Characters'),
        actions: [
          IconButton(
            tooltip: 'Import card',
            onPressed: _loading || _busy ? null : _importCard,
            icon: const Icon(Icons.file_download_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loading || _busy ? null : _create,
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
                    'Import SillyTavern cards (.json or .png). Export stays compatible with Card V2/V3.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
                    itemCount: _characters.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final character = _characters[index];
                      final selected = character.id == _selectedId;
                      final initial = character.name.isEmpty
                          ? '?'
                          : character.name.substring(0, 1).toUpperCase();

                      return ListTile(
                        selected: selected,
                        selectedTileColor:
                            colorScheme.primaryContainer.withValues(alpha: 0.45),
                        leading: CircleAvatar(child: Text(initial)),
                        title: Text(character.name),
                        subtitle: Text(
                          _subtitle(character),
                          maxLines: 2,
                          overflow: .ellipsis,
                        ),
                        trailing: PopupMenuButton<String>(
                          onSelected: (value) {
                            if (value == 'edit') _edit(character);
                            if (value == 'export') _exportCard(character);
                            if (value == 'delete') _delete(character);
                          },
                          itemBuilder: (context) => const [
                            PopupMenuItem(value: 'edit', child: Text('Edit')),
                            PopupMenuItem(
                              value: 'export',
                              child: Text('Export card'),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: Text('Delete'),
                            ),
                          ],
                        ),
                        onTap: () => _select(character),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}
