import '../models/character.dart';
import 'chat_style_rules.dart';
import 'lorebook_service.dart';
import 'presence_service.dart';

/// How the next generation should behave (SillyTavern-style actions).
enum PromptMode {
  /// Normal reply as the character.
  normal,

  /// Keep going without a new user line.
  continueScene,

  /// Write the next line as the user (impersonate).
  impersonate,
}

/// Builds NanoGPT prompt pieces from a SillyTavern-style card + user persona.
class PromptBuilder {
  const PromptBuilder();

  static const _presence = PresenceService();
  static const _chatStyle = ChatStyleRules();

  /// Default fallback system line when the card has no `system_prompt`.
  static const defaultSystemSeed =
      'Write {{char}}\'s next reply in a fictional chat between {{char}} and {{user}}. '
      'Stay in FIRST PERSON as {{char}}: *actions* use I/my/me; speech in "quotes". '
      'Do not speak for {{user}}.';

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
  ///
  /// Optional [lore] injects keyword-triggered World Info before/after the
  /// character definition block (SillyTavern-style).
  ///
  /// [others] are extra group members (summaries only — keeps prompts small).
  String buildSystemPrompt({
    required Character character,
    required String userName,
    String userPersona = '',
    LorebookInjection lore = const LorebookInjection(),
    List<Character> others = const [],
    PromptMode mode = PromptMode.normal,
    String globalSystemPrompt = '',
  }) {
    final charName =
        character.name.trim().isEmpty ? 'Character' : character.name.trim();
    final safeUser = userName.trim().isEmpty ? 'User' : userName.trim();

    final impersonating = mode == PromptMode.impersonate;

    String seed;
    switch (mode) {
      case PromptMode.impersonate:
        seed =
            'Write {{user}}\'s next message in a fictional chat between {{char}} and {{user}}. '
            'You are writing ONLY as {{user}} (the player) — never as {{char}}. '
            'FIRST PERSON only: *actions* and thoughts use I/my/me '
            '(e.g. *I look at her*); speech in "double quotes". '
            'Do not write {{char}}\'s lines, narration, or reactions.';
      case PromptMode.continueScene:
        seed =
            'Continue the scene as {{char}}. Write {{char}}\'s next reply only. '
            'FIRST PERSON as {{char}}: *actions* use I/my/me, speech in "quotes". '
            'Do not speak for {{user}}.';
      case PromptMode.normal:
        seed = character.systemPrompt.trim().isEmpty
            ? defaultSystemSeed
            : character.systemPrompt.trim().replaceAll(
                  RegExp(r'\{\{original\}\}', caseSensitive: false),
                  defaultSystemSeed,
                );
    }

    final chunks = <String>[seed];

    if (others.isNotEmpty) {
      final names = others
          .map((c) => c.name.trim())
          .where((n) => n.isNotEmpty)
          .join(', ');
      if (impersonating) {
        chunks.add(
          'This is a group chat. Other people present: $names. '
          'Right now you are only writing as $safeUser (the player). '
          'Card summaries below are identity reference for people in the scene — '
          'not your voice. '
          'Do not start your reply with "$safeUser:" or your name — '
          'the app already labels who is speaking.',
        );
      } else {
        chunks.add(
          'This is a group chat. Other people present: $names. '
          'Right now you are only writing as $charName. '
          'Card summaries below are identity reference only — not what you know '
          'they did in scenes you missed. '
          'Do not start your reply with "$charName:" or your name — '
          'the app already labels who is speaking.',
        );
      }
      for (final other in others) {
        final summary = _shortCard(other);
        if (summary.isNotEmpty) {
          chunks.add('About ${other.name.trim()}:\n$summary');
        }
      }
    }

    if (lore.beforeChar.trim().isNotEmpty) {
      chunks.add('World info:\n${lore.beforeChar.trim()}');
    }

    if (character.description.trim().isNotEmpty) {
      chunks.add(
        impersonating
            ? 'About $charName (other person in the scene — not your voice):\n'
                '${character.description.trim()}'
            : 'Description:\n${character.description.trim()}',
      );
    }
    if (character.personality.trim().isNotEmpty) {
      chunks.add(
        impersonating
            ? '$charName\'s personality (reference only):\n'
                '${character.personality.trim()}'
            : 'Personality:\n${character.personality.trim()}',
      );
    }
    if (character.scenario.trim().isNotEmpty) {
      chunks.add('Scenario:\n${character.scenario.trim()}');
    }
    if (character.mesExample.trim().isNotEmpty && !impersonating) {
      chunks.add(
        'Example dialogue:\n${character.mesExample.trim()}',
      );
    }

    if (lore.afterChar.trim().isNotEmpty) {
      chunks.add('World info:\n${lore.afterChar.trim()}');
    }

    if (userPersona.trim().isNotEmpty) {
      chunks.add(
        impersonating
            ? 'You are $safeUser. Write in this persona\'s voice:\n'
                '${userPersona.trim()}'
            : 'The user is $safeUser.\nPersona:\n${userPersona.trim()}',
      );
    } else {
      chunks.add(
        impersonating
            ? 'You are writing as $safeUser.'
            : 'The user is called $safeUser.',
      );
    }

    final global = globalSystemPrompt.trim();
    if (global.isNotEmpty) {
      chunks.add(
        applyMacros(global, charName: charName, userName: safeUser),
      );
    }

    chunks.add(
      impersonating
          ? _presence.formatPlayerPerspectiveBoundary(
              charName: charName,
              userName: safeUser,
            )
          : _presence.formatKnowledgeBoundary(
              charName: charName,
              userName: safeUser,
            ),
    );

    return applyMacros(
      chunks.join('\n\n'),
      charName: charName,
      userName: safeUser,
    );
  }

  String buildPostHistory({
    required Character character,
    required String userName,
    String authorsNote = '',
    String globalPostHistory = '',
    PromptMode mode = PromptMode.normal,
  }) {
    final charName =
        character.name.trim().isEmpty ? 'Character' : character.name.trim();
    final safeUser = userName.trim().isEmpty ? 'User' : userName.trim();
    final speakerName =
        mode == PromptMode.impersonate ? safeUser : charName;
    final parts = <String>[];

    final global = globalPostHistory.trim();
    if (global.isNotEmpty) {
      parts.add(applyMacros(global, charName: charName, userName: safeUser));
    }

    // Card post-history is written for the AI character — skip it when the
    // model is drafting the player's line so it cannot pull voice back to {{char}}.
    final cardNote = character.postHistoryInstructions.trim();
    if (cardNote.isNotEmpty && mode != PromptMode.impersonate) {
      parts.add(applyMacros(cardNote, charName: charName, userName: safeUser));
    }

    final note = authorsNote.trim();
    if (note.isNotEmpty) {
      parts.add(
        applyMacros(
          'Author\'s note:\n$note',
          charName: charName,
          userName: safeUser,
        ),
      );
    }

    parts.add(
      _chatStyle.formatModernChatToneRule(
        charName: charName,
        userName: safeUser,
      ),
    );

    parts.add(
      _chatStyle.formatFirstPersonPerspectiveRule(speakerName: speakerName),
    );

    return parts.join('\n\n');
  }

  String expandGreeting({
    required String greeting,
    required Character character,
    required String userName,
  }) {
    final charName =
        character.name.trim().isEmpty ? 'Character' : character.name.trim();
    final safeUser = userName.trim().isEmpty ? 'User' : userName.trim();
    return applyMacros(greeting, charName: charName, userName: safeUser);
  }

  /// Short description + personality snippet for group prompts.
  String characterSummary(Character character) => _shortCard(character);

  String _shortCard(Character character) {
    final bits = <String>[
      if (character.description.trim().isNotEmpty) character.description.trim(),
      if (character.personality.trim().isNotEmpty) character.personality.trim(),
    ];
    if (bits.isEmpty) return '';
    final joined = bits.join(' ');
    if (joined.length <= 280) return joined;
    return '${joined.substring(0, 280)}…';
  }
}
