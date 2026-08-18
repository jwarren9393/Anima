import '../models/chat_message.dart';
import '../models/explicit_scene_guidance.dart';

/// How to steer a regeneration / new swipe of an assistant reply.
enum ReplyRewriteMode {
  custom,
  drunk,
  romantic,
  sensual,
  explicit,
  intimateBuildup,
  afterglow,
  angry,
  happy,
  sad,
  scared,
  playful,
  flirty,
  tender,
  tense,
  hostile,
  exhausted,
  suspicious,
  jealous,
  vulnerable,
  desperate,
  confident,
  whisper,
  softer,
  tenser,
  darker,
  lighter,
  blunt,
  formal,
  shorten,
  expand,
  moreAction,
  moreDialogue,
  sameBeats,
}

/// User choice from the rewrite sheet.
class ReplyRewriteChoice {
  const ReplyRewriteChoice({
    required this.mode,
    this.customInstruction = '',
  });

  final ReplyRewriteMode mode;
  final String customInstruction;
}

/// Builds rewrite instructions for roleplay assistant replies.
class ReplyRewriteService {
  const ReplyRewriteService();

  static final _vocabularyLaw = ExplicitSceneGuidance.vocabularyRule.trim();

  static const modesForMenu = <ReplyRewriteMode>[
    ReplyRewriteMode.custom,
    ReplyRewriteMode.drunk,
    ReplyRewriteMode.romantic,
    ReplyRewriteMode.sensual,
    ReplyRewriteMode.explicit,
    ReplyRewriteMode.intimateBuildup,
    ReplyRewriteMode.afterglow,
    ReplyRewriteMode.angry,
    ReplyRewriteMode.happy,
    ReplyRewriteMode.sad,
    ReplyRewriteMode.scared,
    ReplyRewriteMode.playful,
    ReplyRewriteMode.flirty,
    ReplyRewriteMode.tender,
    ReplyRewriteMode.tense,
    ReplyRewriteMode.hostile,
    ReplyRewriteMode.exhausted,
    ReplyRewriteMode.suspicious,
    ReplyRewriteMode.jealous,
    ReplyRewriteMode.vulnerable,
    ReplyRewriteMode.desperate,
    ReplyRewriteMode.confident,
    ReplyRewriteMode.whisper,
    ReplyRewriteMode.softer,
    ReplyRewriteMode.tenser,
    ReplyRewriteMode.darker,
    ReplyRewriteMode.lighter,
    ReplyRewriteMode.blunt,
    ReplyRewriteMode.formal,
    ReplyRewriteMode.shorten,
    ReplyRewriteMode.expand,
    ReplyRewriteMode.moreAction,
    ReplyRewriteMode.moreDialogue,
    ReplyRewriteMode.sameBeats,
  ];

  String label(ReplyRewriteMode mode) => switch (mode) {
        ReplyRewriteMode.custom => 'Custom instruction…',
        ReplyRewriteMode.drunk => 'Drunk / intoxicated',
        ReplyRewriteMode.romantic => 'Romantic',
        ReplyRewriteMode.sensual => 'Sensual / intimate',
        ReplyRewriteMode.explicit => 'Explicit / graphic',
        ReplyRewriteMode.intimateBuildup => 'Intimate build-up',
        ReplyRewriteMode.afterglow => 'Afterglow / aftermath',
        ReplyRewriteMode.angry => 'Angry / heated',
        ReplyRewriteMode.happy => 'Happy / upbeat',
        ReplyRewriteMode.sad => 'Sad / melancholy',
        ReplyRewriteMode.scared => 'Scared / fearful',
        ReplyRewriteMode.playful => 'Playful / teasing',
        ReplyRewriteMode.flirty => 'Flirty',
        ReplyRewriteMode.tender => 'Tender / gentle',
        ReplyRewriteMode.tense => 'Tense / on edge',
        ReplyRewriteMode.hostile => 'Hostile / cold',
        ReplyRewriteMode.exhausted => 'Exhausted / drained',
        ReplyRewriteMode.suspicious => 'Suspicious / guarded',
        ReplyRewriteMode.jealous => 'Jealous / possessive',
        ReplyRewriteMode.vulnerable => 'Vulnerable / raw',
        ReplyRewriteMode.desperate => 'Desperate / pleading',
        ReplyRewriteMode.confident => 'Confident / bold',
        ReplyRewriteMode.whisper => 'Quiet / whispered',
        ReplyRewriteMode.shorten => 'Shorten',
        ReplyRewriteMode.expand => 'Expand',
        ReplyRewriteMode.moreAction => 'More action',
        ReplyRewriteMode.moreDialogue => 'More dialogue',
        ReplyRewriteMode.softer => 'Softer tone',
        ReplyRewriteMode.tenser => 'Tenser / urgent',
        ReplyRewriteMode.darker => 'Darker mood',
        ReplyRewriteMode.lighter => 'Lighter mood',
        ReplyRewriteMode.blunt => 'Blunt / unfiltered',
        ReplyRewriteMode.formal => 'Formal / composed',
        ReplyRewriteMode.sameBeats => 'Same beats, new wording',
      };

  String subtitle(ReplyRewriteMode mode) => switch (mode) {
        ReplyRewriteMode.custom => 'Type exactly what you want changed',
        ReplyRewriteMode.drunk => 'Slurred, loose, unsteady delivery',
        ReplyRewriteMode.romantic => 'Warm tension and intimacy',
        ReplyRewriteMode.sensual =>
          'Realistic intimacy — emotional, not graphic',
        ReplyRewriteMode.explicit =>
          'Raw adult words — no euphemisms or AI tropes',
        ReplyRewriteMode.intimateBuildup =>
          'Teasing, tension, anticipation before sex',
        ReplyRewriteMode.afterglow =>
          'Post-climax — messy, human, not a movie ending',
        ReplyRewriteMode.angry => 'Sharp, confrontational heat',
        ReplyRewriteMode.happy => 'Light, energized mood',
        ReplyRewriteMode.sad => 'Heavy, quiet melancholy',
        ReplyRewriteMode.scared => 'Fear, dread, hypervigilance',
        ReplyRewriteMode.playful => 'Witty, teasing energy',
        ReplyRewriteMode.flirty => 'Bold attraction and hints',
        ReplyRewriteMode.tender => 'Gentle, caring, soft delivery',
        ReplyRewriteMode.tense => 'Tight nerves, high stakes',
        ReplyRewriteMode.hostile => 'Cold distance or open antagonism',
        ReplyRewriteMode.exhausted => 'Tired, running on fumes',
        ReplyRewriteMode.suspicious => 'Guarded, probing, distrustful',
        ReplyRewriteMode.jealous => 'Possessive edge, insecurity showing',
        ReplyRewriteMode.vulnerable => 'Emotionally exposed, unguarded',
        ReplyRewriteMode.desperate => 'Urgent need, pleading undertone',
        ReplyRewriteMode.confident => 'Assured, self-possessed delivery',
        ReplyRewriteMode.whisper => 'Hushed, close, careful volume',
        ReplyRewriteMode.shorten => 'Trim length; keep the same events',
        ReplyRewriteMode.expand => 'Add detail and texture',
        ReplyRewriteMode.moreAction => 'More *actions* and physical beats',
        ReplyRewriteMode.moreDialogue => 'More spoken lines',
        ReplyRewriteMode.softer => 'Gentler, warmer delivery',
        ReplyRewriteMode.tenser => 'Raise stakes and urgency',
        ReplyRewriteMode.darker => 'Heavier, grittier atmosphere',
        ReplyRewriteMode.lighter => 'Warmer or more hopeful tone',
        ReplyRewriteMode.blunt => 'Direct, unvarnished, no softening',
        ReplyRewriteMode.formal => 'Polished, restrained, composed',
        ReplyRewriteMode.sameBeats =>
          'Rewrite without changing what happens',
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
      ReplyRewriteMode.drunk =>
        'Rewrite as DRUNK/INTOXICATED: slurred speech, tangents, loose filter, '
        'laughter, unsteady body language. Same story beats — intoxicated delivery.',
      ReplyRewriteMode.romantic =>
        'Rewrite with ROMANTIC tension: longing, charged pauses, tenderness. '
        'Same facts and outcome.',
      ReplyRewriteMode.sensual =>
        'Rewrite with SENSUAL, realistic intimacy — sensory detail, breath, '
        'hesitation, emotional stakes. Same facts. No porn clichés, no curtain-call '
        'lines, no fade-to-black.',
      ReplyRewriteMode.explicit =>
        'Rewrite EXPLICIT/GRAPHIC: full sensory detail, plain adult vocabulary, '
        'stay in the physical moment. Same facts and outcome. Do not sanitize.\n\n'
        '$_vocabularyLaw',
      ReplyRewriteMode.intimateBuildup =>
        'Rewrite as INTIMATE BUILD-UP: teasing, charged pauses, hands and mouths '
        'wandering, clothes coming off, restraint breaking — anticipation before '
        'the main act unless already there. Same facts.\n\n$_vocabularyLaw',
      ReplyRewriteMode.afterglow =>
        'Rewrite as AFTERGLOW/AFTERMATH: post-climax messiness, catching breath, '
        'tangled limbs, tenderness or awkward humor — not a generic porn wrap-up. '
        'Same facts.\n\n$_vocabularyLaw',
      ReplyRewriteMode.angry =>
        'Rewrite ANGRY/HEATED: sharper words, frustration, confrontation as fits '
        'the character. Same facts and outcome.',
      ReplyRewriteMode.happy =>
        'Rewrite with HAPPY, upbeat energy — warmth and ease in voice. Same beats.',
      ReplyRewriteMode.sad =>
        'Rewrite with SAD/MELANCHOLY weight — slower, heavier delivery. Same beats.',
      ReplyRewriteMode.scared =>
        'Rewrite SCARED/FEARFUL: shaky breath, dread, hypervigilance. Same beats.',
      ReplyRewriteMode.playful =>
        'Rewrite PLAYFUL/TEASING: wit and light provocation. Same story beats.',
      ReplyRewriteMode.flirty =>
        'Rewrite FLIRTY: bold attraction, teasing hints. Same story beats.',
      ReplyRewriteMode.tender =>
        'Rewrite TENDER/GENTLE: soft, careful delivery, kindness in small gestures. Same beats.',
      ReplyRewriteMode.tense =>
        'Rewrite TENSE/ON EDGE: tight nerves, watchful pauses, raised stakes. Same beats.',
      ReplyRewriteMode.hostile =>
        'Rewrite HOSTILE/COLD: distrust, barbed politeness, refusal to cooperate. Same beats.',
      ReplyRewriteMode.exhausted =>
        'Rewrite EXHAUSTED/DRAINED: short answers, heavy pauses, fatigue showing. Same beats.',
      ReplyRewriteMode.suspicious =>
        'Rewrite SUSPICIOUS/GUARDED: probing questions, reading between lines. Same beats.',
      ReplyRewriteMode.jealous =>
        'Rewrite JEALOUS/POSSESSIVE: insecurity, sharp edges around rivals or attention. Same beats.',
      ReplyRewriteMode.vulnerable =>
        'Rewrite VULNERABLE/RAW: emotional exposure, honesty breaking through guard. Same beats.',
      ReplyRewriteMode.desperate =>
        'Rewrite DESPERATE/PLEADING: urgent need, stakes feel personal and immediate. Same beats.',
      ReplyRewriteMode.confident =>
        'Rewrite CONFIDENT/BOLD: assured voice, self-possessed body language. Same beats.',
      ReplyRewriteMode.whisper =>
        'Rewrite QUIET/WHUSHED: hushed volume, close proximity, careful words. Same beats.',
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
      ReplyRewriteMode.blunt =>
        'Rewrite BLUNT/UNFILTERED: direct words, no softening or euphemism. Same beats.',
      ReplyRewriteMode.formal =>
        'Rewrite FORMAL/COMPOSED: polished diction, restrained emotion. Same beats.',
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
