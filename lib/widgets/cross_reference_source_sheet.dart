import 'package:flutter/material.dart';

import '../models/character.dart';
import '../models/persona.dart';

/// A picked cross-reference source card, ready for AI prompt building.
class CrossReferenceSource {
  const CrossReferenceSource({
    required this.label,
    required this.block,
    this.notes = '',
  });

  /// Human-readable source tag, e.g. `Character: Mira` or `Persona: Ash`.
  final String label;

  /// Formatted field block of the source card for AI prompts.
  final String block;

  /// Optional notes on how the two cards should connect.
  final String notes;
}

/// Pick another character or persona to base the current card on.
///
/// Cross-reference: the AI drafts the card being edited using the picked card
/// as shared-world reference material (facts re-pointed at the target).
Future<CrossReferenceSource?> showCrossReferenceSourceSheet({
  required BuildContext context,
  required List<Character> characters,
  required List<Persona> personas,
  String excludeId = '',
  String targetLabel = 'card',
}) {
  return showModalBottomSheet<CrossReferenceSource>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => _CrossReferenceSourceSheet(
      characters: characters,
      personas: personas,
      excludeId: excludeId,
      targetLabel: targetLabel,
    ),
  );
}

class _CrossReferenceSourceSheet extends StatefulWidget {
  const _CrossReferenceSourceSheet({
    required this.characters,
    required this.personas,
    required this.excludeId,
    required this.targetLabel,
  });

  final List<Character> characters;
  final List<Persona> personas;
  final String excludeId;
  final String targetLabel;

  @override
  State<_CrossReferenceSourceSheet> createState() =>
      _CrossReferenceSourceSheetState();
}

class _CrossReferenceSourceSheetState
    extends State<_CrossReferenceSourceSheet> {
  late String _kind; // 'character' | 'persona'
  String? _selectedId;
  final _notes = TextEditingController();

  @override
  void initState() {
    super.initState();
    _kind = _visibleCharacters.isEmpty && _visiblePersonas.isNotEmpty
        ? 'persona'
        : 'character';
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  List<Character> get _visibleCharacters => widget.characters
      .where((c) => c.id != widget.excludeId && c.name.trim().isNotEmpty)
      .toList();

  List<Persona> get _visiblePersonas => widget.personas
      .where((p) => p.id != widget.excludeId && p.name.trim().isNotEmpty)
      .toList();

  String? get _selectedName {
    if (_selectedId == null) return null;
    if (_kind == 'persona') {
      for (final persona in _visiblePersonas) {
        if (persona.id == _selectedId) return persona.name;
      }
    } else {
      for (final character in _visibleCharacters) {
        if (character.id == _selectedId) return character.name;
      }
    }
    return null;
  }

  CrossReferenceSource? _buildResult() {
    if (_selectedId == null) return null;
    if (_kind == 'persona') {
      for (final persona in _visiblePersonas) {
        if (persona.id == _selectedId) {
          return CrossReferenceSource(
            label: 'Persona: ${persona.name}',
            block: _personaSourceBlock(persona),
            notes: _notes.text.trim(),
          );
        }
      }
      return null;
    }
    for (final character in _visibleCharacters) {
      if (character.id == _selectedId) {
        return CrossReferenceSource(
          label: 'Character: ${character.name}',
          block: _characterSourceBlock(character),
          notes: _notes.text.trim(),
        );
      }
    }
    return null;
  }

  String _characterSourceBlock(Character character) {
    final lines = <String>[];
    void add(String label, String value) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) return;
      lines.add('$label:\n$trimmed');
    }

    add('Name', character.name);
    add('Description', character.description);
    add('Personality', character.personality);
    add('Scenario', character.scenario);
    add('First message', character.firstMes);
    add('Example messages', character.mesExample);
    if (character.tags.isNotEmpty) {
      lines.add('Tags: ${character.tags.join(', ')}');
    }
    return lines.isEmpty ? '' : lines.join('\n\n');
  }

  String _personaSourceBlock(Persona persona) {
    final lines = <String>[];
    void add(String label, String value) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) return;
      lines.add('$label:\n$trimmed');
    }

    add('Name', persona.name);
    add('Identity and role', persona.description);
    add('Appearance', persona.appearance);
    add('Personality', persona.personality);
    add('Background', persona.background);
    add('Goals and motivations', persona.goals);
    return lines.isEmpty ? '' : lines.join('\n\n');
  }

  String _snippet(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return 'No details yet';
    final line = trimmed.split('\n').first.trim();
    return line.length <= 80 ? line : '${line.substring(0, 77).trimRight()}…';
  }

  Widget _characterTile(Character character) {
    final selected = _selectedId == character.id;
    return ListTile(
      leading: CircleAvatar(
        child: Text(
          character.name.trim().isEmpty
              ? '?'
              : character.name.trim()[0].toUpperCase(),
        ),
      ),
      title: Text(character.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        _snippet(
          character.description.trim().isNotEmpty
              ? character.description
              : character.personality,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: selected ? const Icon(Icons.check_circle) : null,
      onTap: () => setState(() => _selectedId = character.id),
    );
  }

  Widget _personaTile(Persona persona) {
    final selected = _selectedId == persona.id;
    return ListTile(
      leading: CircleAvatar(
        child: Text(
          persona.name.trim().isEmpty
              ? '?'
              : persona.name.trim()[0].toUpperCase(),
        ),
      ),
      title: Text(persona.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        _snippet(persona.description),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: selected ? const Icon(Icons.check_circle) : null,
      onTap: () => setState(() => _selectedId = persona.id),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final characters = _visibleCharacters;
    final personas = _visiblePersonas;
    final count = _kind == 'persona' ? personas.length : characters.length;
    final selectedName = _selectedName;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.8,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Base on another card…',
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                child: Text(
                  'Pick a card to borrow shared-world facts from. The AI drafts '
                  'this ${widget.targetLabel} using it as reference — you '
                  'review every change before saving.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SegmentedButton<String>(
                  segments: [
                    ButtonSegment(
                      value: 'character',
                      label: Text('Characters (${characters.length})'),
                      icon: const Icon(Icons.face_outlined),
                    ),
                    ButtonSegment(
                      value: 'persona',
                      label: Text('Personas (${personas.length})'),
                      icon: const Icon(Icons.person_outline),
                    ),
                  ],
                  selected: {_kind},
                  onSelectionChanged: (selection) => setState(() {
                    _kind = selection.first;
                    _selectedId = null;
                  }),
                ),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: count == 0
                    ? Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _kind == 'persona'
                              ? 'No personas saved yet.'
                              : 'No other characters saved yet.',
                          style: theme.textTheme.bodySmall,
                          textAlign: TextAlign.center,
                        ),
                      )
                    : ListView(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        children: [
                          if (_kind == 'persona')
                            for (final persona in personas)
                              _personaTile(persona)
                          else
                            for (final character in characters)
                              _characterTile(character),
                        ],
                      ),
              ),
              if (selectedName != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: TextField(
                    controller: _notes,
                    minLines: 1,
                    maxLines: 3,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'How should they connect? (optional)',
                      hintText: "e.g. make her Mira's estranged sister",
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: selectedName == null
                          ? null
                          : () => Navigator.pop(context, _buildResult()),
                      child: Text(
                        selectedName == null
                            ? 'Pick a card'
                            : 'Base on $selectedName',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}