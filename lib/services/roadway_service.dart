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

  /// Paths need enough room for ~6 short options without tail repetition.
  static const generateMaxTokens = 720;

  /// Tighter sampling — variety via prompt, not high temperature loops.
  static SamplingSettings generateSampling(SamplingSettings base) {
    final capped = base.maxTokens == null || base.maxTokens! > generateMaxTokens
        ? generateMaxTokens
        : base.maxTokens!;
    return base.copyWith(
      temperature: base.temperature > 0.72 ? 0.72 : base.temperature,
      maxTokens: capped,
      frequencyPenalty: base.frequencyPenalty < 0.35 ? 0.45 : base.frequencyPenalty,
      presencePenalty: base.presencePenalty < 0.15 ? 0.2 : base.presencePenalty,
      repetitionPenalty: base.repetitionPenalty ?? 1.1,
    );
  }

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
        'You brainstorm short next-message ideas for the human player in a '
        'private roleplay chat.',
      )
      ..writeln()
      ..writeln('Roadway note:')
      ..writeln(guidance)
      ..writeln()
      ..writeln('Write exactly $count numbered options (1. 2. 3. …).')
      ..writeln(
        'Each option is what the player could paste as their next message — '
        'FIRST PERSON only: speech in "quotes" with I/you; actions in '
        '*asterisks* with I/my/me (e.g. *I look at her*). Never use the '
        "player's name inside an option body.",
      )
      ..writeln('Do not write as the character. Do not continue the AI reply.')
      ..writeln(
        'Each option must be a different beat — no repeated sentences, '
        'phrases, or near-duplicates.',
      )
      ..writeln('Output only the numbered list — no title or commentary.');

    final user = StringBuffer()
      ..writeln('Player ($userName) is {{user}}. Character is {{char}} ($characterName).')
      ..writeln()
      ..writeln('Recent chat (newest last):')
      ..writeln(
        _recentContext(recentMessages, userName: userName, characterName: characterName),
      )
      ..writeln()
      ..writeln(
        'Generate $count numbered first-person options for {{user}}’s next message.',
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
        'You draft the player’s next roleplay message by combining ideas they '
        'already liked.',
      )
      ..writeln()
      ..writeln('Roadway note:')
      ..writeln(guidance)
      ..writeln()
      ..writeln(
        'Write ONE cohesive first-person message for {{user}} — speech in '
        '"quotes" with I/you; actions in *asterisks* with I/my/me. Never use '
        "the player's name inside *actions*.",
      )
      ..writeln(
        'Weave the selected ideas together; do not list them separately.',
      )
      ..writeln('Do not write as the character. Do not continue the AI reply.')
      ..writeln('Output only the final message text — no numbering or commentary.');

    final user = StringBuffer()
      ..writeln('Player ($userName) is {{user}}. Character is {{char}} ($characterName).')
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
  String parseCombinedMessage(String raw, {String userName = ''}) {
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
    final options = parseOptions(text, max: 12, userName: userName);
    if (options.length >= 2) {
      return normalizeUserPerspective(options.join(' '), userName: userName);
    }
    return normalizeUserPerspective(text, userName: userName);
  }

  String _formatSelectedOptions(List<String> options) {
    final buf = StringBuffer();
    for (var i = 0; i < options.length; i++) {
      buf.writeln('${i + 1}. ${options[i]}');
    }
    return buf.toString().trim();
  }

  /// Pulls numbered / bulleted lines into clean option strings.
  List<String> parseOptions(
    String raw, {
    int max = defaultOptionCount,
    String userName = '',
  }) {
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
      text = normalizeUserPerspective(text, userName: userName);
      options.add(text);
      if (options.length >= max) break;
    }

    if (options.isNotEmpty) return dedupeOptions(options);

    // Fallback: split on blank lines if the model ignored numbering.
    final blocks = raw
        .split(RegExp(r'\n\s*\n'))
        .map((b) => b.trim())
        .where((b) => b.isNotEmpty)
        .toList();
    for (final block in blocks) {
      final cleaned = normalizeUserPerspective(
        block.replaceAll(RegExp(r'\s+'), ' ').trim(),
        userName: userName,
      );
      if (cleaned.isEmpty) continue;
      options.add(cleaned);
      if (options.length >= max) break;
    }
    return dedupeOptions(options);
  }

  /// Fixes common third-person leaks (*Trey looks…*) in player path options.
  String normalizeUserPerspective(String text, {required String userName}) {
    var out = text.trim();
    if (out.isEmpty) return out;
    final name = userName.trim();
    if (name.isEmpty) return out;

    final escaped = RegExp.escape(name);
    out = out.replaceAllMapped(
      RegExp('\\*$escaped\\s+', caseSensitive: false),
      (_) => '*I ',
    );
    out = out.replaceAllMapped(
      RegExp('\\*$escaped\'s\\s+', caseSensitive: false),
      (_) => '*my ',
    );
    out = out.replaceAllMapped(
      RegExp('\\*$escaped\\b', caseSensitive: false),
      (_) => '*I',
    );
    return out.trim();
  }

  /// Drops exact and near-duplicate path lines from model output.
  List<String> dedupeOptions(List<String> options) {
    final seen = <String>{};
    final out = <String>[];
    for (final option in options) {
      final key = _normalizeForDedupe(option);
      if (key.isEmpty) continue;
      if (seen.contains(key)) continue;
      seen.add(key);
      out.add(option);
    }
    return out;
  }

  String _normalizeForDedupe(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
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
          ? 'You'
          : (m.speakerName?.trim().isNotEmpty == true
              ? m.speakerName!.trim()
              : characterName);
      final role = m.isUser ? 'player' : 'assistant';
      buf.writeln('$name ($role): $text');
    }
    final out = buf.toString().trim();
    return out.isEmpty ? '(no messages yet)' : out;
  }
}
