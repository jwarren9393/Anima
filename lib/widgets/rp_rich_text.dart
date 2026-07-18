import 'package:flutter/material.dart';

import '../models/ui_style_settings.dart';

/// Kind of RP markup segment.
enum RpSegmentKind {
  /// Unmarked leftover text.
  plain,

  /// Inside *asterisks* — action / narration / thoughts.
  action,

  /// Inside "double quotes" — spoken dialogue.
  dialogue,
}

class RpSegment {
  const RpSegment(this.kind, this.text);

  final RpSegmentKind kind;
  final String text;
}

/// Splits SillyTavern-style RP text into action / dialogue / plain runs.
List<RpSegment> parseRpSegments(String input) {
  if (input.isEmpty) return const [];

  final segments = <RpSegment>[];
  final buffer = StringBuffer();
  var i = 0;

  void flushPlain() {
    if (buffer.isEmpty) return;
    segments.add(RpSegment(RpSegmentKind.plain, buffer.toString()));
    buffer.clear();
  }

  while (i < input.length) {
    final ch = input[i];

    if (ch == '*') {
      final end = input.indexOf('*', i + 1);
      if (end != -1) {
        flushPlain();
        segments.add(
          RpSegment(RpSegmentKind.action, input.substring(i + 1, end)),
        );
        i = end + 1;
        continue;
      }
    }

    if (ch == '"' || ch == '\u201C') {
      final closer = ch == '\u201C' ? '\u201D' : '"';
      final end = input.indexOf(closer, i + 1);
      if (end != -1) {
        flushPlain();
        segments.add(
          RpSegment(RpSegmentKind.dialogue, input.substring(i + 1, end)),
        );
        i = end + 1;
        continue;
      }
    }

    buffer.write(ch);
    i++;
  }

  flushPlain();
  return segments;
}

/// Renders RP text with clear visual difference between dialogue and actions.
class RpRichText extends StatelessWidget {
  const RpRichText({
    super.key,
    required this.text,
    required this.baseStyle,
    this.isUser = false,
  });

  final String text;
  final TextStyle baseStyle;
  final bool isUser;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ui = AnimaUiTheme.of(context);
    final segments = parseRpSegments(text);
    if (segments.isEmpty) {
      return Text(text, style: baseStyle);
    }

    // Dialogue: bright, solid. Actions: softer italic. Plain: in between.
    final dialogueColor = baseStyle.color ?? scheme.onSurface;
    final actionColor = isUser
        ? (baseStyle.color ?? ui.userBubbleForeground).withValues(alpha: 0.78)
        : ui.actionColor.withValues(alpha: 0.9);
    final plainColor = isUser
        ? (baseStyle.color ?? ui.userBubbleForeground).withValues(alpha: 0.92)
        : scheme.onSurfaceVariant;

    final spans = <InlineSpan>[];
    for (final segment in segments) {
      if (segment.text.isEmpty) continue;
      switch (segment.kind) {
        case RpSegmentKind.action:
          spans.add(
            TextSpan(
              text: '*${segment.text}*',
              style: baseStyle.copyWith(
                color: actionColor,
                fontStyle: FontStyle.italic,
                fontWeight: FontWeight.w500,
              ),
            ),
          );
        case RpSegmentKind.dialogue:
          spans.add(
            TextSpan(
              text: '"${segment.text}"',
              style: baseStyle.copyWith(
                color: dialogueColor,
                fontStyle: FontStyle.normal,
                fontWeight: FontWeight.w600,
              ),
            ),
          );
        case RpSegmentKind.plain:
          spans.add(
            TextSpan(
              text: segment.text,
              style: baseStyle.copyWith(
                color: plainColor,
                fontStyle: FontStyle.normal,
                fontWeight: FontWeight.w400,
              ),
            ),
          );
      }
    }

    return Text.rich(TextSpan(children: spans));
  }
}
