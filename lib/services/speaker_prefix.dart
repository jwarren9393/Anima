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
  if (stripped.isEmpty) {
    // During streaming the model often sends "Name:" before the body — hide
    // the label until real reply text arrives (bubble already shows the name).
    if (pattern.hasMatch(text)) return '';
    return text;
  }
  return stripped;
}

/// Strips a leading `Name:` label from any cast member (group chats).
String stripLeadingCastPrefix(String text, Iterable<String> castNames) {
  for (final name in castNames) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) continue;
    final stripped = stripLeadingSpeakerPrefix(text, trimmed);
    if (stripped != text) return stripped;
  }
  return text;
}
