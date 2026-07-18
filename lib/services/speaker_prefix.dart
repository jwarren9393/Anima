/// Strips a leading "SpeakerName:" style label from AI reply text.
///
/// Group chats already show the speaker on the bubble; models often copy the
/// `Name: …` history format and put the name in the body too.
String stripLeadingSpeakerPrefix(String text, String? speakerName) {
  final name = speakerName?.trim() ?? '';
  if (name.isEmpty || text.isEmpty) return text;

  final escaped = RegExp.escape(name);
  // More specific wrappers first (e.g. **Name:**), then plain Name:
  final pattern = RegExp(
    '^\\s*(?:'
    '(?:\\*{1,2}|_{1,2})$escaped\\s*[:：\\-–—](?:\\*{1,2}|_{1,2})\\s*'
    '|'
    '(?:\\*{1,2}|_{1,2})?$escaped(?:\\*{1,2}|_{1,2})?\\s*[:：\\-–—]\\s*'
    ')',
    caseSensitive: false,
  );
  final stripped = text.replaceFirst(pattern, '');
  return stripped.isEmpty ? text : stripped;
}
