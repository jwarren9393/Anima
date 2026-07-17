import 'package:flutter/material.dart';

import '../models/character.dart';
import '../services/character_service.dart';

/// Form to create/edit a SillyTavern-style character card.
class CharacterEditScreen extends StatefulWidget {
  const CharacterEditScreen({
    super.key,
    required this.characterService,
    this.existing,
  });

  final CharacterService characterService;
  final Character? existing;

  @override
  State<CharacterEditScreen> createState() => _CharacterEditScreenState();
}

class _CharacterEditScreenState extends State<CharacterEditScreen> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _personality = TextEditingController();
  final _scenario = TextEditingController();
  final _firstMes = TextEditingController();
  final _alternateGreetings = TextEditingController();
  final _mesExample = TextEditingController();
  final _systemPrompt = TextEditingController();
  final _postHistory = TextEditingController();
  final _creatorNotes = TextEditingController();
  final _creator = TextEditingController();
  final _version = TextEditingController();
  final _tags = TextEditingController();
  bool _saving = false;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _name.text = existing.name;
      _description.text = existing.description;
      _personality.text = existing.personality;
      _scenario.text = existing.scenario;
      _firstMes.text = existing.firstMes;
      _alternateGreetings.text = existing.alternateGreetings.join('\n');
      _mesExample.text = existing.mesExample;
      _systemPrompt.text = existing.systemPrompt;
      _postHistory.text = existing.postHistoryInstructions;
      _creatorNotes.text = existing.creatorNotes;
      _creator.text = existing.creator;
      _version.text = existing.characterVersion;
      _tags.text = existing.tags.join(', ');
    }
  }

  List<String> _lines(String raw) => raw
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();

  List<String> _csv(String raw) => raw
      .split(RegExp(r'[,;]'))
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Give your character a name.')),
      );
      return;
    }

    setState(() => _saving = true);
    final existing = widget.existing;
    final character = Character(
      id: existing?.id ?? widget.characterService.newId(),
      name: name,
      description: _description.text.trim(),
      personality: _personality.text.trim(),
      scenario: _scenario.text.trim(),
      firstMes: _firstMes.text.trim(),
      alternateGreetings: _lines(_alternateGreetings.text),
      mesExample: _mesExample.text.trim(),
      systemPrompt: _systemPrompt.text.trim(),
      postHistoryInstructions: _postHistory.text.trim(),
      creatorNotes: _creatorNotes.text.trim(),
      creator: _creator.text.trim(),
      characterVersion: _version.text.trim(),
      tags: _csv(_tags.text),
      characterBook: existing?.characterBook,
      extensions: existing?.extensions ?? const {},
    );
    await widget.characterService.upsert(character);
    if (!mounted) return;
    Navigator.of(context).pop(character);
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _personality.dispose();
    _scenario.dispose();
    _firstMes.dispose();
    _alternateGreetings.dispose();
    _mesExample.dispose();
    _systemPrompt.dispose();
    _postHistory.dispose();
    _creatorNotes.dispose();
    _creator.dispose();
    _version.dispose();
    _tags.dispose();
    super.dispose();
  }

  Widget _field(
    TextEditingController controller, {
    required String label,
    String? hint,
    String? help,
    int minLines = 1,
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: .start,
        children: [
          TextField(
            controller: controller,
            minLines: minLines,
            maxLines: maxLines,
            textCapitalization:
                minLines == 1 ? .sentences : .sentences,
            decoration: InputDecoration(
              labelText: label,
              hintText: hint,
              alignLabelWithHint: minLines > 1,
              border: const OutlineInputBorder(),
            ),
          ),
          if (help != null) ...[
            const SizedBox(height: 6),
            Text(help, style: Theme.of(context).textTheme.bodySmall),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit character card' : 'New character card'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Fields match SillyTavern Character Cards (V2/V3). '
            'You can use {{char}} and {{user}} in the text.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          _field(_name, label: 'Name', hint: 'e.g. Luna'),
          _field(
            _description,
            label: 'Description',
            hint: 'Appearance, background, important facts…',
            help: 'Usually included in every prompt (ST Description).',
            minLines: 4,
            maxLines: 10,
          ),
          _field(
            _personality,
            label: 'Personality',
            hint: 'Short personality summary…',
            minLines: 2,
            maxLines: 6,
          ),
          _field(
            _scenario,
            label: 'Scenario',
            hint: 'Current situation / context…',
            minLines: 2,
            maxLines: 6,
          ),
          _field(
            _firstMes,
            label: 'First message',
            hint: 'Opening greeting…',
            help: 'Shown when a new chat starts.',
            minLines: 3,
            maxLines: 8,
          ),
          _field(
            _alternateGreetings,
            label: 'Alternate greetings',
            hint: 'One greeting per line…',
            help: 'Extra first-message swipes (ST alternate_greetings).',
            minLines: 3,
            maxLines: 8,
          ),
          _field(
            _mesExample,
            label: 'Example messages',
            hint: '<START>\n{{user}}: …\n{{char}}: …',
            help: 'ST mes_example — teaches tone and style.',
            minLines: 4,
            maxLines: 12,
          ),
          _field(
            _systemPrompt,
            label: 'System prompt (optional)',
            hint: 'Leave blank to use Anima’s default…',
            help: 'ST system_prompt. Supports {{original}}.',
            minLines: 2,
            maxLines: 6,
          ),
          _field(
            _postHistory,
            label: 'Post-history instructions (optional)',
            hint: 'Nudge after the chat history…',
            help: 'ST post_history_instructions.',
            minLines: 2,
            maxLines: 6,
          ),
          _field(
            _creatorNotes,
            label: 'Creator notes',
            hint: 'Notes for humans (not sent to the AI)…',
            minLines: 2,
            maxLines: 5,
          ),
          _field(_creator, label: 'Creator', hint: 'Your name or handle'),
          _field(_version, label: 'Character version', hint: 'e.g. 1.0'),
          _field(
            _tags,
            label: 'Tags',
            hint: 'comma, separated, tags',
          ),
          if (widget.existing?.characterBook != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'This card has an embedded lorebook. Anima keeps it for export; '
                'full lorebook playback comes in Phase 6.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(_isEditing ? 'Save character' : 'Create character'),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
