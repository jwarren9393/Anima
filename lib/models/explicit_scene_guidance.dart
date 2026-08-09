/// Shared explicit-scene vocabulary rules for moods, rewrites, and prompts.
class ExplicitSceneGuidance {
  const ExplicitSceneGuidance._();

  /// Scene mood ids that trigger the vocabulary law in [AuthorsNoteComposer].
  static const explicitMoodIds = <String>{
    'explicit',
    'intimate_buildup',
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

FORBIDDEN — never write these LLM clichés or euphemisms:
• "his member", "her core", "his core", "her heat", "his heat", "her wetness", "his length", "her channel", "manhood", "womanhood", "love canal", "nether regions", "intimate area", "private parts", "folds", "bud", "pearl", "treasure", "sheathe"
• "looked down where we're still connected", "still joined", "became one", "they were one", "remained connected"
• "pistoning", "spearing", "burying himself deep", "planting his seed", "thrusting home", "hilted", "impaled"
• breathy filler: "oh god yes", "yes yes yes", "don't stop", "you feel so good", "so big", "so tight" as generic porn lines
• purple prose: "waves of pleasure", "molten heat", "velvety warmth", "tight heat", "slick channel", "feminine core", "masculine core", "liquid fire", "starburst of pleasure"
• summarizing sex in one soft sentence or cutting away mid-act
• curtain-call: "that was amazing", "I've never felt that before", "you were incredible" unless genuinely specific and in-character — not generic porn wrap-up

Write like a real person in the moment — specific, physical, messy, breathless, sometimes funny or awkward — not romance-novel purple prose or porn-script dialogue. {{char}} stays in character.
''';
}
