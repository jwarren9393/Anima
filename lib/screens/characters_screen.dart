import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/character.dart';
import '../services/avatar_service.dart';
import '../services/character_card_codec.dart';
import '../services/character_service.dart';
import '../services/nanogpt_service.dart';
import '../services/settings_service.dart';
import '../widgets/anima_avatar.dart';
import 'character_edit_screen.dart';

/// List of saved characters with SillyTavern card import/export.
class CharactersScreen extends StatefulWidget {
  const CharactersScreen({
    super.key,
    required this.characterService,
    required this.settingsService,
    required this.nanoGptService,
  });

  final CharacterService characterService;
  final SettingsService settingsService;
  final NanoGptService nanoGptService;

  @override
  State<CharactersScreen> createState() => _CharactersScreenState();
}

class _CharactersScreenState extends State<CharactersScreen> {
  final _codec = CharacterCardCodec();
  final _avatarService = AvatarService();
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
    final base = text.trim().isEmpty ? 'No description yet' : text.trim();
    final lore = character.enabledLoreEntryCount;
    if (lore <= 0) return base;
    return '$base · Lorebook ($lore)';
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
          settingsService: widget.settingsService,
          nanoGptService: widget.nanoGptService,
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
          settingsService: widget.settingsService,
          nanoGptService: widget.nanoGptService,
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

      var character = imported;
      // SillyTavern PNG cards *are* the avatar image — save a copy.
      if (_codec.looksLikePng(bytes)) {
        final avatarName = await _avatarService.saveBytes(
          stem: imported.id,
          bytes: bytes,
          extension: '.png',
        );
        character = imported.copyWith(avatarFileName: avatarName);
      }

      await widget.characterService.upsert(character);
      await widget.settingsService.saveSelectedCharacterId(character.id);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Imported “${character.name}”')),
      );
      Navigator.of(context).pop(character);
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
              ListTile(
                title: const Text('Export as PNG card'),
                subtitle: const Text('Embedded chara chunk (ST import)'),
                onTap: () => Navigator.pop(context, 'png'),
              ),
              ListTile(
                title: const Text('Export as PNG card (V3)'),
                subtitle: const Text('Includes chara + ccv3 chunks'),
                onTap: () => Navigator.pop(context, 'png_v3'),
              ),
            ],
          ),
        ),
      );
      if (format == null) return;

      final dir = await getTemporaryDirectory();
      final safeName = character.name
          .replaceAll(RegExp(r'[^\w\-]+'), '_')
          .replaceAll(RegExp(r'_+'), '_');
      final base = safeName.isEmpty ? 'character' : safeName;

      if (format == 'png' || format == 'png_v3') {
        Uint8List? avatarPng;
        final avatarPath =
            await _avatarService.resolvePath(character.avatarFileName);
        if (avatarPath != null &&
            avatarPath.toLowerCase().endsWith('.png')) {
          avatarPng = await File(avatarPath).readAsBytes();
        }
        final bytes = _codec.toCardPng(
          character,
          asV3: format == 'png_v3',
          avatarPngBytes: avatarPng,
        );
        final file = File('${dir.path}/${base}_card.png');
        await file.writeAsBytes(bytes);
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(file.path, mimeType: 'image/png')],
            subject: '${character.name} character card',
            text: 'SillyTavern-compatible PNG character card',
          ),
        );
      } else {
        final json = format == 'v3'
            ? _codec.toCardV3Json(character)
            : _codec.toCardV2Json(character);
        final file = File('${dir.path}/${base}_card_$format.json');
        await file.writeAsString(json);
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(file.path, mimeType: 'application/json')],
            subject: '${character.name} character card',
            text: 'SillyTavern-compatible character card ($format)',
          ),
        );
      }
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

                      return ListTile(
                        selected: selected,
                        selectedTileColor:
                            colorScheme.primaryContainer.withValues(alpha: 0.45),
                        leading: AnimaAvatar(
                          fileName: character.avatarFileName,
                          label: character.name,
                          radius: 22,
                          avatarService: _avatarService,
                        ),
                        title: Text(character.name),
                        subtitle: Text(
                          _subtitle(character),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
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
