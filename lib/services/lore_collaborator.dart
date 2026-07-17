import '../models/lorebook.dart';
import 'settings_service.dart';

/// Creative World Info entry fields the AI wand can expand.
enum LoreCollaboratorField {
  name,
  keys,
  secondaryKeys,
  content,
}

/// Snapshot of the entry + book being edited — sent as wand context.
class LoreEntryDraftContext {
  const LoreEntryDraftContext({
    this.bookName = '',
    this.bookDescription = '',
    this.characterName = '',
    this.name = '',
    this.keys = '',
    this.secondaryKeys = '',
    this.content = '',
    this.comment = '',
    this.constant = false,
    this.selective = false,
    this.siblingEntries = const [],
  });

  final String bookName;
  final String bookDescription;
  final String characterName;
  final String name;
  final String keys;
  final String secondaryKeys;
  final String content;
  final String comment;
  final bool constant;
  final bool selective;

  /// Other entries in the same book (for tone / continuity).
  final List<LoreSiblingSummary> siblingEntries;

  String valueFor(LoreCollaboratorField field) {
    switch (field) {
      case LoreCollaboratorField.name:
        return name;
      case LoreCollaboratorField.keys:
        return keys;
      case LoreCollaboratorField.secondaryKeys:
        return secondaryKeys;
      case LoreCollaboratorField.content:
        return content;
    }
  }
}

/// Compact summary of another entry in the same lorebook.
class LoreSiblingSummary {
  const LoreSiblingSummary({
    this.label = '',
    this.keys = const [],
    this.contentPreview = '',
    this.constant = false,
  });

  final String label;
  final List<String> keys;
  final String contentPreview;
  final bool constant;

  factory LoreSiblingSummary.fromEntry(LorebookEntry entry, {int maxChars = 160}) {
    final raw = entry.content.trim();
    final preview = raw.length <= maxChars
        ? raw
        : '${raw.substring(0, maxChars).trimRight()}…';
    return LoreSiblingSummary(
      label: entry.displayLabel,
      keys: List<String>.from(entry.keys),
      contentPreview: preview,
      constant: entry.constant,
    );
  }
}

/// Builds NanoGPT messages for the World Info entry AI wand.
class LoreCollaborator {
  const LoreCollaborator();

  String fieldLabel(LoreCollaboratorField field) {
    switch (field) {
      case LoreCollaboratorField.name:
        return 'Label';
      case LoreCollaboratorField.keys:
        return 'Keywords';
      case LoreCollaboratorField.secondaryKeys:
        return 'Secondary keywords';
      case LoreCollaboratorField.content:
        return 'Lore content';
    }
  }

  String fieldPurpose(LoreCollaboratorField field) {
    switch (field) {
      case LoreCollaboratorField.name:
        return 'Short editor label for this World Info entry '
            '(not sent to the chat AI as lore). Keep it brief.';
      case LoreCollaboratorField.keys:
        return 'SillyTavern-style trigger keywords. Comma-separated words or '
            'phrases that appear in chat and fire this entry. Prefer concrete '
            'names, places, items, and distinctive terms.';
      case LoreCollaboratorField.secondaryKeys:
        return 'Secondary keywords used with Selective (two-key) mode — a '
            'primary key AND a secondary key must both match. Comma-separated.';
      case LoreCollaboratorField.content:
        return 'World Info lore text injected into the AI prompt when this '
            'entry fires. Write factual setting details in third person. '
            'Keep it compact for mobile token budgets.';
    }
  }

  /// Messages for a one-shot NanoGPT call. Reuses normal model/sampling at call site.
  List<Map<String, String>> buildMessages({
    required LoreCollaboratorField field,
    required LoreEntryDraftContext draft,
    String guidanceNote = CollaboratorSettings.defaultGuidanceNote,
  }) {
    final current = draft.valueFor(field).trim();
    final contextBlock = _buildContextBlock(draft, exclude: field);
    final guidance = guidanceNote.trim().isEmpty
        ? CollaboratorSettings.defaultGuidanceNote
        : guidanceNote.trim();

    final system = StringBuffer()
      ..writeln(
        'You are an AI collaborator helping write SillyTavern-style '
        'World Info / lorebook entries for a private personal app called Anima.',
      )
      ..writeln()
      ..writeln('Guidance note (follow closely):')
      ..writeln(guidance)
      ..writeln()
      ..writeln('Target field: ${fieldLabel(field)}')
      ..writeln(fieldPurpose(field))
      ..writeln()
      ..writeln(
        'Write NEW text for that field only. Do not repeat existing field '
        'text unless briefly needed for continuity. The app will APPEND your '
        'reply below whatever is already in the field.',
      );

    if (field == LoreCollaboratorField.keys ||
        field == LoreCollaboratorField.secondaryKeys) {
      system.writeln(
        'For keywords: output a comma-separated list only — no quotes, '
        'no bullet points, no “here are keywords…”.',
      );
    } else if (field == LoreCollaboratorField.name) {
      system.writeln(
        'For the label: output a short name only (a few words), no quotes.',
      );
    } else {
      system.writeln(
        'Output plain lore text only — no quotes around the whole reply, '
        'no “here is…”, no field labels.',
      );
    }

    final user = StringBuffer();
    if (contextBlock.isEmpty) {
      user.writeln(
        'No other lorebook context is filled yet. Use only the draft below.',
      );
    } else {
      user.writeln('Current lorebook context:');
      user.writeln(contextBlock);
    }
    user.writeln();
    user.writeln('Target field: ${fieldLabel(field)}');
    if (current.isEmpty) {
      user.writeln(
        'The target field is empty. Invent fitting content from the lorebook '
        'context above (or invent freely if context is also empty).',
      );
    } else {
      user.writeln('Current draft / hint in the target field:');
      user.writeln(current);
      user.writeln();
      user.writeln(
        'Expand, continue, or refine based on that draft. Produce new text '
        'to append (do not restate the whole draft unless rewriting is needed).',
      );
    }

    return [
      {'role': 'system', 'content': system.toString().trim()},
      {'role': 'user', 'content': user.toString().trim()},
    ];
  }

  /// Appends [generated] under [existing], with a blank line when both have text.
  /// For keyword fields, joins with commas instead of a blank line.
  String appendGenerated(
    String existing,
    String generated, {
    required LoreCollaboratorField field,
  }) {
    final addition = generated.trim();
    if (addition.isEmpty) return existing;

    if (field == LoreCollaboratorField.keys ||
        field == LoreCollaboratorField.secondaryKeys) {
      return _appendKeywords(existing, addition);
    }

    if (field == LoreCollaboratorField.name) {
      final base = existing.trim();
      if (base.isEmpty) return addition;
      // Labels are short — replace with a refined suggestion when both exist.
      return addition;
    }

    final base = existing.trimRight();
    if (base.isEmpty) return addition;
    return '$base\n\n$addition';
  }

  String _appendKeywords(String existing, String generated) {
    final existingParts = _splitKeywords(existing);
    final newParts = _splitKeywords(generated);
    if (newParts.isEmpty) return existing.trim();
    if (existingParts.isEmpty) return newParts.join(', ');

    final seen = <String>{
      for (final p in existingParts) p.toLowerCase(),
    };
    final merged = List<String>.from(existingParts);
    for (final part in newParts) {
      final key = part.toLowerCase();
      if (seen.contains(key)) continue;
      seen.add(key);
      merged.add(part);
    }
    return merged.join(', ');
  }

  List<String> _splitKeywords(String raw) {
    return raw
        .split(RegExp(r'[,;\n]'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  String _buildContextBlock(
    LoreEntryDraftContext draft, {
    required LoreCollaboratorField exclude,
  }) {
    final lines = <String>[];
    void add(String label, String value) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) return;
      lines.add('$label:\n$trimmed');
    }

    add('Character (card this book belongs to)', draft.characterName);
    add('Lorebook name', draft.bookName);
    add('Lorebook notes', draft.bookDescription);
    if (draft.constant) {
      lines.add('This entry is Always on (no keyword required).');
    }
    if (draft.selective) {
      lines.add('This entry uses Selective (two-key) matching.');
    }

    if (exclude != LoreCollaboratorField.name) {
      add('Entry label', draft.name);
    }
    if (exclude != LoreCollaboratorField.keys) {
      add('Keywords', draft.keys);
    }
    if (exclude != LoreCollaboratorField.secondaryKeys) {
      add('Secondary keywords', draft.secondaryKeys);
    }
    if (exclude != LoreCollaboratorField.content) {
      add('Lore content', draft.content);
    }
    add('Editor comment', draft.comment);

    if (draft.siblingEntries.isNotEmpty) {
      final siblingLines = <String>[];
      for (final sibling in draft.siblingEntries.take(12)) {
        final bits = <String>[];
        if (sibling.label.trim().isNotEmpty) {
          bits.add(sibling.label.trim());
        }
        if (sibling.constant) {
          bits.add('always-on');
        } else if (sibling.keys.isNotEmpty) {
          bits.add('keys: ${sibling.keys.join(', ')}');
        }
        final head = bits.isEmpty ? 'Entry' : bits.join(' · ');
        if (sibling.contentPreview.trim().isEmpty) {
          siblingLines.add('- $head');
        } else {
          siblingLines.add('- $head — ${sibling.contentPreview.trim()}');
        }
      }
      lines.add('Other entries in this lorebook:\n${siblingLines.join('\n')}');
    }

    return lines.join('\n\n');
  }
}
