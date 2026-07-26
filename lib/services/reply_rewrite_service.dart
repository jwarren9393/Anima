import '../models/chat_message.dart';

/// How to steer a regeneration / new swipe of an assistant reply.
enum ReplyRewriteMode {
  shorten,
  expand,
  moreAction,
  moreDialogue,
  softer,
  tenser,
  darker,
  lighter,
  sameBeats,
  custom,
}

/// User choice from the rewrite sheet.
class ReplyRewriteChoice {
  const ReplyRewriteChoice({
    required this.mode,
    this.customInstruction = '',
    this.asNewSwipe = false,
  });

  final ReplyRewriteMode mode;
  final String customInstruction;
  final bool asNewSwipe;
}

/// Builds rewrite instructions for roleplay assistant replies.
class ReplyRewriteService {
  const ReplyRewriteService();

  static const modesForMenu = <ReplyRewriteMode>[
    ReplyRewriteMode.shorten,
    ReplyRewriteMode.expand,
    ReplyRewriteMode.moreAction,
    ReplyRewriteMode.moreDialogue,
    ReplyRewriteMode.softer,
    ReplyRewriteMode.tenser,
    ReplyRewriteMode.darker,
    ReplyRewriteMode.lighter,
    ReplyRewriteMode.sameBeats,
    ReplyRewriteMode.custom,
  ];

  String label(ReplyRewriteMode mode) => switch (mode) {
        ReplyRewriteMode.shorten => 'Shorten',
        ReplyRewriteMode.expand => 'Expand',
        ReplyRewriteMode.moreAction => 'More action',
        ReplyRewriteMode.moreDialogue => 'More dialogue',
        ReplyRewriteMode.softer => 'Softer tone',
        ReplyRewriteMode.tenser => 'Tenser / urgent',
        ReplyRewriteMode.darker => 'Darker mood',
        ReplyRewriteMode.lighter => 'Lighter mood',
        ReplyRewriteMode.sameBeats => 'Same beats, new wording',
        ReplyRewriteMode.custom => 'Custom instruction…',
      };

  String subtitle(ReplyRewriteMode mode) => switch (mode) {
        ReplyRewriteMode.shorten => 'Trim length; keep the same events',
        ReplyRewriteMode.expand => 'Add detail and texture',
        ReplyRewriteMode.moreAction => 'More *actions* and physical beats',
        ReplyRewriteMode.moreDialogue => 'More spoken lines',
        ReplyRewriteMode.softer => 'Gentler, warmer delivery',
        ReplyRewriteMode.tenser => 'Raise stakes and urgency',
        ReplyRewriteMode.darker => 'Heavier, grittier atmosphere',
        ReplyRewriteMode.lighter => 'Warmer or more hopeful tone',
        ReplyRewriteMode.sameBeats =>
          'Rewrite without changing what happens',
        ReplyRewriteMode.custom => 'Type exactly what you want changed',
      };

  String instructionFor(
    ReplyRewriteMode mode, {
    String customInstruction = '',
  }) {
    if (mode == ReplyRewriteMode.custom) {
      final text = customInstruction.trim();
      if (text.isEmpty) {
        throw ArgumentError('Custom rewrite needs an instruction.');
      }
      return text;
    }
    return switch (mode) {
      ReplyRewriteMode.shorten =>
        'SHORTEN this reply while keeping the same story beats, facts, and '
        'outcome. Cut filler; stay in character.',
      ReplyRewriteMode.expand =>
        'EXPAND this reply with richer sensory detail and interiority. Keep the '
        'same events and outcome; do not add new plot twists.',
      ReplyRewriteMode.moreAction =>
        'Rewrite with MORE *action* and physical staging (*asterisks*). Keep the '
        'same story beats.',
      ReplyRewriteMode.moreDialogue =>
        'Rewrite with MORE spoken dialogue in "quotes". Keep the same story beats.',
      ReplyRewriteMode.softer =>
        'Rewrite in a SOFTER, warmer tone. Same facts and outcome.',
      ReplyRewriteMode.tenser =>
        'Rewrite with MORE tension and urgency. Same facts and outcome.',
      ReplyRewriteMode.darker =>
        'Rewrite with a DARKER, heavier mood. Same facts and outcome.',
      ReplyRewriteMode.lighter =>
        'Rewrite with a LIGHTER, warmer mood. Same facts and outcome.',
      ReplyRewriteMode.sameBeats =>
        'Rewrite with fresh wording but the SAME beats, facts, and outcome. '
        'Do not summarize — write a full replacement reply.',
      ReplyRewriteMode.custom => throw StateError('custom handled above'),
    };
  }

  /// Extra messages appended before the model generates the replacement reply.
  List<Map<String, String>> buildRewriteMessages({
    required ReplyRewriteMode mode,
    required String originalReply,
    required String characterName,
    List<ChatMessage> contextMessages = const [],
    String customInstruction = '',
  }) {
    final original = originalReply.trim();
    if (original.isEmpty) {
      throw ArgumentError('Nothing to rewrite.');
    }
    final name =
        characterName.trim().isEmpty ? 'Character' : characterName.trim();
    final instruction = instructionFor(
      mode,
      customInstruction: customInstruction,
    );

    final context = StringBuffer();
    final recent = contextMessages
        .where((m) => m.text.trim().isNotEmpty)
        .toList();
    final start = recent.length > 8 ? recent.length - 8 : 0;
    for (final message in recent.sublist(start)) {
      final who = message.isUser
          ? 'User'
          : (message.speakerName?.trim().isNotEmpty == true
              ? message.speakerName!.trim()
              : name);
      context.writeln('$who: ${message.text.trim()}');
    }

    final user = StringBuffer()
      ..writeln('Rewrite task for $name\'s reply.')
      ..writeln()
      ..writeln('Instruction: $instruction')
      ..writeln()
      ..writeln('Current draft to rewrite:')
      ..writeln(original)
      ..writeln();
    if (context.isNotEmpty) {
      user.writeln('Recent chat context (for continuity only):');
      user.writeln(context.toString().trim());
      user.writeln();
    }
    user.writeln(
      'Write ONLY $name\'s replacement reply. Use *actions* and "dialogue" as '
      'appropriate. Do not write for the user. Do not add preamble.',
    );

    return [
      {
        'role': 'system',
        'content':
            'You rewrite one assistant roleplay reply in a private chat app. '
            'Follow the instruction exactly. Stay in character as $name.',
      },
      {'role': 'user', 'content': user.toString().trim()},
    ];
  }
}
