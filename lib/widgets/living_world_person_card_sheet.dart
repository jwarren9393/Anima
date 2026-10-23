import 'package:flutter/material.dart';

import '../models/character.dart';
import '../models/chat_session.dart';
import '../models/living_world.dart';
import '../models/persona.dart';
import '../screens/personas_screen.dart';
import '../services/ai_field_changes.dart';
import '../services/character_service.dart';
import '../services/chat_service.dart';
import '../services/living_world_card_bridge.dart';
import '../services/living_world_service.dart';
import '../services/nanogpt_service.dart';
import '../services/persona_service.dart';
import '../services/settings_service.dart';
import '../services/world_workshop_builder.dart';
import 'ai_field_changes_sheet.dart';
import 'greeting_picker.dart';

/// Phase 13 flows: notebook person → character / persona / bound solo chat.
class LivingWorldPersonCardActions {
  LivingWorldPersonCardActions._();

  static const _bridge = LivingWorldCardBridge();
  static final _builder = WorldWorkshopBuilder();

  /// AI-drafts a character from [person], reviews fields, saves, links person.
  ///
  /// Returns the updated world (with `characterCardId` set) or null if cancelled.
  static Future<({LivingWorld world, Character character})?>
  createCharacterFromPerson({
    required BuildContext context,
    required LivingWorld world,
    required WorldPerson person,
    required LivingWorldService worldService,
    required CharacterService characterService,
    required SettingsService settingsService,
    required NanoGptService nanoGptService,
  }) async {
    final name = person.name.trim();
    if (name.isEmpty) {
      _toast(context, 'Give this person a name first.');
      return null;
    }

    final existingLink = person.characterCardId?.trim() ?? '';
    if (existingLink.isNotEmpty) {
      final replace = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Already linked'),
          content: Text(
            '$name already links to card $existingLink. '
            'Create a new character and replace the link?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Create new'),
            ),
          ],
        ),
      );
      if (replace != true || !context.mounted) return null;
    }

    final preferredId = characterService.newId();
    final seed = _bridge.seedCharacterFromPerson(person, id: preferredId);
    final brief = _bridge.buildPersonBrief(world: world, person: person);

    _showBusy(context, 'Drafting character from $name…');
    Character? draft;
    try {
      final build = await settingsService.resolveCharacterBuild();
      final baseUrl = await settingsService.getApiBaseUrl();
      final messages = _builder.buildPlainEnglishCharacterExportMessages(
        userBrief: brief,
        characterName: name,
        buildPromptNote: build.promptNote,
      );
      for (var attempt = 0; attempt < 2; attempt++) {
        final raw = await nanoGptService.complete(
          model: build.model,
          messages: messages,
          baseUrl: baseUrl,
          sampling: WorldWorkshopBuilder.workshopExportSampling(build.sampling),
        );
        try {
          draft = _builder.parseCharacterJson(
            raw,
            preferredId: preferredId,
            fallbackName: name,
          );
          break;
        } on FormatException {
          if (attempt == 1) rethrow;
        }
      }
    } catch (e) {
      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
      if (context.mounted) {
        final useSeed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('AI draft failed'),
            content: Text(
              'Could not draft with AI ($e).\n\n'
              'Save a simple card from the notebook fields instead?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Use notebook fields'),
              ),
            ],
          ),
        );
        if (useSeed != true || !context.mounted) return null;
        draft = seed;
      } else {
        return null;
      }
    }

    if (context.mounted && draft != seed) {
      Navigator.of(context, rootNavigator: true).pop(); // busy
    }
    if (!context.mounted || draft == null) return null;

    // Keep a greeting if the slim parser cleared it.
    if (draft.firstMes.trim().isEmpty && seed.firstMes.trim().isNotEmpty) {
      draft = draft.copyWith(firstMes: seed.firstMes);
    }
    if (draft.name.trim().isEmpty) {
      draft = draft.copyWith(name: name);
    }

    final empty = Character(id: preferredId, name: name);
    final changes = compareCharacterFields(empty, draft);
    if (changes.isEmpty) {
      _toast(context, 'No character fields to review.');
      return null;
    }

    final selected = await showAiFieldChangesSheet(
      context: context,
      title: 'Review character from $name',
      subtitle:
          'Check fields to save as a new character card, then link this person.',
      changes: changes,
      applyLabel: 'Save character',
    );
    if (selected == null || !context.mounted) return null;

    final merged = mergeCharacterChanges(empty, draft, selected);
    if (merged.name.trim().isEmpty) {
      _toast(context, 'Character needs a name.');
      return null;
    }

    await characterService.upsert(merged);
    final linked = _bridge.linkPersonToCharacter(
      world,
      personId: person.id,
      characterId: merged.id,
    );
    final saved = await worldService.save(linked);
    if (context.mounted) {
      _toast(context, 'Saved ${merged.name} and linked in the world.');
    }
    return (world: saved, character: merged);
  }

  /// AI-drafts a persona from [person] (player stand-in). Does not change links.
  static Future<Persona?> createPersonaFromPerson({
    required BuildContext context,
    required LivingWorld world,
    required WorldPerson person,
    required PersonaService personaService,
    required SettingsService settingsService,
    required NanoGptService nanoGptService,
  }) async {
    final name = person.name.trim();
    if (name.isEmpty) {
      _toast(context, 'Give this person a name first.');
      return null;
    }

    final preferredId = personaService.newId();
    final seed = _bridge.seedPersonaFromPerson(person, id: preferredId);
    final brief = _bridge.buildPersonBrief(world: world, person: person);

    _showBusy(context, 'Drafting persona from $name…');
    Persona? draft;
    try {
      final build = await settingsService.resolveCharacterBuild();
      final baseUrl = await settingsService.getApiBaseUrl();
      final messages = _builder.buildPlainEnglishPersonaExportMessages(
        userBrief: brief,
        personaName: name,
        buildPromptNote: build.personaPromptNote,
      );
      for (var attempt = 0; attempt < 2; attempt++) {
        final raw = await nanoGptService.complete(
          model: build.model,
          messages: messages,
          baseUrl: baseUrl,
          sampling: WorldWorkshopBuilder.workshopExportSampling(build.sampling),
        );
        try {
          draft = _builder.parsePersonaJson(
            raw,
            preferredId: preferredId,
            fallbackName: name,
          );
          break;
        } on FormatException {
          if (attempt == 1) rethrow;
        }
      }
    } catch (e) {
      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
      if (context.mounted) {
        final useSeed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('AI draft failed'),
            content: Text(
              'Could not draft with AI ($e).\n\n'
              'Save a simple persona from the notebook fields instead?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Use notebook fields'),
              ),
            ],
          ),
        );
        if (useSeed != true || !context.mounted) return null;
        draft = seed;
      } else {
        return null;
      }
    }

    if (context.mounted && draft != seed) {
      Navigator.of(context, rootNavigator: true).pop();
    }
    if (!context.mounted || draft == null) return null;

    if (draft.name.trim().isEmpty) {
      draft = draft.copyWith(name: name);
    }

    final empty = Persona(id: preferredId, name: name);
    final changes = comparePersonaFields(empty, draft);
    if (changes.isEmpty) {
      _toast(context, 'No persona fields to review.');
      return null;
    }

    final selected = await showAiFieldChangesSheet(
      context: context,
      title: 'Review persona from $name',
      subtitle: 'Check fields to save as a {{user}} persona (player stand-in).',
      changes: changes,
      applyLabel: 'Save persona',
    );
    if (selected == null || !context.mounted) return null;

    final merged = mergePersonaChanges(empty, draft, selected);
    if (merged.name.trim().isEmpty) {
      _toast(context, 'Persona needs a name.');
      return null;
    }

    await personaService.upsert(merged);
    if (context.mounted) {
      _toast(context, 'Saved persona ${merged.name}.');
    }
    return merged;
  }

  /// Update an existing character card from Living World person state (arcs,
  /// relationships, soft personality) — review before save.
  static Future<Character?> refreshCharacterFromWorld({
    required BuildContext context,
    required LivingWorld world,
    required WorldPerson person,
    required Character existing,
    required CharacterService characterService,
    required SettingsService settingsService,
    required NanoGptService nanoGptService,
  }) async {
    final name = person.name.trim().isNotEmpty
        ? person.name.trim()
        : existing.name.trim();
    final brief = _bridge.buildPersonBrief(world: world, person: person);
    final cardSnapshot = StringBuffer()
      ..writeln('Name: ${existing.name}')
      ..writeln('Description: ${existing.description}')
      ..writeln('Personality: ${existing.personality}')
      ..writeln('Scenario: ${existing.scenario}')
      ..writeln('System prompt: ${existing.systemPrompt}')
      ..writeln('Post-history: ${existing.postHistoryInstructions}');

    final userBrief =
        'Update this existing Anima character card so it matches the Living '
        'World notebook (relationships, soft personality drift, current role). '
        'Keep the same person and name. Prefer short, concrete edits — do not '
        'rewrite the whole card for no reason. Adult fiction OK.\n\n'
        '## Current character card\n'
        '${cardSnapshot.toString().trim()}\n\n'
        '## Living World person state (authoritative for arcs / links)\n'
        '$brief';

    _showBusy(context, 'Updating ${existing.name} from world…');
    Character? draft;
    try {
      final build = await settingsService.resolveCharacterBuild();
      final baseUrl = await settingsService.getApiBaseUrl();
      final messages = _builder.buildPlainEnglishCharacterExportMessages(
        userBrief: userBrief,
        characterName: name,
        buildPromptNote: build.promptNote,
      );
      for (var attempt = 0; attempt < 2; attempt++) {
        final raw = await nanoGptService.complete(
          model: build.model,
          messages: messages,
          baseUrl: baseUrl,
          sampling: WorldWorkshopBuilder.workshopExportSampling(build.sampling),
        );
        try {
          draft = _builder.parseCharacterJson(
            raw,
            preferredId: existing.id,
            fallbackName: name,
          );
          break;
        } on FormatException {
          if (attempt == 1) rethrow;
        }
      }
    } catch (e) {
      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
      if (context.mounted) {
        _toast(context, 'Could not update from world: $e');
      }
      return null;
    }

    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
    if (!context.mounted || draft == null) return null;

    // Preserve greetings / examples unless the model filled them.
    draft = draft.copyWith(
      id: existing.id,
      name: draft.name.trim().isEmpty ? existing.name : draft.name,
      firstMes: draft.firstMes.trim().isEmpty
          ? existing.firstMes
          : draft.firstMes,
      alternateGreetings: draft.alternateGreetings.isEmpty
          ? existing.alternateGreetings
          : draft.alternateGreetings,
      mesExample: draft.mesExample.trim().isEmpty
          ? existing.mesExample
          : draft.mesExample,
      avatarFileName: existing.avatarFileName,
      characterBook: existing.characterBook,
    );

    final changes = compareCharacterFields(existing, draft);
    if (changes.isEmpty) {
      _toast(context, 'World state matches the card — nothing to change.');
      return null;
    }

    final selected = await showAiFieldChangesSheet(
      context: context,
      title: 'Update ${existing.name} from world',
      subtitle:
          'Apply Living World arcs/relationships into this character card.',
      changes: changes,
      applyLabel: 'Update card',
    );
    if (selected == null || !context.mounted) return null;

    final merged = mergeCharacterChanges(existing, draft, selected);
    await characterService.upsert(merged);
    if (context.mounted) {
      _toast(context, 'Updated ${merged.name} from the Living World.');
    }
    return merged;
  }

  /// Solo chat with a linked character, already bound to [world.id].
  static Future<ChatSession?> startBoundChat({
    required BuildContext context,
    required LivingWorld world,
    required WorldPerson person,
    required CharacterService characterService,
    required PersonaService personaService,
    required ChatService chatService,
    required SettingsService settingsService,
    required NanoGptService nanoGptService,
  }) async {
    final cardId = person.characterCardId?.trim() ?? '';
    if (cardId.isEmpty) {
      _toast(context, 'Link or create a character for this person first.');
      return null;
    }

    final characters = await characterService.loadCharacters();
    Character? character;
    for (final c in characters) {
      if (c.id == cardId) {
        character = c;
        break;
      }
    }
    if (!context.mounted) return null;
    if (character == null) {
      _toast(context, 'Linked card $cardId is missing from Characters.');
      return null;
    }

    final persona = await Navigator.of(context).push<Persona>(
      MaterialPageRoute(
        builder: (_) => PersonasScreen(
          personaService: personaService,
          settingsService: settingsService,
          nanoGptService: nanoGptService,
          pickForChat: true,
        ),
      ),
    );
    if (persona == null || !context.mounted) return null;

    final greetingIndex = await pickGreetingIndex(
      context,
      character: character,
      userName: persona.name,
    );
    if (greetingIndex == null || !context.mounted) return null;

    final session = await chatService.startNewChat(
      character,
      userName: persona.name,
      personaId: persona.sessionId,
      greetingIndex: greetingIndex,
      worldId: world.id,
    );
    return session;
  }

  static void _showBusy(BuildContext context, String message) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(width: 20),
              Expanded(child: Text(message)),
            ],
          ),
        ),
      ),
    );
  }

  static void _toast(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
