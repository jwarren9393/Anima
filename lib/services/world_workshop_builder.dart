import 'dart:convert';

import '../models/chat_message.dart';
import '../models/lorebook.dart';
import 'settings_service.dart';

/// Builds prompts and parses lorebooks for the Creation Center.
class WorldWorkshopBuilder {
  const WorldWorkshopBuilder();

  /// System prompt for the ongoing workshop chat (questions + brainstorming).
  String chatSystemPrompt({
    String guidanceNote = CollaboratorSettings.defaultGuidanceNote,
  }) {
    final guidance = guidanceNote.trim().isEmpty
        ? CollaboratorSettings.defaultGuidanceNote
        : guidanceNote.trim();

    return '''
You are Anima's World Info collaborator. You help the user invent a setting,
factions, places, magic, history, and lore for a private roleplay app.

Your job in this chat:
- Ask clear follow-up questions when useful.
- Suggest ideas, but let the user steer.
- Keep track of what they decide.
- Do NOT dump a finished lorebook JSON unless they explicitly ask for a draft
  preview in chat. The app has a separate "Create lorebook" button that will
  ask you for JSON later.

Guidance note (follow closely):
$guidance

Keep replies conversational and useful on a phone — not huge walls of text
unless the user asks for depth.
'''.trim();
  }

  /// Messages for the final “turn this chat into a lorebook” NanoGPT call.
  List<Map<String, String>> buildExportMessages({
    required List<ChatMessage> conversation,
    String guidanceNote = CollaboratorSettings.defaultGuidanceNote,
  }) {
    final guidance = guidanceNote.trim().isEmpty
        ? CollaboratorSettings.defaultGuidanceNote
        : guidanceNote.trim();

    final transcript = StringBuffer();
    for (final message in conversation) {
      final who = message.isUser ? 'User' : 'Assistant';
      transcript.writeln('$who: ${message.text.trim()}');
      transcript.writeln();
    }

    final system = '''
You convert a world-building conversation into one SillyTavern-compatible
World Info lorebook JSON object for the Anima app.

Guidance note (follow closely):
$guidance

Output rules:
- Reply with ONLY a single JSON object. No markdown fences. No preamble.
- Shape:
{
  "name": "short book title",
  "description": "one-line summary",
  "scan_depth": 4,
  "token_budget": 512,
  "recursive_scanning": false,
  "entries": [
    {
      "name": "optional label",
      "keys": ["keyword", "alias"],
      "secondary_keys": [],
      "content": "lore text injected when keys match",
      "enabled": true,
      "constant": false,
      "selective": false,
      "insertion_order": 100,
      "priority": 10,
      "case_sensitive": false,
      "position": "before_char",
      "comment": ""
    }
  ]
}
- Create useful keyword entries (places, people, factions, rules, items).
- Prefer several focused entries over one giant dump.
- Use "constant": true only for a short always-on overview if helpful.
- keys should be words/phrases that would appear in chat to trigger the entry.
- content should be raw lore text (not JSON). Do not sanitize or moralize.
'''.trim();

    final user = '''
Turn this workshop conversation into one lorebook JSON object:

${transcript.toString().trim()}
'''.trim();

    return [
      {'role': 'system', 'content': system},
      {'role': 'user', 'content': user},
    ];
  }

  /// Parse model output into a [Lorebook]. Throws [FormatException] on failure.
  Lorebook parseLorebookJson(String raw) {
    final map = _extractJsonObject(raw);
    final book = Lorebook.fromJson(map);
    if (book.entries.isEmpty) {
      throw const FormatException(
        'The AI returned a lorebook with no entries. Try chatting a bit more, then Create again.',
      );
    }
    if (book.name.trim().isEmpty) {
      return book.copyWith(name: 'Workshop lorebook');
    }
    return book;
  }

  /// Guess a short workshop title from the first user message.
  String suggestTitle(List<ChatMessage> messages, {String fallback = 'New workshop'}) {
    for (final message in messages) {
      if (!message.isUser) continue;
      final text = message.text.trim();
      if (text.isEmpty) continue;
      final firstLine = text.split('\n').first.trim();
      if (firstLine.length <= 48) return firstLine;
      return '${firstLine.substring(0, 45).trimRight()}…';
    }
    return fallback;
  }

  Map<String, dynamic> _extractJsonObject(String raw) {
    var text = raw.trim();
    if (text.isEmpty) {
      throw const FormatException('The AI returned an empty lorebook.');
    }

    // Strip ```json ... ``` if the model ignores instructions.
    final fence = RegExp(
      r'```(?:json)?\s*([\s\S]*?)```',
      caseSensitive: false,
    );
    final fenceMatch = fence.firstMatch(text);
    if (fenceMatch != null) {
      text = fenceMatch.group(1)!.trim();
    }

    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start < 0 || end <= start) {
      throw const FormatException(
        'Could not find lorebook JSON in the AI reply. Try Create lorebook again.',
      );
    }

    final slice = text.substring(start, end + 1);
    final decoded = jsonDecode(slice);
    if (decoded is! Map) {
      throw const FormatException('Lorebook JSON must be an object.');
    }
    return Map<String, dynamic>.from(decoded);
  }
}
