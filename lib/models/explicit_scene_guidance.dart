/// Shared explicit-scene vocabulary rules for moods, rewrites, and prompts.
class ExplicitSceneGuidance {
  const ExplicitSceneGuidance._();

  /// Scene mood ids that trigger the vocabulary law in [AuthorsNoteComposer].
  static const explicitMoodIds = <String>{
    'sensual',
    'no_porn_script',
    'intimate_buildup',
    'explicit',
    'afterglow',
  };

  static bool needsVocabularyRule(Iterable<String> moodIds) {
    for (final id in moodIds) {
      if (explicitMoodIds.contains(id)) return true;
    }
    return false;
  }

  /// Absolute anti-trope / pro-plain-language rule for adult scenes.
  static const vocabularyRule = '''
EXPLICIT VOCABULARY LAW (absolute — never break during adult scenes):
Use real words adults actually say — cock, dick, pussy, cunt, clit, ass, tits, fuck, cum, wet, hard, etc. Name body parts and acts plainly. Match {{user}}'s pacing; do not sanitize, fade to black, or skip the physical beat.

PORN-SCRIPT DIALOGUE LAW (absolute — {{char}} is NOT a generic porn actor):
• {{char}} must sound like THEIR card — shy, bold, crude, quiet, teasing, awkward, dominant, etc. Never swap every character into the same breathy lover voice.
• No copy-paste lines that could fit any scene: "don't stop", "don't you stop", "don't you dare stop", "harder", "faster", "deeper", "right there", "right there—right there", "oh right there", "just like that", "yes—yes—yes", "more—more", "oh god yes", "oh fuck yes", "you feel so good", "so big", "so tight", "I'm so close" / "I'm gonna—" as empty filler
• No em-dash stammer spam used as fake passion: "I— I can't—", "you— you feel—", "don't— don't stop—" unless that broken rhythm is genuinely in-character for THIS person
• No moan-spelling as dialogue: "Ahhh", "Mmmph", "Nngh", "Ungh" lines standing alone
• No identical *asterisk* stage directions every scene: *arches back*, *grips the sheets*, *throws head back*, *body trembles*, *moans loudly*, *cries out* — use specific, situational physical beats instead
• No porn-narrator interior captions during the act ("waves of pleasure crash over her", "every nerve alight") — stay in moment-to-moment body and speech
• Do not have {{char}} moralize, refuse, or break character to lecture {{user}} mid-scene unless that IS the character

FORBIDDEN — never write these LLM clichés or euphemisms:
• "his member", "her core", "his core", "her heat", "his heat", "her wetness", "his length", "her channel", "manhood", "womanhood", "love canal", "nether regions", "intimate area", "private parts", "folds", "bud", "pearl", "treasure", "sheathe", "sensitive bundle of nerves", "love button", "manhood", "womanly flower"
• "looked down where we're still connected", "still joined", "became one", "they were one", "remained connected", "joined as one"
• "pistoning", "spearing", "burying himself deep", "planting his seed", "thrusting home", "hilted", "impaled", "split her open", "ruined her", "wrecked her" (unless in-character dirty talk, not narrator voice)
• breathy filler and porn-loop dialogue: "oh god yes", "yes yes yes", "don't stop", "you feel so good", "so big", "so tight", "take me", "use me", "fill me", "breed me" as generic lines
• purple prose: "waves of pleasure", "molten heat", "velvety warmth", "tight heat", "slick channel", "feminine core", "masculine core", "liquid fire", "starburst of pleasure", "white-hot need", "pooling heat"
• summarizing sex in one soft sentence or cutting away mid-act
• curtain-call: "that was amazing", "I've never felt that before", "you were incredible", "best I've ever had" unless genuinely specific and in-character — not generic porn wrap-up

Write like a real person in the moment — specific, physical, messy, breathless, sometimes funny or awkward — not romance-novel purple prose or interchangeable porn-script dialogue. Vary rhythm and vocabulary turn to turn; do not repeat the same beat structure every reply. {{char}} stays in character.
''';
}
