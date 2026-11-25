import '../models/field_wand_options.dart';
import 'settings_service.dart';

/// Creative character-card fields the AI wand can expand.
enum CharacterCollaboratorField {
  description,
  personality,
  scenario,
  firstMes,
  alternateGreetings,
  mesExample,
  systemPrompt,
  postHistoryInstructions,
}

/// Snapshot of the card being edited — all fields can be sent as context.
class CharacterDraftContext {
  const CharacterDraftContext({
    this.name = '',
    this.description = '',
    this.personality = '',
    this.scenario = '',
    this.firstMes = '',
    this.alternateGreetings = '',
    this.mesExample = '',
    this.systemPrompt = '',
    this.postHistoryInstructions = '',
    this.creatorNotes = '',
    this.creator = '',
    this.tags = '',
  });

  final String name;
  final String description;
  final String personality;
  final String scenario;
  final String firstMes;
  final String alternateGreetings;
  final String mesExample;
  final String systemPrompt;
  final String postHistoryInstructions;
  final String creatorNotes;
  final String creator;
  final String tags;

  String valueFor(CharacterCollaboratorField field) {
    switch (field) {
      case CharacterCollaboratorField.description:
        return description;
      case CharacterCollaboratorField.personality:
        return personality;
      case CharacterCollaboratorField.scenario:
        return scenario;
      case CharacterCollaboratorField.firstMes:
        return firstMes;
      case CharacterCollaboratorField.alternateGreetings:
        return alternateGreetings;
      case CharacterCollaboratorField.mesExample:
        return mesExample;
      case CharacterCollaboratorField.systemPrompt:
        return systemPrompt;
      case CharacterCollaboratorField.postHistoryInstructions:
        return postHistoryInstructions;
    }
  }
}

/// Builds NanoGPT messages for the character-editor AI wand.
class CharacterCollaborator {
  const CharacterCollaborator();

  String fieldLabel(CharacterCollaboratorField field) {
    switch (field) {
      case CharacterCollaboratorField.description:
        return 'Description';
      case CharacterCollaboratorField.personality:
        return 'Personality';
      case CharacterCollaboratorField.scenario:
        return 'Scenario';
      case CharacterCollaboratorField.firstMes:
        return 'First message';
      case CharacterCollaboratorField.alternateGreetings:
        return 'Alternate greetings';
      case CharacterCollaboratorField.mesExample:
        return 'Example messages';
      case CharacterCollaboratorField.systemPrompt:
        return 'System prompt';
      case CharacterCollaboratorField.postHistoryInstructions:
        return 'Post-history instructions';
    }
  }

  String fieldPurpose(CharacterCollaboratorField field) {
    switch (field) {
      case CharacterCollaboratorField.description:
        return 'ST Description — physical appearance, age, role/occupation, and '
            'factual backstory only (who they are on paper). Do NOT put temperament, '
            'speech style, or behavioral traits here — those belong in Personality.';
      case CharacterCollaboratorField.personality:
        return 'ST Personality — temperament, values, habits, speech style, and how '
            'they behave in scenes. Do NOT repeat appearance or backstory facts from '
            'Description — reference them only if needed for continuity.';
      case CharacterCollaboratorField.scenario:
        return 'ST Scenario — the current situation / scene context.';
      case CharacterCollaboratorField.firstMes:
        return 'ST First Message — the opening greeting when a new chat starts. '
            'Write in-character; may use {{char}} and {{user}}.';
      case CharacterCollaboratorField.alternateGreetings:
        return 'ST alternate_greetings — extra opening greetings (one per line) '
            'for swiping. Write one new greeting (or a few lines).';
      case CharacterCollaboratorField.mesExample:
        return 'ST mes_example — example dialogue that teaches tone and style. '
            'Prefer the <START> / {{user}}: / {{char}}: format. Do NOT paste the '
            'character bio here — write sample lines only.';
      case CharacterCollaboratorField.systemPrompt:
        return 'ST system_prompt — optional custom system instructions. '
            'May use {{original}} to keep Anima’s default.';
      case CharacterCollaboratorField.postHistoryInstructions:
        return 'ST post_history_instructions — a short nudge after chat history.';
    }
  }

  /// Messages for a one-shot NanoGPT call. Reuses normal model/sampling at call site.
  List<Map<String, String>> buildMessages({
    required CharacterCollaboratorField field,
    required CharacterDraftContext draft,
    String guidanceNote = CollaboratorSettings.defaultGuidanceNote,
    FieldWandExpansion expansion = FieldWandExpansion.light,
    FieldWandExternalSource? externalSource,
  }) {
    final current = draft.valueFor(field).trim();
    final contextBlock = _buildContextBlock(draft, exclude: field);
    final guidance = guidanceNote.trim().isEmpty
        ? CollaboratorSettings.defaultGuidanceNote
        : guidanceNote.trim();

    final system = StringBuffer()
      ..writeln(
        'You are an AI collaborator helping write a SillyTavern-style '
        'character card for a private personal app called Anima.',
      )
      ..writeln()
      ..writeln('Guidance note (follow closely):')
      ..writeln(guidance)
      ..writeln()
      ..writeln('Target field: ${fieldLabel(field)}')
      ..writeln(fieldPurpose(field))
      ..writeln()
      ..writeln(
        'Write NEW text for that field only. Do not repeat facts already in other '
        'fields (especially between Description and Personality). The app will '
        'APPEND your reply below whatever is already in the field.',
      )
      ..writeln(
        'Output plain field text only — no quotes around the whole reply, '
        'no “here is…”, no field labels.',
      )
      ..writeln()
      ..writeln('Expansion level:')
      ..writeln(expansion.promptInstruction);
    if (externalSource != null && !externalSource.isEmpty) {
      system.writeln();
      system.writeln(
        'Use the ${externalSource.label.toUpperCase()} CONTEXT in the user '
        'message to add facts that belong in this field. Do not dump unrelated '
        'material. If the field is sparse, prioritize concrete details from '
        'that context over inventing.',
      );
    }

    final user = StringBuffer();
    if (contextBlock.isEmpty) {
      user.writeln(
        'No other character fields are filled yet. Use only the draft below.',
      );
    } else {
      user.writeln('Current character card (other filled fields):');
      user.writeln(contextBlock);
    }
    user.writeln();
    user.writeln('Target field: ${fieldLabel(field)}');
    if (current.isEmpty) {
      user.writeln(
        'The target field is empty. Invent fitting content from the card '
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
    if (externalSource != null && !externalSource.isEmpty) {
      user.writeln();
      user.writeln('${externalSource.label} context:');
      user.writeln(externalSource.contextBlock.trim());
    }

    return [
      {'role': 'system', 'content': system.toString().trim()},
      {'role': 'user', 'content': user.toString().trim()},
    ];
  }

  /// Appends [generated] under [existing], with a blank line when both have text.
  String appendGenerated(String existing, String generated) {
    final addition = generated.trim();
    if (addition.isEmpty) return existing;
    final base = existing.trimRight();
    if (base.isEmpty) return addition;
    return '$base\n\n$addition';
  }

  String _buildContextBlock(
    CharacterDraftContext draft, {
    required CharacterCollaboratorField exclude,
  }) {
    final lines = <String>[];
    void add(String label, String value) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) return;
      lines.add('$label:\n$trimmed');
    }

    add('Name', draft.name);
    if (exclude != CharacterCollaboratorField.description) {
      add('Description', draft.description);
    }
    if (exclude != CharacterCollaboratorField.personality) {
      add('Personality', draft.personality);
    }
    if (exclude != CharacterCollaboratorField.scenario) {
      add('Scenario', draft.scenario);
    }
    if (exclude != CharacterCollaboratorField.firstMes) {
      add('First message', draft.firstMes);
    }
    if (exclude != CharacterCollaboratorField.alternateGreetings) {
      add('Alternate greetings', draft.alternateGreetings);
    }
    if (exclude != CharacterCollaboratorField.mesExample) {
      add('Example messages', draft.mesExample);
    }
    if (exclude != CharacterCollaboratorField.systemPrompt) {
      add('System prompt', draft.systemPrompt);
    }
    if (exclude != CharacterCollaboratorField.postHistoryInstructions) {
      add('Post-history instructions', draft.postHistoryInstructions);
    }
    add('Creator notes', draft.creatorNotes);
    add('Creator', draft.creator);
    add('Tags', draft.tags);

    return lines.join('\n\n');
  }

  static const _fullCharacterCardJsonShape = '''
{
  "spec": "chara_card_v2",
  "spec_version": "2.0",
  "data": {
    "name": "Character Name",
    "description": "appearance, background, important facts",
    "personality": "traits, speech style, motives",
    "scenario": "current situation / scene context",
    "first_mes": "opening greeting",
    "alternate_greetings": ["extra greeting 1", "extra greeting 2"],
    "mes_example": "<START>\\n{{user}}: ...\\n{{char}}: ...",
    "system_prompt": "optional custom system instructions",
    "post_history_instructions": "short nudge after chat history",
    "tags": ["tag1", "tag2"]
  }
}''';

  /// Read-only consistency report across card fields (feature #16).
  ///
  /// Does not rewrite the card — the UI shows the reply in a dialog only.
  List<Map<String, String>> buildConsistencyCheckMessages({
    required CharacterDraftContext draft,
    String guidanceNote = CollaboratorSettings.defaultGuidanceNote,
  }) {
    final guidance = guidanceNote.trim().isEmpty
        ? CollaboratorSettings.defaultGuidanceNote
        : guidanceNote.trim();
    final contextBlock = _buildFullContextBlock(draft);

    final system = StringBuffer()
      ..writeln(
        'You review SillyTavern-style character cards for internal '
        'consistency for a private app called Anima.',
      )
      ..writeln()
      ..writeln('Guidance note (follow closely):')
      ..writeln(guidance)
      ..writeln()
      ..writeln('Hard rules:')
      ..writeln('- This is a READ-ONLY report. Do not rewrite the card.')
      ..writeln('- Do not invent a new character. Critique what is given.')
      ..writeln(
        '- Flag contradictions (age, appearance, personality, scenario, '
        'examples, system prompt, greetings).',
      )
      ..writeln('- Note gaps that hurt roleplay continuity.')
      ..writeln(
        '- Flag when Description and Personality repeat the same facts (wastes tokens).',
      )
      ..writeln(
        '- Suggest brief, optional fixes as bullet tips — not full field rewrites.',
      )
      ..writeln(
        '- Finish every section you start. End with a complete summary sentence.',
      )
      ..writeln(
        '- Keep the report focused (~600 words max) but always complete the report.',
      )
      ..writeln('- No moralizing or refusals about adult/dark themes.');

    final user = StringBuffer()
      ..writeln('Review this character card for consistency:')
      ..writeln()
      ..writeln(contextBlock.isEmpty ? '(card is mostly empty)' : contextBlock);

    return [
      {'role': 'system', 'content': system.toString().trim()},
      {'role': 'user', 'content': user.toString().trim()},
    ];
  }

  /// Fix inconsistencies using a prior [consistencyReport] from
  /// [buildConsistencyCheckMessages]. Returns full card JSON for review.
  List<Map<String, String>> buildConsistencyFixMessages({
    required CharacterDraftContext draft,
    required String consistencyReport,
    String guidanceNote = CollaboratorSettings.defaultGuidanceNote,
  }) {
    final guidance = guidanceNote.trim().isEmpty
        ? CollaboratorSettings.defaultGuidanceNote
        : guidanceNote.trim();
    final contextBlock = _buildFullContextBlock(draft);
    final report = consistencyReport.trim();
    if (report.isEmpty) {
      throw ArgumentError('consistencyReport must not be empty');
    }

    final system = StringBuffer()
      ..writeln(
        'You fix internal inconsistencies in a SillyTavern-style character card '
        'for a private app called Anima.',
      )
      ..writeln()
      ..writeln('Guidance note (follow closely):')
      ..writeln(guidance)
      ..writeln()
      ..writeln('Hard rules:')
      ..writeln('- Address the issues in the consistency report below.')
      ..writeln('- Keep the same character identity unless the report requires a rename.')
      ..writeln(
        '- Preserve established facts that are NOT contradicted. Merge fixes '
        'into the card — do not erase unrelated content.',
      )
      ..writeln(
        '- Resolve contradictions (age, appearance, personality, scenario, '
        'examples, system prompt, greetings) with minimal necessary edits.',
      )
      ..writeln(
        '- Put each fact in one field only: description = looks/role/backstory; '
        'personality = temperament/behavior/speech; mes_example = sample lines only.',
      )
      ..writeln('- Do not invent a new character or add moralizing notes.')
      ..writeln()
      ..writeln('Output rules:')
      ..writeln('- Reply with ONLY a single JSON object. No markdown fences. No preamble.')
      ..writeln('- Prefer this shape (chara_card_v2):')
      ..writeln(_fullCharacterCardJsonShape)
      ..writeln(
        '- Include every listed field from the current card (use empty string or '
        '[] when a field is intentionally blank).',
      )
      ..writeln('- Do NOT include character_book / lorebook — lore stays separate.')
      ..writeln('- Do NOT include creator_notes, creator, or character_version.');

    final user = StringBuffer()
      ..writeln('CURRENT CHARACTER CARD:')
      ..writeln(contextBlock.isEmpty ? '(card is mostly empty)' : contextBlock)
      ..writeln()
      ..writeln('CONSISTENCY REPORT (fix these issues):')
      ..writeln(report)
      ..writeln()
      ..writeln(
        'Output the corrected character card as one JSON object. Fix only what '
        'the report requires; keep everything else aligned with the current card.',
      );

    return [
      {'role': 'system', 'content': system.toString().trim()},
      {'role': 'user', 'content': user.toString().trim()},
    ];
  }

  /// Compact a card for fewer prompt tokens while keeping RP-critical facts.
  ///
  /// Returns the same JSON shape as [buildConsistencyFixMessages] for parsing.
  List<Map<String, String>> buildCompactMessages({
    required CharacterDraftContext draft,
    String guidanceNote = CollaboratorSettings.defaultGuidanceNote,
  }) {
    final guidance = guidanceNote.trim().isEmpty
        ? CollaboratorSettings.defaultGuidanceNote
        : guidanceNote.trim();
    final contextBlock = _buildFullContextBlock(draft);

    final system = StringBuffer()
      ..writeln(
        'You compact SillyTavern-style character cards for a private mobile app '
        'called Anima.',
      )
      ..writeln()
      ..writeln('Guidance note (follow closely):')
      ..writeln(guidance)
      ..writeln()
      ..writeln('Goal: shorten the card for fewer prompt tokens while keeping '
          'everything needed for good roleplay.')
      ..writeln()
      ..writeln('Hard rules:')
      ..writeln('- Keep the same character identity, voice, and established facts.')
      ..writeln('- Remove filler, repetition, and prose that does not change behavior.')
      ..writeln('- Put each fact in one field only: description = looks/role/backstory; '
          'personality = temperament/behavior/speech; mes_example = sample lines only.')
      ..writeln('- Shorten greetings and examples — keep tone, cut padding.')
      ..writeln('- Prefer tight bullet phrases over long paragraphs where possible.')
      ..writeln('- Aim for roughly 30–50% shorter overall when the card is verbose.')
      ..writeln('- Do not add moralizing notes or invent new plot.')
      ..writeln('- If a field is already minimal, leave it unchanged or only lightly trim.')
      ..writeln()
      ..writeln('Output rules:')
      ..writeln('- Reply with ONLY a single JSON object. No markdown fences. No preamble.')
      ..writeln('- Prefer this shape (chara_card_v2):')
      ..writeln(_fullCharacterCardJsonShape)
      ..writeln(
        '- Include every listed field from the current card (use empty string or '
        '[] when a field is intentionally blank).',
      )
      ..writeln('- Do NOT include character_book / lorebook — lore stays separate.')
      ..writeln('- Do NOT include creator_notes, creator, or character_version.');

    final user = StringBuffer()
      ..writeln('CURRENT CHARACTER CARD (compact this):')
      ..writeln(contextBlock.isEmpty ? '(card is mostly empty)' : contextBlock)
      ..writeln()
      ..writeln(
        'Output the compacted character card as one JSON object. Shorter, denser, '
        'same character.',
      );

    return [
      {'role': 'system', 'content': system.toString().trim()},
      {'role': 'user', 'content': user.toString().trim()},
    ];
  }

  /// Expand a card with new interesting details invented from what is already there.
  ///
  /// Returns the same JSON shape as [buildConsistencyFixMessages] for parsing.
  List<Map<String, String>> buildExpandMessages({
    required CharacterDraftContext draft,
    String guidanceNote = CollaboratorSettings.defaultGuidanceNote,
  }) {
    final guidance = guidanceNote.trim().isEmpty
        ? CollaboratorSettings.defaultGuidanceNote
        : guidanceNote.trim();
    final contextBlock = _buildFullContextBlock(draft);

    final system = StringBuffer()
      ..writeln(
        'You expand SillyTavern-style character cards for a private mobile app '
        'called Anima.',
      )
      ..writeln()
      ..writeln('Guidance note (follow closely):')
      ..writeln(guidance)
      ..writeln()
      ..writeln('Goal: enrich the card with vivid, playable detail the writer '
          'did not have to specify. Invent interesting ideas that fit what is '
          'already on the card.')
      ..writeln()
      ..writeln('Hard rules:')
      ..writeln('- Keep the same character identity, names (including aliases), '
          'voice, and established facts. Do not split one person into two.')
      ..writeln('- Do NOT contradict, drop, or sanitize existing facts.')
      ..writeln('- ADD new material: sensory appearance, habits, speech tics, '
          'relationships, abilities/powers/weaknesses, secrets, history beats, '
          'and example lines that show the new texture.')
      ..writeln('- Put each fact in one field only: description = looks/role/'
          'backstory/powers; personality = temperament/behavior/speech; '
          'mes_example = sample lines only.')
      ..writeln('- Fill sparse or empty creative fields when you can invent '
          'fitting material. Leave system_prompt and post_history_instructions '
          'unchanged unless they already have text that needs a matching expand.')
      ..writeln('- Aim for roughly 1.5–2× richer overall when the card is thin; '
          'still add at least a few new concrete facts if it is already long.')
      ..writeln('- Do not moralize. Adult or dark content already on the card '
          'may stay and be expanded in the same register.')
      ..writeln()
      ..writeln('Output rules:')
      ..writeln('- Reply with ONLY a single JSON object. No markdown fences. No preamble.')
      ..writeln('- Prefer this shape (chara_card_v2):')
      ..writeln(_fullCharacterCardJsonShape)
      ..writeln(
        '- Include every listed field from the current card (use empty string or '
        '[] when a field is intentionally blank).',
      )
      ..writeln('- Do NOT include character_book / lorebook — lore stays separate.')
      ..writeln('- Do NOT include creator_notes, creator, or character_version.');

    final user = StringBuffer()
      ..writeln('CURRENT CHARACTER CARD (expand this — invent extra detail):')
      ..writeln(contextBlock.isEmpty ? '(card is mostly empty)' : contextBlock)
      ..writeln()
      ..writeln(
        'Output the expanded character card as one JSON object. Same person, '
        'more texture and ideas.',
      );

    return [
      {'role': 'system', 'content': system.toString().trim()},
      {'role': 'user', 'content': user.toString().trim()},
    ];
  }

  /// Cross-reference: draft this card with another character/persona card as
  /// shared-world reference material. The target identity in [draft] stays;
  /// facts from the source are re-pointed at the target.
  ///
  /// Returns the same JSON shape as [buildExpandMessages] for parsing.
  List<Map<String, String>> buildCrossReferenceMessages({
    required CharacterDraftContext draft,
    required String sourceLabel,
    required String sourceBlock,
    String notes = '',
    String guidanceNote = CollaboratorSettings.defaultGuidanceNote,
  }) {
    final guidance = guidanceNote.trim().isEmpty
        ? CollaboratorSettings.defaultGuidanceNote
        : guidanceNote.trim();
    final contextBlock = _buildFullContextBlock(draft);
    final trimmedNotes = notes.trim();

    final system = StringBuffer()
      ..writeln(
        'You adapt SillyTavern-style character cards for a private mobile app '
        'called Anima.',
      )
      ..writeln()
      ..writeln('Guidance note (follow closely):')
      ..writeln(guidance)
      ..writeln()
      ..writeln(
        'Task: CROSS-REFERENCE. The SOURCE card is reference material; the '
        'TARGET is the character card you are drafting. Ground the target in '
        'the source’s shared world so both cards fit together in the same '
        'chats.',
      )
      ..writeln()
      ..writeln('Hard rules:')
      ..writeln(
        '- The TARGET comes first. Keep its name (and aliases) exactly; never '
        'replace the target with the source character.',
      )
      ..writeln(
        '- Keep everything already written on the target unless it directly '
        'conflicts with a borrowed fact; resolve conflicts in favor of the '
        'target.',
      )
      ..writeln(
        '- Borrow concrete shared-world facts from the SOURCE (places, '
        'factions, organizations, events, history, speech register) and '
        're-point them at the target.',
      )
      ..writeln(
        '- Invent glue where the source is silent: how the target fits the '
        'same world, and optionally how they know of or cross paths with the '
        'source.',
      )
      ..writeln(
        '- The target is a distinct person: do NOT copy the source bio '
        'wholesale or duplicate the source identity, appearance, or voice.',
      )
      ..writeln(
        '- Put each fact in one field only: description = looks/role/backstory; '
        'personality = temperament/behavior/speech; mes_example = sample lines '
        'only.',
      )
      ..writeln(
        '- Fill sparse or empty creative fields with grounded material. Leave '
        'system_prompt and post_history_instructions unchanged.',
      )
      ..writeln(
        '- Do not moralize. Match the register of the source and target cards.',
      )
      ..writeln()
      ..writeln('Output rules:')
      ..writeln('- Reply with ONLY a single JSON object. No markdown fences. No preamble.')
      ..writeln('- Prefer this shape (chara_card_v2):')
      ..writeln(_fullCharacterCardJsonShape)
      ..writeln(
        '- Include every listed field from the target card (use empty string or '
        '[] when a field is intentionally blank).',
      )
      ..writeln('- Do NOT include character_book / lorebook — lore stays separate.')
      ..writeln('- Do NOT include creator_notes, creator, or character_version.');

    final userParts = <String>[
      'SOURCE CARD (reference material — $sourceLabel):',
      sourceBlock.trim().isEmpty ? '(source card is empty)' : sourceBlock.trim(),
      'TARGET CHARACTER CARD (draft this):',
      contextBlock.isEmpty
          ? '(target card is mostly empty — draft it from the source’s world)'
          : contextBlock,
      if (trimmedNotes.isNotEmpty) 'HOW THEY CONNECT (follow this):\n$trimmedNotes',
      'Output the cross-referenced target card as one JSON object. Same '
          'target, grounded in the source’s world.',
    ];
    final user = userParts.join('\n\n');

    return [
      {'role': 'system', 'content': system.toString().trim()},
      {'role': 'user', 'content': user},
    ];
  }

  String _buildFullContextBlock(CharacterDraftContext draft) {
    final lines = <String>[];
    void add(String label, String value) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) return;
      lines.add('$label:\n$trimmed');
    }

    add('Name', draft.name);
    add('Description', draft.description);
    add('Personality', draft.personality);
    add('Scenario', draft.scenario);
    add('First message', draft.firstMes);
    add('Alternate greetings', draft.alternateGreetings);
    add('Example messages', draft.mesExample);
    add('System prompt', draft.systemPrompt);
    add('Post-history instructions', draft.postHistoryInstructions);
    add('Creator notes', draft.creatorNotes);
    add('Creator', draft.creator);
    add('Tags', draft.tags);
    return lines.join('\n\n');
  }
}
