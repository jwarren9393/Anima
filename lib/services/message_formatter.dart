import '../models/chat_message.dart';
import 'settings_service.dart';

/// Builds a one-shot NanoGPT request to lightly format a composer draft.
///
/// Fixes caps/punctuation and adds `*actions*` / `"dialogue"` — does not reword.
class MessageFormatter {
  const MessageFormatter();

  /// Recent chat lines only as markup examples (newest last). Keep tiny on phone.
  List<Map<String, String>> buildMessages({
    required String draft,
    required String userName,
    required String characterName,
    List<ChatMessage> recentMessages = const [],
    String formatNote = CollaboratorSettings.defaultComposerFormatNote,
  }) {
    final guidance = formatNote.trim().isEmpty
        ? CollaboratorSettings.defaultComposerFormatNote
        : formatNote.trim();

    final system = StringBuffer()
      ..writeln(
        'You are a light formatter for roleplay chat drafts in Anima.',
      )
      ..writeln()
      ..writeln('Composer format note (follow closely):')
      ..writeln(guidance)
      ..writeln()
      ..writeln('Hard rules:')
      ..writeln(
        '- Do NOT reword, paraphrase, expand, shorten, or “improve” the draft.',
      )
      ..writeln(
        '- Keep the user’s words and word order. Only fix capitalization and '
        'punctuation, and add *asterisks* / "quotes" where needed.',
      )
      ..writeln(
        '- Put actions, gestures, narration, and thoughts in *asterisks*.',
      )
      ..writeln('- Put spoken words in double quotes "like this".')
      ..writeln(
        '- If the draft is already well marked up, only fix small typos/caps.',
      )
      ..writeln(
        '- Do not write {{char}}\'s reply. Do not add new plot beats.',
      )
      ..writeln(
        '- Output ONLY the formatted message — no labels, no markdown fences, '
        'no “here is…”.',
      );

    final user = StringBuffer()
      ..writeln('{{user}} name: $userName')
      ..writeln('{{char}} name: $characterName')
      ..writeln();

    final context = _recentContext(recentMessages, userName: userName);
    if (context.isNotEmpty) {
      user.writeln(
        'Recent chat (markup examples only — do not copy their wording '
        'into the draft):',
      );
      user.writeln(context);
      user.writeln();
    }

    user.writeln('Draft to format (preserve wording):');
    user.writeln(draft.trim());

    return [
      {'role': 'system', 'content': system.toString().trim()},
      {'role': 'user', 'content': user.toString().trim()},
    ];
  }

  String _recentContext(
    List<ChatMessage> messages, {
    required String userName,
    int maxMessages = 4,
  }) {
    if (messages.isEmpty) return '';
    final start =
        messages.length > maxMessages ? messages.length - maxMessages : 0;
    final lines = <String>[];
    for (var i = start; i < messages.length; i++) {
      final m = messages[i];
      final text = m.text.trim();
      if (text.isEmpty) continue;
      final who = m.isUser
          ? userName
          : (m.speakerName?.trim().isNotEmpty == true
              ? m.speakerName!.trim()
              : 'Character');
      final clipped = text.length > 180 ? '${text.substring(0, 180)}…' : text;
      lines.add('$who: $clipped');
    }
    return lines.join('\n');
  }
}
