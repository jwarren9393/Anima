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

  /// Suggest trigger keywords from the entry's lore content (feature #15).
  ///
  /// Output is meant to be merged into the Keywords field — not a free rewrite.
  List<Map<String, String>> buildKeywordSuggestMessages({
    required LoreEntryDraftContext draft,
    String guidanceNote = CollaboratorSettings.defaultGuidanceNote,
  }) {
    final content = draft.content.trim();
    final guidance = guidanceNote.trim().isEmpty
        ? CollaboratorSettings.defaultGuidanceNote
        : guidanceNote.trim();

    final system = StringBuffer()
      ..writeln(
        'You extract SillyTavern World Info trigger keywords from lore text '
        'for a private app called Anima.',
      )
      ..writeln()
      ..writeln('Guidance note (follow closely):')
      ..writeln(guidance)
      ..writeln()
      ..writeln('Hard rules:')
      ..writeln(
        '- Read the lore content and list concrete trigger words/phrases '
        'that would appear in chat (names, places, items, titles, distinctive terms).',
      )
      ..writeln('- Prefer 4–12 keywords. Avoid generic words (the, he, magic).')
      ..writeln(
        '- Output a comma-separated list only — no quotes, bullets, or preamble.',
      )
      ..writeln('- Do not rewrite the lore content.');

    final user = StringBuffer();
    if (draft.bookName.trim().isNotEmpty) {
      user.writeln('Lorebook: ${draft.bookName.trim()}');
    }
    if (draft.name.trim().isNotEmpty) {
      user.writeln('Entry label: ${draft.name.trim()}');
    }
    if (draft.keys.trim().isNotEmpty) {
      user.writeln('Existing keywords (do not simply repeat these):');
      user.writeln(draft.keys.trim());
      user.writeln();
    }
    user.writeln('Lore content:');
    user.writeln(content.isEmpty ? '(empty)' : content);
    user.writeln();
    user.writeln('Suggest keywords as a comma-separated list:');

    return [
      {'role': 'system', 'content': system.toString().trim()},
      {'role': 'user', 'content': user.toString().trim()},
    ];
  }

  /// Merges suggested keywords into [existing] (deduped, comma-separated).
  String mergeKeywords(String existing, String suggested) =>
      _appendKeywords(existing, suggested);

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

  String _buildFullBookBlock(Lorebook book, {String characterName = ''}) {
    final lines = <String>[];
    void add(String label, String value) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) return;
      lines.add('$label:\n$trimmed');
    }

    add('Character (card this book belongs to)', characterName);
    add('Lorebook name', book.name);
    add('Lorebook notes', book.description);
    lines.add('Scan depth: ${book.scanDepth}');
    lines.add('Token budget: ${book.tokenBudget}');
    if (book.recursiveScanning) {
      lines.add('Recursive scanning: on');
    }

    if (book.entries.isEmpty) {
      lines.add('Entries: (none)');
    } else {
      final entryLines = <String>[];
      for (final entry in book.entries) {
        final bits = <String>[];
        if (entry.id != null) bits.add('id ${entry.id}');
        if (entry.name.trim().isNotEmpty) bits.add('label: ${entry.name.trim()}');
        if (entry.constant) {
          bits.add('always-on');
        } else if (entry.keys.isNotEmpty) {
          bits.add('keys: ${entry.keys.join(', ')}');
        }
        if (entry.secondaryKeys.isNotEmpty) {
          bits.add('secondary: ${entry.secondaryKeys.join(', ')}');
        }
        if (!entry.enabled) bits.add('disabled');
        final head = bits.isEmpty ? 'Entry' : bits.join(' · ');
        final body = entry.content.trim().isEmpty ? '(empty)' : entry.content.trim();
        entryLines.add('- $head\n$body');
      }
      lines.add('Entries:\n${entryLines.join('\n\n')}');
    }

    return lines.join('\n\n');
  }

  static const _lorebookJsonShape = '''
{
  "name": "short book title",
  "description": "one-line summary",
  "scan_depth": 4,
  "token_budget": 512,
  "recursive_scanning": false,
  "entries": [
    {
      "id": 1,
      "name": "optional label",
      "keys": ["keyword", "alias"],
      "secondary_keys": [],
      "content": "lore text injected when keys match",
      "enabled": true,
      "constant": false,
      "selective": false,
      "insertion_order": 100,
      "priority": 10,
      "case_sensitive": false,
      "position": "before_char",
      "comment": ""
    }
  ]
}''';

  /// Read-only consistency report for a whole lorebook.
  List<Map<String, String>> buildConsistencyCheckMessages({
    required Lorebook book,
    String characterName = '',
    String guidanceNote = CollaboratorSettings.defaultGuidanceNote,
  }) {
    final guidance = guidanceNote.trim().isEmpty
        ? CollaboratorSettings.defaultGuidanceNote
        : guidanceNote.trim();
    final contextBlock = _buildFullBookBlock(book, characterName: characterName);

    final system = StringBuffer()
      ..writeln(
        'You review SillyTavern World Info lorebooks for internal consistency '
        'for a private app called Anima.',
      )
      ..writeln()
      ..writeln('Guidance note (follow closely):')
      ..writeln(guidance)
      ..writeln()
      ..writeln('Hard rules:')
      ..writeln('- This is a READ-ONLY report. Do not rewrite the lorebook.')
      ..writeln('- Flag contradictions between entries (names, places, timelines, rules).')
      ..writeln('- Flag duplicate or overlapping entries that should merge.')
      ..writeln('- Flag weak or missing keywords that would fail to trigger lore.')
      ..writeln('- Suggest brief, optional fixes as bullet tips — not full rewrites.')
      ..writeln('- Keep the report under ~400 words. Use short sections with headings.')
      ..writeln('- No moralizing or refusals about adult/dark themes.');

    final user = StringBuffer()
      ..writeln('Review this lorebook for consistency:')
      ..writeln()
      ..writeln(contextBlock.isEmpty ? '(lorebook is mostly empty)' : contextBlock);

    return [
      {'role': 'system', 'content': system.toString().trim()},
      {'role': 'user', 'content': user.toString().trim()},
    ];
  }

  /// Fix inconsistencies using a prior lorebook consistency report.
  List<Map<String, String>> buildConsistencyFixMessages({
    required Lorebook book,
    required String consistencyReport,
    String characterName = '',
    String guidanceNote = CollaboratorSettings.defaultGuidanceNote,
  }) {
    final guidance = guidanceNote.trim().isEmpty
        ? CollaboratorSettings.defaultGuidanceNote
        : guidanceNote.trim();
    final contextBlock = _buildFullBookBlock(book, characterName: characterName);
    final report = consistencyReport.trim();
    if (report.isEmpty) {
      throw ArgumentError('consistencyReport must not be empty');
    }

    final system = StringBuffer()
      ..writeln(
        'You fix internal inconsistencies in a SillyTavern World Info lorebook '
        'for a private app called Anima.',
      )
      ..writeln()
      ..writeln('Guidance note (follow closely):')
      ..writeln(guidance)
      ..writeln()
      ..writeln('Hard rules:')
      ..writeln('- Address the issues in the consistency report below.')
      ..writeln('- Preserve entry IDs, extensions, and settings unless the report requires changes.')
      ..writeln('- Merge overlapping entries when the report says to; do not erase unrelated lore.')
      ..writeln('- Resolve contradictions with minimal necessary edits.')
      ..writeln('- Do not moralize or refuse adult/dark themes.')
      ..writeln()
      ..writeln('Output rules:')
      ..writeln('- Reply with ONLY a single JSON object. No markdown fences. No preamble.')
      ..writeln('- Shape:')
      ..writeln(_lorebookJsonShape)
      ..writeln('- Output the complete corrected lorebook in one object.');

    final user = StringBuffer()
      ..writeln('CURRENT LOREBOOK:')
      ..writeln(contextBlock.isEmpty ? '(lorebook is mostly empty)' : contextBlock)
      ..writeln()
      ..writeln('CONSISTENCY REPORT (fix these issues):')
      ..writeln(report)
      ..writeln()
      ..writeln(
        'Output the corrected lorebook as one JSON object. Fix only what the '
        'report requires; keep everything else aligned with the current book.',
      );

    return [
      {'role': 'system', 'content': system.toString().trim()},
      {'role': 'user', 'content': user.toString().trim()},
    ];
  }
}
