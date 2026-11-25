import '../models/character.dart';
import '../models/lorebook.dart';
import '../models/persona.dart';

/// One field (or entry) that changed between before/after AI review.
class AiFieldChange {
  const AiFieldChange({
    required this.label,
    required this.before,
    required this.after,
  });

  final String label;
  final String before;
  final String after;

  bool get isAddition => before.trim().isEmpty && after.trim().isNotEmpty;
  bool get isRemoval => before.trim().isNotEmpty && after.trim().isEmpty;
}

String _norm(String value) => value.trim();

bool _changed(String before, String after) => _norm(before) != _norm(after);

void _addIfChanged(
  List<AiFieldChange> out,
  String label,
  String before,
  String after,
) {
  if (!_changed(before, after)) return;
  out.add(AiFieldChange(label: label, before: before.trim(), after: after.trim()));
}

/// Compare editable character card text fields.
List<AiFieldChange> compareCharacterFields(Character before, Character after) {
  final out = <AiFieldChange>[];
  _addIfChanged(out, 'Name', before.name, after.name);
  _addIfChanged(out, 'Description', before.description, after.description);
  _addIfChanged(out, 'Personality', before.personality, after.personality);
  _addIfChanged(out, 'Scenario', before.scenario, after.scenario);
  _addIfChanged(out, 'First message', before.firstMes, after.firstMes);
  _addIfChanged(
    out,
    'Alternate greetings',
    before.alternateGreetings.join('\n'),
    after.alternateGreetings.join('\n'),
  );
  _addIfChanged(out, 'Example messages', before.mesExample, after.mesExample);
  _addIfChanged(out, 'System prompt', before.systemPrompt, after.systemPrompt);
  _addIfChanged(
    out,
    'Post-history instructions',
    before.postHistoryInstructions,
    after.postHistoryInstructions,
  );
  _addIfChanged(
    out,
    'Tags',
    before.tags.join(', '),
    after.tags.join(', '),
  );
  return out;
}

String _entryKey(LorebookEntry entry, int fallbackIndex) {
  if (entry.id != null) return 'id:${entry.id}';
  final label = entry.displayLabel.trim().toLowerCase();
  if (label.isNotEmpty && label != 'untitled entry') {
    return 'label:$label';
  }
  return 'idx:$fallbackIndex';
}

String _formatEntrySnapshot(LorebookEntry entry) {
  final lines = <String>[];
  if (entry.name.trim().isNotEmpty) {
    lines.add('Label: ${entry.name.trim()}');
  }
  if (entry.keys.isNotEmpty) {
    lines.add('Keywords: ${entry.keys.join(', ')}');
  }
  if (entry.secondaryKeys.isNotEmpty) {
    lines.add('Secondary: ${entry.secondaryKeys.join(', ')}');
  }
  if (entry.constant) lines.add('Always on');
  if (entry.content.trim().isNotEmpty) {
    lines.add(entry.content.trim());
  }
  return lines.isEmpty ? '(empty entry)' : lines.join('\n');
}

/// Compare lorebook metadata and entries for review UI.
List<AiFieldChange> compareLorebooks(Lorebook before, Lorebook after) {
  final out = <AiFieldChange>[];
  _addIfChanged(out, 'Book name', before.name, after.name);
  _addIfChanged(out, 'Book notes', before.description, after.description);

  final beforeByKey = <String, LorebookEntry>{};
  for (var i = 0; i < before.entries.length; i++) {
    beforeByKey[_entryKey(before.entries[i], i)] = before.entries[i];
  }
  final afterByKey = <String, LorebookEntry>{};
  for (var i = 0; i < after.entries.length; i++) {
    afterByKey[_entryKey(after.entries[i], i)] = after.entries[i];
  }

  final allKeys = {...beforeByKey.keys, ...afterByKey.keys}.toList()..sort();

  for (final key in allKeys) {
    final prev = beforeByKey[key];
    final next = afterByKey[key];
    if (prev != null && next != null) {
      final label = next.displayLabel;
      _addIfChanged(
        out,
        'Entry · $label',
        _formatEntrySnapshot(prev),
        _formatEntrySnapshot(next),
      );
    } else if (prev != null) {
      _addIfChanged(
        out,
        'Removed entry · ${prev.displayLabel}',
        _formatEntrySnapshot(prev),
        '',
      );
    } else if (next != null) {
      _addIfChanged(
        out,
        'New entry · ${next.displayLabel}',
        '',
        _formatEntrySnapshot(next),
      );
    }
  }

  return out;
}

/// Compare editable persona text fields.
List<AiFieldChange> comparePersonaFields(Persona before, Persona after) {
  final out = <AiFieldChange>[];
  _addIfChanged(out, 'Name', before.name, after.name);
  _addIfChanged(out, 'Identity and role', before.description, after.description);
  _addIfChanged(out, 'Appearance', before.appearance, after.appearance);
  _addIfChanged(out, 'Personality', before.personality, after.personality);
  _addIfChanged(out, 'Background', before.background, after.background);
  _addIfChanged(out, 'Goals', before.goals, after.goals);
  return out;
}

/// Compare editable fields on one lore entry.
List<AiFieldChange> compareLorebookEntry(
  LorebookEntry before,
  LorebookEntry after,
) {
  final out = <AiFieldChange>[];
  _addIfChanged(out, 'Label', before.name, after.name);
  _addIfChanged(
    out,
    'Keywords',
    before.keys.join(', '),
    after.keys.join(', '),
  );
  _addIfChanged(
    out,
    'Secondary keywords',
    before.secondaryKeys.join(', '),
    after.secondaryKeys.join(', '),
  );
  _addIfChanged(out, 'Lore content', before.content, after.content);
  return out;
}

Set<String> _selectedLabels(Iterable<AiFieldChange> selected) =>
    selected.map((change) => change.label).toSet();

/// Apply only [selected] field changes from [after] onto [before].
Character mergeCharacterChanges(
  Character before,
  Character after,
  List<AiFieldChange> selected,
) {
  final pick = _selectedLabels(selected);
  if (pick.isEmpty) return before;

  String field(String label, String next, String prev) =>
      pick.contains(label) ? next : prev;

  return before.copyWith(
    name: field('Name', after.name, before.name),
    description: field('Description', after.description, before.description),
    personality: field('Personality', after.personality, before.personality),
    scenario: field('Scenario', after.scenario, before.scenario),
    firstMes: field('First message', after.firstMes, before.firstMes),
    alternateGreetings: pick.contains('Alternate greetings')
        ? after.alternateGreetings
        : before.alternateGreetings,
    mesExample: field('Example messages', after.mesExample, before.mesExample),
    systemPrompt: field('System prompt', after.systemPrompt, before.systemPrompt),
    postHistoryInstructions: field(
      'Post-history instructions',
      after.postHistoryInstructions,
      before.postHistoryInstructions,
    ),
    tags: pick.contains('Tags') ? after.tags : before.tags,
  );
}

/// Apply only [selected] field changes from [after] onto [before].
Persona mergePersonaChanges(
  Persona before,
  Persona after,
  List<AiFieldChange> selected,
) {
  final pick = _selectedLabels(selected);
  if (pick.isEmpty) return before;

  String field(String label, String next, String prev) =>
      pick.contains(label) ? next : prev;

  return before.copyWith(
    name: field('Name', after.name, before.name),
    description: field(
      'Identity and role',
      after.description,
      before.description,
    ),
    appearance: field('Appearance', after.appearance, before.appearance),
    personality: field('Personality', after.personality, before.personality),
    background: field('Background', after.background, before.background),
    goals: field('Goals', after.goals, before.goals),
  );
}

/// Apply only [selected] field changes from [after] onto [before].
LorebookEntry mergeLorebookEntryChanges(
  LorebookEntry before,
  LorebookEntry after,
  List<AiFieldChange> selected,
) {
  final pick = _selectedLabels(selected);
  if (pick.isEmpty) return before;

  String field(String label, String next, String prev) =>
      pick.contains(label) ? next : prev;

  return before.copyWith(
    name: field('Label', after.name, before.name),
    keys: pick.contains('Keywords') ? after.keys : before.keys,
    secondaryKeys:
        pick.contains('Secondary keywords') ? after.secondaryKeys : before.secondaryKeys,
    content: field('Lore content', after.content, before.content),
  );
}

/// Apply only [selected] lorebook changes from [after] onto [before].
Lorebook mergeLorebookChanges(
  Lorebook before,
  Lorebook after,
  List<AiFieldChange> selected,
) {
  final pick = _selectedLabels(selected);
  if (pick.isEmpty) return before;

  var name = before.name;
  var description = before.description;
  if (pick.contains('Book name')) name = after.name;
  if (pick.contains('Book notes')) description = after.description;

  final beforeByKey = <String, LorebookEntry>{};
  for (var i = 0; i < before.entries.length; i++) {
    beforeByKey[_entryKey(before.entries[i], i)] = before.entries[i];
  }
  final afterByKey = <String, LorebookEntry>{};
  for (var i = 0; i < after.entries.length; i++) {
    afterByKey[_entryKey(after.entries[i], i)] = after.entries[i];
  }

  final entries = <LorebookEntry>[];
  for (var i = 0; i < before.entries.length; i++) {
    final prev = before.entries[i];
    final key = _entryKey(prev, i);
    final next = afterByKey[key];
    if (next != null) {
      final label = 'Entry · ${next.displayLabel}';
      entries.add(pick.contains(label) ? next : prev);
      continue;
    }
    final removedLabel = 'Removed entry · ${prev.displayLabel}';
    if (!pick.contains(removedLabel)) {
      entries.add(prev);
    }
  }

  for (var i = 0; i < after.entries.length; i++) {
    final next = after.entries[i];
    final key = _entryKey(next, i);
    if (beforeByKey.containsKey(key)) continue;
    final label = 'New entry · ${next.displayLabel}';
    if (pick.contains(label)) {
      entries.add(next);
    }
  }

  return before.copyWith(
    name: name,
    description: description,
    entries: entries,
  );
}
