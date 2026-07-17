import '../models/character.dart';

/// Builds NanoGPT prompt pieces from a SillyTavern-style card + user persona.
class PromptBuilder {
  const PromptBuilder();

  /// Default fallback system line when the card has no `system_prompt`.
  static const defaultSystemSeed =
      'Write {{char}}\'s next reply in a fictional chat between {{char}} and {{user}}.';

  /// Replace `{{user}}` / `{{char}}` (and common aliases) case-insensitively.
  String applyMacros(
    String input, {
    required String charName,
    required String userName,
  }) {
    var text = input;
    final replacements = <RegExp, String>{
      RegExp(r'\{\{user\}\}', caseSensitive: false): userName,
      RegExp(r'\{\{char\}\}', caseSensitive: false): charName,
      RegExp(r'<USER>', caseSensitive: false): userName,
      RegExp(r'<BOT>', caseSensitive: false): charName,
      RegExp(r'\{\{User\}\}'): userName,
      RegExp(r'\{\{Char\}\}'): charName,
    };
    replacements.forEach((pattern, value) {
      text = text.replaceAll(pattern, value);
    });
    return text;
  }

  /// System message assembled from card fields (description / personality / …).
  String buildSystemPrompt({
    required Character character,
    required String userName,
    String userPersona = '',
  }) {
    final charName = character.name.trim().isEmpty ? 'Character' : character.name.trim();
    final safeUser = userName.trim().isEmpty ? 'User' : userName.trim();

    final seed = character.systemPrompt.trim().isEmpty
        ? defaultSystemSeed
        : character.systemPrompt.trim().replaceAll(
              RegExp(r'\{\{original\}\}', caseSensitive: false),
              defaultSystemSeed,
            );

    final chunks = <String>[seed];

    if (character.description.trim().isNotEmpty) {
      chunks.add('Description:\n${character.description.trim()}');
    }
    if (character.personality.trim().isNotEmpty) {
      chunks.add('Personality:\n${character.personality.trim()}');
    }
    if (character.scenario.trim().isNotEmpty) {
      chunks.add('Scenario:\n${character.scenario.trim()}');
    }
    if (character.mesExample.trim().isNotEmpty) {
      chunks.add(
        'Example dialogue:\n${character.mesExample.trim()}',
      );
    }
    if (userPersona.trim().isNotEmpty) {
      chunks.add(
        'The user is $safeUser.\nPersona:\n${userPersona.trim()}',
      );
    } else {
      chunks.add('The user is called $safeUser.');
    }

    return applyMacros(
      chunks.join('\n\n'),
      charName: charName,
      userName: safeUser,
    );
  }

  String buildPostHistory({
    required Character character,
    required String userName,
  }) {
    final text = character.postHistoryInstructions.trim();
    if (text.isEmpty) return '';
    final charName = character.name.trim().isEmpty ? 'Character' : character.name.trim();
    final safeUser = userName.trim().isEmpty ? 'User' : userName.trim();
    return applyMacros(text, charName: charName, userName: safeUser);
  }

  String expandGreeting({
    required String greeting,
    required Character character,
    required String userName,
  }) {
    final charName = character.name.trim().isEmpty ? 'Character' : character.name.trim();
    final safeUser = userName.trim().isEmpty ? 'User' : userName.trim();
    return applyMacros(greeting, charName: charName, userName: safeUser);
  }
}
