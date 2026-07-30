import '../models/chat_message.dart';
import 'settings_service.dart';

/// Builds prompts for the universal chat Narrator and formats narrator lines
/// for the roleplay API payload.
class NarratorService {
  const NarratorService();

  static const defaultNote = CollaboratorSettings.defaultNarratorNote;

  /// How narrator lines appear in the live prompt (chronological history).
  String formatForPrompt({
    required String text,
    required String userName,
    required String charName,
  }) {
    final body = text.trim();
    if (body.isEmpty) return '';
    final user = userName.trim().isEmpty ? 'User' : userName.trim();
    final char = charName.trim().isEmpty ? 'Character' : charName.trim();
    return '''
Narrator (omniscient scene voice — not $user or $char speaking):
$body

This is established scene truth and direction. Characters and $user react to it.
Do not attribute this line to $user or $char in dialogue. Do not repeat it verbatim.
'''.trim();
  }

  List<Map<String, String>> buildGenerateMessages({
    required String userName,
    required String characterName,
    required List<ChatMessage> recentMessages,
    String narratorNote = defaultNote,
    String nudge = '',
    String existingDraft = '',
    bool isGroup = false,
    List<String> otherCharacterNames = const [],
  }) {
    final guidance =
        narratorNote.trim().isEmpty ? defaultNote : narratorNote.trim();
    final draft = existingDraft.trim();
    final steer = nudge.trim();

    final system = StringBuffer()
      ..writeln(
        'You write narrator lines for a private roleplay chat app (Anima).',
      )
      ..writeln()
      ..writeln('Narrator note (follow closely):')
      ..writeln(guidance)
      ..writeln()
      ..writeln('Hard rules:')
      ..writeln(
        '- Output ONE narrator passage only — omniscient third-person prose.',
      )
      ..writeln(
        '- You may use *actions* and sensory detail. No character dialogue '
        'unless a brief quoted sound in-scene is essential.',
      )
      ..writeln(
        '- Do NOT write as {{user}} or {{char}}. Do NOT use "I" for a player '
        'or character voice.',
      )
      ..writeln(
        '- Ground the line in recent chat; advance or steer the scene when asked.',
      )
      ..writeln('- No titles, labels, markdown fences, or meta commentary.')
      ..writeln('- Output only the narrator text.');

    final user = StringBuffer()
      ..writeln('{{user}} name: $userName')
      ..writeln('{{char}} name: $characterName');
    if (isGroup && otherCharacterNames.isNotEmpty) {
      user.writeln('Also present: ${otherCharacterNames.join(', ')}');
    }
    user.writeln();
    user.writeln('Recent chat (newest last):');
    user.writeln(
      _recentContext(
        recentMessages,
        userName: userName,
        characterName: characterName,
      ),
    );
    user.writeln();
    if (draft.isNotEmpty) {
      user.writeln('Current narrator draft (revise or replace as directed):');
      user.writeln(draft);
      user.writeln();
    }
    if (steer.isNotEmpty) {
      user.writeln('Steer / nudge from the player:');
      user.writeln(steer);
      user.writeln();
    }
    if (draft.isNotEmpty && steer.isNotEmpty) {
      user.writeln(
        'Revise the draft following the nudge. Keep what still fits the scene.',
      );
    } else if (draft.isNotEmpty) {
      user.writeln(
        'Polish the draft: clearer prose, same facts unless the scene demands a fix.',
      );
    } else if (steer.isNotEmpty) {
      user.writeln(
        'Write a new narrator line that follows the nudge and fits the scene.',
      );
    } else {
      user.writeln(
        'Write the next narrator line: contextualize the moment and gently '
        'advance the scene.',
      );
    }

    return [
      {'role': 'system', 'content': system.toString().trim()},
      {'role': 'user', 'content': user.toString().trim()},
    ];
  }

  static String _recentContext(
    List<ChatMessage> messages, {
    required String userName,
    required String characterName,
  }) {
    final recent = messages.where((m) => m.text.trim().isNotEmpty).toList();
    final start = recent.length > 14 ? recent.length - 14 : 0;
    final buffer = StringBuffer();
    for (final message in recent.sublist(start)) {
      final text = message.text.trim();
      if (text.isEmpty) continue;
      if (message.isNarrator) {
        buffer.writeln('Narrator: $text');
      } else if (message.isUser) {
        buffer.writeln('$userName: $text');
      } else {
        final who = message.speakerName?.trim().isNotEmpty == true
            ? message.speakerName!.trim()
            : characterName;
        buffer.writeln('$who: $text');
      }
      buffer.writeln();
    }
    return buffer.toString().trim();
  }
}
