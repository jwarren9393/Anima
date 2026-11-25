import '../widgets/rp_rich_text.dart';

/// Wraps plain (non-asterisk) runs in `"dialogue"`. Leaves actions as-is.
String autoWrapDialogue(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return input;

  final segments = parseRpSegments(trimmed);
  if (segments.isEmpty) return trimmed;

  final hasPlainSpeech = segments.any(
    (segment) =>
        segment.kind == RpSegmentKind.plain && segment.text.trim().isNotEmpty,
  );
  if (!hasPlainSpeech) return trimmed;

  final buffer = StringBuffer();
  for (final segment in segments) {
    switch (segment.kind) {
      case RpSegmentKind.action:
        _appendSpaced(buffer, '*${segment.text.trim()}*');
      case RpSegmentKind.dialogue:
        _appendSpaced(buffer, '"${segment.text}"');
      case RpSegmentKind.plain:
        _appendPlain(buffer, segment.text);
    }
  }
  return buffer.toString().trim();
}

void _appendSpaced(StringBuffer buffer, String chunk) {
  if (chunk.trim().isEmpty) return;
  if (buffer.isNotEmpty && !buffer.toString().endsWith('\n')) {
    buffer.write(' ');
  }
  buffer.write(chunk);
}

void _appendPlain(StringBuffer buffer, String plain) {
  final lines = plain.split('\n');
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i].trim();
    if (line.isEmpty) {
      if (i < lines.length - 1 && buffer.isNotEmpty) buffer.writeln();
      continue;
    }
    final wrapped = _isAlreadyQuoted(line) ? line : '"$line"';
    if (buffer.isNotEmpty && !buffer.toString().endsWith('\n')) {
      buffer.write(' ');
    }
    buffer.write(wrapped);
    if (i < lines.length - 1) buffer.writeln();
  }
}

bool _isAlreadyQuoted(String text) {
  if (text.length < 2) return false;
  final first = text[0];
  final last = text[text.length - 1];
  return (first == '"' && last == '"') ||
      (first == '\u201C' && last == '\u201D');
}
