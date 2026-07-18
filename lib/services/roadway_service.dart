import '../models/chat_message.dart';
import 'settings_service.dart';

/// Builds NanoGPT prompts for Roadway-style “what next?” path suggestions.
///
/// Inspired by SillyTavern-Roadway: brainstorm short player options from recent
/// chat, then let the user tap one into the composer and edit before sending.
class RoadwayService {
  const RoadwayService();

  static const defaultNote = CollaboratorSettings.defaultRoadwayNote;

  /// How many path tiles to aim for on a phone.
  static const defaultOptionCount = 6;

  List<Map<String, String>> buildMessages({
    required String userName,
    required String characterName,
    required List<ChatMessage> recentMessages,
    String roadwayNote = defaultNote,
    int optionCount = defaultOptionCount,
  }) {
    final guidance =
        roadwayNote.trim().isEmpty ? defaultNote : roadwayNote.trim();
    final count = optionCount.clamp(3, 9);

    final system = StringBuffer()
      ..writeln(
        'You help the player choose their next move in a private roleplay.',
      )
      ..writeln()
      ..writeln('Roadway note (follow closely):')
      ..writeln(guidance)
      ..writeln()
      ..writeln('Hard rules:')
      ..writeln('- Write exactly $count options.')
      ..writeln('- Use a plain numbered list: 1. … 2. … (no markdown fences).')
      ..writeln(
        '- Each option is one or two short sentences the player could send '
        'as {{user}} (actions in *asterisks*, speech in "quotes" when useful).',
      )
      ..writeln('- Do NOT write as {{char}}. Do NOT continue the AI reply.')
      ..writeln('- Do NOT add titles, preamble, or commentary outside the list.')
      ..writeln('- Options must be concrete and different from each other.');

    final user = StringBuffer()
      ..writeln('{{user}} name: $userName')
      ..writeln('{{char}} name: $characterName')
      ..writeln()
      ..writeln('Recent chat (newest last):')
      ..writeln(
        _recentContext(recentMessages, userName: userName, characterName: characterName),
      )
      ..writeln()
      ..writeln(
        'Generate $count numbered options for {{user}}’s next message.',
      );

    return [
      {'role': 'system', 'content': system.toString().trim()},
      {'role': 'user', 'content': user.toString().trim()},
    ];
  }

  /// Builds a prompt that merges several selected Paths into one {{user}} message.
  ///
  /// Returns an empty list when fewer than two non-empty selections are provided.
  List<Map<String, String>> buildCombineMessages({
    required String userName,
    required String characterName,
    required List<ChatMessage> recentMessages,
    required List<String> selectedOptions,
    String roadwayNote = defaultNote,
  }) {
    final cleaned = selectedOptions
        .map((o) => o.trim())
        .where((o) => o.isNotEmpty)
        .toList(growable: false);
    if (cleaned.length < 2) return const [];

    final guidance =
        roadwayNote.trim().isEmpty ? defaultNote : roadwayNote.trim();

    final system = StringBuffer()
      ..writeln(
        'You help the player draft their next roleplay message by combining '
        'ideas they already liked.',
      )
      ..writeln()
      ..writeln('Roadway note (follow closely):')
      ..writeln(guidance)
      ..writeln()
      ..writeln('Hard rules:')
      ..writeln(
        '- Write ONE cohesive message the player could send as {{user}}.',
      )
      ..writeln(
        '- Weave together the selected path ideas; keep the best beats from '
        'each without listing them separately.',
      )
      ..writeln(
        '- Use *asterisks* for actions and "quotes" for speech when useful.',
      )
      ..writeln('- Do NOT write as {{char}}. Do NOT continue the AI reply.')
      ..writeln(
        '- Do NOT add titles, numbering, bullet lists, preamble, or commentary.',
      )
      ..writeln('- Output only the final message text.');

    final user = StringBuffer()
      ..writeln('{{user}} name: $userName')
      ..writeln('{{char}} name: $characterName')
      ..writeln()
      ..writeln('Recent chat (newest last):')
      ..writeln(
        _recentContext(
          recentMessages,
          userName: userName,
          characterName: characterName,
        ),
      )
      ..writeln()
      ..writeln('Selected path ideas to combine:')
      ..writeln(_formatSelectedOptions(cleaned))
      ..writeln()
      ..writeln(
        'Combine those selected ideas into one natural {{user}} message.',
      );

    return [
      {'role': 'system', 'content': system.toString().trim()},
      {'role': 'user', 'content': user.toString().trim()},
    ];
  }

  /// Cleans a combine-mode completion into a single composer-ready string.
  String parseCombinedMessage(String raw) {
    var text = raw.replaceAll('\r\n', '\n').trim();
    if (text.isEmpty) return '';

    // Drop common wrappers / fences the model sometimes adds.
    if (text.startsWith('```') && text.endsWith('```')) {
      final lines = text.split('\n');
      if (lines.length >= 2) {
        text = lines.sublist(1, lines.length - 1).join('\n').trim();
      }
    }
    if ((text.startsWith('"') && text.endsWith('"')) ||
        (text.startsWith('“') && text.endsWith('”'))) {
      text = text.substring(1, text.length - 1).trim();
    }

    // If the model ignored instructions and returned a numbered list, join
    // the option bodies into one paragraph instead of dumping the numbers.
    final options = parseOptions(text, max: 12);
    if (options.length >= 2) {
      return options.join(' ').trim();
    }
    return text;
  }

  String _formatSelectedOptions(List<String> options) {
    final buf = StringBuffer();
    for (var i = 0; i < options.length; i++) {
      buf.writeln('${i + 1}. ${options[i]}');
    }
    return buf.toString().trim();
  }

  /// Pulls numbered / bulleted lines into clean option strings.
  List<String> parseOptions(String raw, {int max = defaultOptionCount}) {
    final lines = raw.replaceAll('\r\n', '\n').split('\n');
    final options = <String>[];
    final bullet = RegExp(
      r'^\s*(?:(?:\d+)[.)\-:]|[-*•])\s+(.+)$',
    );

    for (final line in lines) {
      final match = bullet.firstMatch(line);
      if (match == null) continue;
      var text = (match.group(1) ?? '').trim();
      // Strip wrapping quotes the model sometimes adds around the whole option.
      if ((text.startsWith('"') && text.endsWith('"')) ||
          (text.startsWith('“') && text.endsWith('”'))) {
        text = text.substring(1, text.length - 1).trim();
      }
      if (text.isEmpty) continue;
      options.add(text);
      if (options.length >= max) break;
    }

    if (options.isNotEmpty) return options;

    // Fallback: split on blank lines if the model ignored numbering.
    final blocks = raw
        .split(RegExp(r'\n\s*\n'))
        .map((b) => b.trim())
        .where((b) => b.isNotEmpty)
        .toList();
    for (final block in blocks) {
      final cleaned = block.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (cleaned.isEmpty) continue;
      options.add(cleaned);
      if (options.length >= max) break;
    }
    return options;
  }

  String _recentContext(
    List<ChatMessage> messages, {
    required String userName,
    required String characterName,
    int maxMessages = 8,
  }) {
    if (messages.isEmpty) return '(no messages yet)';
    final start =
        messages.length > maxMessages ? messages.length - maxMessages : 0;
    final buf = StringBuffer();
    for (var i = start; i < messages.length; i++) {
      final m = messages[i];
      final text = m.text.trim();
      if (text.isEmpty) continue;
      final name = m.isUser
          ? userName
          : (m.speakerName?.trim().isNotEmpty == true
              ? m.speakerName!.trim()
              : characterName);
      final role = m.isUser ? 'user' : 'assistant';
      buf.writeln('$name ($role): $text');
    }
    final out = buf.toString().trim();
    return out.isEmpty ? '(no messages yet)' : out;
  }
}
