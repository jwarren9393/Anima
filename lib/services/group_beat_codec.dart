import 'dart:convert';

import '../models/group_beat_part.dart';

/// Flatten / prompt formatting and swipe JSON for group-beat messages.
class GroupBeatCodec {
  const GroupBeatCodec();

  static String flatten(List<GroupBeatPart> lines) {
    final out = <String>[];
    for (final line in lines) {
      final name = line.speakerName.trim();
      final text = line.text.trim();
      if (name.isEmpty || text.isEmpty) continue;
      out.add('$name: $text');
    }
    return out.join('\n');
  }

  static String formatForPrompt(List<GroupBeatPart> lines) {
    final body = flatten(lines);
    if (body.isEmpty) return '';
    return 'Group moment (simultaneous reactions):\n$body';
  }

  static String encodeSwipe(List<GroupBeatPart> lines) {
    return jsonEncode(lines.map((l) => l.toJson()).toList());
  }

  static List<GroupBeatPart> decodeSwipe(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return const [];
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is! List) return const [];
      return decoded
          .map((e) => GroupBeatPart.fromJson(Map<String, dynamic>.from(e as Map)))
          .where((p) => p.text.trim().isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  static List<List<GroupBeatPart>> decodeAllSwipes(List<String> swipes) {
    return swipes.map(decodeSwipe).where((s) => s.isNotEmpty).toList();
  }

  static List<String> encodeAllSwipes(List<List<GroupBeatPart>> variants) {
    return variants.map(encodeSwipe).toList(growable: false);
  }
}
