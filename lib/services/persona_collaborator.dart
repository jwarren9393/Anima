import 'settings_service.dart';

/// Creative persona fields the AI wand can expand.
enum PersonaCollaboratorField {
  description,
  appearance,
  personality,
  background,
  goals,
}

/// Snapshot of the persona being edited — all fields can be sent as context.
class PersonaDraftContext {
  const PersonaDraftContext({
    this.name = '',
    this.description = '',
    this.appearance = '',
    this.personality = '',
    this.background = '',
    this.goals = '',
  });

  final String name;
  final String description;
  final String appearance;
  final String personality;
  final String background;
  final String goals;

  String valueFor(PersonaCollaboratorField field) {
    switch (field) {
      case PersonaCollaboratorField.description:
        return description;
      case PersonaCollaboratorField.appearance:
        return appearance;
      case PersonaCollaboratorField.personality:
        return personality;
      case PersonaCollaboratorField.background:
        return background;
      case PersonaCollaboratorField.goals:
        return goals;
    }
  }
}

/// Builds NanoGPT messages for the persona-editor AI wand.
class PersonaCollaborator {
  const PersonaCollaborator();

  String fieldLabel(PersonaCollaboratorField field) {
    switch (field) {
      case PersonaCollaboratorField.description:
        return 'Identity and role';
      case PersonaCollaboratorField.appearance:
        return 'Appearance';
      case PersonaCollaboratorField.personality:
        return 'Personality';
      case PersonaCollaboratorField.background:
        return 'Background';
      case PersonaCollaboratorField.goals:
        return 'Goals and motivations';
    }
  }

  String fieldPurpose(PersonaCollaboratorField field) {
    switch (field) {
      case PersonaCollaboratorField.description:
        return 'Player identity and role — who {{user}} is and their place in '
            'the setting (title, occupation, faction, relationship to the world). '
            'Facts about the player, not instructions for the AI to speak as them.';
      case PersonaCollaboratorField.appearance:
        return 'Appearance — physical features, clothing, and distinguishing '
            'details for the player persona.';
      case PersonaCollaboratorField.personality:
        return 'Personality — traits, habits, temperament, and manner of speaking.';
      case PersonaCollaboratorField.background:
        return 'Background — history, relationships, abilities, and important '
            'personal facts. Keep broad world lore short; that belongs in lorebooks.';
      case PersonaCollaboratorField.goals:
        return 'Goals and motivations — what they want, fear, protect, or work toward.';
    }
  }

  /// Messages for a one-shot NanoGPT call. Reuses normal model/sampling at call site.
  List<Map<String, String>> buildMessages({
    required PersonaCollaboratorField field,
    required PersonaDraftContext draft,
    String guidanceNote = CollaboratorSettings.defaultGuidanceNote,
  }) {
    final current = draft.valueFor(field).trim();
    final contextBlock = _buildContextBlock(draft, exclude: field);
    final guidance = guidanceNote.trim().isEmpty
        ? CollaboratorSettings.defaultGuidanceNote
        : guidanceNote.trim();

    final system = StringBuffer()
      ..writeln(
        'You are an AI collaborator helping write a user persona ({{user}}) '
        'for a private personal roleplay app called Anima. This is the human '
        'player identity, not an AI-controlled character card.',
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
        'Do not write greetings, example dialogue, system prompts, or commands '
        'telling the assistant to roleplay this persona.',
      )
      ..writeln(
        'Output plain field text only — no quotes around the whole reply, '
        'no “here is…”, no field labels.',
      );

    final user = StringBuffer();
    if (contextBlock.isEmpty) {
      user.writeln(
        'No other persona fields are filled yet. Use only the draft below.',
      );
    } else {
      user.writeln('Current persona (other filled fields):');
      user.writeln(contextBlock);
    }
    user.writeln();
    user.writeln('Target field: ${fieldLabel(field)}');
    if (current.isEmpty) {
      user.writeln(
        'The target field is empty. Invent fitting content from the persona '
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
    PersonaDraftContext draft, {
    required PersonaCollaboratorField exclude,
  }) {
    final lines = <String>[];
    void add(String label, String value) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) return;
      lines.add('$label:\n$trimmed');
    }

    add('Name', draft.name);
    if (exclude != PersonaCollaboratorField.description) {
      add('Identity and role', draft.description);
    }
    if (exclude != PersonaCollaboratorField.appearance) {
      add('Appearance', draft.appearance);
    }
    if (exclude != PersonaCollaboratorField.personality) {
      add('Personality', draft.personality);
    }
    if (exclude != PersonaCollaboratorField.background) {
      add('Background', draft.background);
    }
    if (exclude != PersonaCollaboratorField.goals) {
      add('Goals and motivations', draft.goals);
    }

    return lines.join('\n\n');
  }
}
