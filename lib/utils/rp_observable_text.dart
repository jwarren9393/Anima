import '../widgets/rp_rich_text.dart';

/// Text another character may witness from someone else's bubble.
///
/// In Anima, *asterisks* are normally **visible actions** other present
/// characters can see (shake hands, groan, walk upstairs). Only segments that
/// read like **private internal monologue** are stripped — spoken `"dialogue"`
/// and plain text are always kept.
String observableRpTextForOthers(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return trimmed;

  final segments = parseRpSegments(trimmed);
  if (segments.isEmpty) return trimmed;

  final buffer = StringBuffer();
  for (final segment in segments) {
    switch (segment.kind) {
      case RpSegmentKind.action:
        final action = segment.text.trim();
        if (action.isEmpty || isLikelyPrivateThought(action)) continue;
        if (buffer.isNotEmpty && !buffer.toString().endsWith('\n')) {
          buffer.write(' ');
        }
        buffer.write('*$action*');
      case RpSegmentKind.dialogue:
        final line = segment.text.trim();
        if (line.isEmpty) continue;
        if (buffer.isNotEmpty && !buffer.toString().endsWith('\n')) {
          buffer.write(' ');
        }
        buffer.write('"$line"');
      case RpSegmentKind.plain:
        final line = segment.text.trim();
        if (line.isEmpty) continue;
        if (buffer.isNotEmpty && !buffer.toString().endsWith('\n')) {
          buffer.write(' ');
        }
        buffer.write(line);
    }
  }

  final result = buffer.toString().trim();
  if (result.isNotEmpty) return result;

  return '[No audible words or visible actions witnessed.]';
}

/// True when an *asterisk* block reads like internal monologue, not a visible
/// beat others in the room could see.
bool isLikelyPrivateThought(String actionText) {
  final lower = actionText.trim().toLowerCase();
  if (lower.isEmpty) return true;

  // Interaction with another person → visible action.
  if (_referencesOtherPerson(lower)) return false;

  return _matchesInternalMonologue(lower);
}

bool _referencesOtherPerson(String lower) {
  const pronouns = [
    r'\byou\b',
    r'\byour\b',
    r'\byours\b',
    r'\bhe\b',
    r'\bhim\b',
    r'\bhis\b',
    r'\bshe\b',
    r'\bher\b',
    r'\bthey\b',
    r'\bthem\b',
    r'\btheir\b',
  ];
  for (final pattern in pronouns) {
    if (RegExp(pattern).hasMatch(lower)) return true;
  }
  return false;
}

bool _matchesInternalMonologue(String lower) {
  const patterns = [
    r"can'?t believe",
    r'cannot believe',
    r'\boh god\b',
    r'\boh fuck\b',
    r'\boh shit\b',
    r'\bgod[,.]',
    r'\bwhat did i\b',
    r'\bwhy did i\b',
    r'\bhow could i\b',
    r'\bi hope\b',
    r'\bhope (?:he|she|they) don',
    r'\bmy (?:hands|heart|stomach|mind|chest|throat|legs)\b',
    r'\b(?:shake|shaking|shook|race|racing|races|pound|pounding|sink|sinking|spin|spinning)\b',
    r'\bto myself\b',
    r'\bin my (?:head|mind)\b',
    r'\bmentally\b',
    r'\binternally\b',
    r'\bif only\b',
    r'\bwish i hadn',
    r'\bso (?:ashamed|guilty|stupid|fucked)\b',
    r"\bplease don'?t let\b",
    r"\bdon'?t let (?:him|her|them) know\b",
    r"\bthey can'?t know\b",
    r'\bno one can know\b',
    r'\bsecret\b',
  ];
  for (final pattern in patterns) {
    if (RegExp(pattern).hasMatch(lower)) return true;
  }
  return false;
}
