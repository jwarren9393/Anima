import 'package:flutter/material.dart';

import '../models/character.dart';
import '../services/character_service.dart';

/// Form to create a new character or edit an existing one.
class CharacterEditScreen extends StatefulWidget {
  const CharacterEditScreen({
    super.key,
    required this.characterService,
    this.existing,
  });

  final CharacterService characterService;

  /// Null when creating; set when editing.
  final Character? existing;

  @override
  State<CharacterEditScreen> createState() => _CharacterEditScreenState();
}

class _CharacterEditScreenState extends State<CharacterEditScreen> {
  final _nameController = TextEditingController();
  final _promptController = TextEditingController();
  bool _saving = false;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _nameController.text = existing.name;
      _promptController.text = existing.systemPrompt;
    }
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final prompt = _promptController.text.trim();

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Give your character a name.')),
      );
      return;
    }
    if (prompt.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Write a short personality / instructions prompt.'),
        ),
      );
      return;
    }

    setState(() => _saving = true);
    final character = Character(
      id: widget.existing?.id ?? widget.characterService.newId(),
      name: name,
      systemPrompt: prompt,
    );
    await widget.characterService.upsert(character);
    if (!mounted) return;
    Navigator.of(context).pop(character);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _promptController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit character' : 'New character'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextField(
            controller: _nameController,
            textCapitalization: .words,
            decoration: const InputDecoration(
              labelText: 'Name',
              hintText: 'e.g. Luna',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _promptController,
            minLines: 6,
            maxLines: 12,
            decoration: const InputDecoration(
              labelText: 'Personality / instructions',
              hintText:
                  'Tell the AI who this character is and how they should talk…',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'This text is sent to NanoGPT as hidden instructions (a “system” message). '
            'The character will try to follow it during the chat.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(_isEditing ? 'Save changes' : 'Create character'),
          ),
        ],
      ),
    );
  }
}
