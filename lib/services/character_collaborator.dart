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
        return 'ST Description — appearance, background, important facts. '
            'Usually included in every chat prompt.';
      case CharacterCollaboratorField.personality:
        return 'ST Personality — a concise personality summary.';
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
            'Prefer the <START> / {{user}}: / {{char}}: format.';
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
        'Write NEW text for that field only. Do not repeat existing field '
        'text unless briefly needed for continuity. The app will APPEND your '
        'reply below whatever is already in the field.',
      )
      ..writeln(
        'Output plain field text only — no quotes around the whole reply, '
        'no “here is…”, no field labels.',
      );

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
}
