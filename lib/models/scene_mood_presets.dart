/// Built-in scene moods — toggled per chat, merged into Author's Note each turn.
class SceneMoodPreset {
  const SceneMoodPreset({
    required this.id,
    required this.name,
    required this.description,
    required this.text,
  });

  final String id;
  final String name;
  final String description;

  /// Injected when this mood is active (macros expanded at prompt time).
  final String text;
}

class SceneMoodPresets {
  const SceneMoodPresets._();

  static const List<SceneMoodPreset> all = [
    SceneMoodPreset(
      id: 'drunk',
      name: 'Drunk',
      description: 'Slurred, loose, unsteady delivery.',
      text:
          'SCENE MOOD — DRUNK (ongoing until turned off):\n'
          '{{char}} is noticeably drunk — slurred speech, loose filter, exaggerated '
          'emotions, poor coordination, risky impulses. NOT sober professional '
          '{{char}} voice. Write drunk: shorter sentences, repetition, tangents, '
          'laughter, misjudged volume, physical slips (*stumbles*, *slurs*). '
          'Sober eloquence is wrong for this scene.',
    ),
    SceneMoodPreset(
      id: 'romantic',
      name: 'Romantic',
      description: 'Warm tension, longing, intimacy.',
      text:
          'SCENE MOOD — ROMANTIC:\n'
          'Lean into romantic tension: meaningful glances, charged pauses, '
          'tender touch, emotional vulnerability. Let attraction color dialogue '
          'without rushing to a conclusion unless {{user}} leads there.',
    ),
    SceneMoodPreset(
      id: 'tense',
      name: 'Tense',
      description: 'High stakes, tight nerves, urgency.',
      text:
          'SCENE MOOD — TENSE:\n'
          'Keep the scene tight and urgent: short beats, watchful pauses, '
          'raised stakes, consequences looming. Characters choose words carefully. '
          'Do not deflate tension with jokes or filler.',
    ),
    SceneMoodPreset(
      id: 'sensual',
      name: 'Sensual / intimate',
      description: 'Realistic adult intimacy — no porn clichés.',
      text:
          'SCENE MOOD — SENSUAL / INTIMATE (ongoing until turned off):\n'
          'Write adult intimacy like real people: breath, hesitation, humor, awkward '
          'beats, specific sensation, emotional stakes. Avoid porn clichés — no "oh god '
          'yes", no breathy stammering for its own sake, no "that was amazing" '
          'curtain-call, no instant fade-to-black after climax. Stay in the moment; '
          'match {{user}}\'s pacing. {{char}} stays in character — not a generic lover voice.',
    ),
    SceneMoodPreset(
      id: 'angry',
      name: 'Angry',
      description: 'Sharp, heated, confrontational.',
      text:
          'SCENE MOOD — ANGRY:\n'
          '{{char}} is angry or on edge: sharper words, clipped replies, visible '
          'frustration, controlled or uncontrolled outbursts as fits the card. '
          'Same facts — heated delivery.',
    ),
    SceneMoodPreset(
      id: 'happy',
      name: 'Happy',
      description: 'Light, upbeat, energized.',
      text:
          'SCENE MOOD — HAPPY:\n'
          'Play this beat with genuine warmth and energy: smiles, ease, quicker '
          'rhythm, small joys. Not manic — let good mood show in voice and body.',
    ),
    SceneMoodPreset(
      id: 'sad',
      name: 'Sad',
      description: 'Heavy, quiet, melancholy.',
      text:
          'SCENE MOOD — SAD:\n'
          'Write with melancholy weight: slower rhythm, unfinished sentences, '
          'distance or tenderness, grief or regret coloring small actions. '
          'Avoid forced cheer.',
    ),
    SceneMoodPreset(
      id: 'playful',
      name: 'Playful',
      description: 'Teasing, witty, fun energy.',
      text:
          'SCENE MOOD — PLAYFUL:\n'
          'Banter and teasing are welcome: wit, light provocation, physical comedy '
          'when it fits. Stay in character — not every line needs a joke.',
    ),
    SceneMoodPreset(
      id: 'scared',
      name: 'Scared',
      description: 'Fear, dread, hypervigilance.',
      text:
          'SCENE MOOD — SCARED:\n'
          '{{char}} is frightened or deeply uneasy: shaky breath, scanning exits, '
          'jumpiness, denial or bravado over real fear. Prioritize dread over action-movie confidence.',
    ),
    SceneMoodPreset(
      id: 'tender',
      name: 'Tender',
      description: 'Gentle, caring, soft.',
      text:
          'SCENE MOOD — TENDER:\n'
          'Soft, careful delivery: kindness in small gestures, patient listening, '
          'gentle humor. Protect emotional safety in the beat.',
    ),
    SceneMoodPreset(
      id: 'hostile',
      name: 'Hostile',
      description: 'Cold, distrustful, adversarial.',
      text:
          'SCENE MOOD — HOSTILE:\n'
          'Cold distance or open antagonism: suspicion, barbed politeness, refusal '
          'to cooperate, threat without necessarily escalating to violence.',
    ),
    SceneMoodPreset(
      id: 'flirty',
      name: 'Flirty',
      description: 'Teasing attraction, bold hints.',
      text:
          'SCENE MOOD — FLIRTY:\n'
          'Playful attraction: double meanings, bold compliments, confident body '
          'language, push-and-pull. Follow {{user}}\'s lead on how far it goes.',
    ),
    SceneMoodPreset(
      id: 'exhausted',
      name: 'Exhausted',
      description: 'Tired, drained, running on fumes.',
      text:
          'SCENE MOOD — EXHAUSTED:\n'
          '{{char}} is worn down: short answers, heavy pauses, mistakes from fatigue, '
          'irritability or vulnerability from being spent. Not their crisp default voice.',
    ),
    SceneMoodPreset(
      id: 'suspicious',
      name: 'Suspicious',
      description: 'Guarded, probing, distrustful.',
      text:
          'SCENE MOOD — SUSPICIOUS:\n'
          '{{char}} does not fully trust the situation: probing questions, reading '
          'between lines, withholding information, watching for lies.',
    ),
  ];

  static SceneMoodPreset? byId(String id) {
    final key = id.trim();
    if (key.isEmpty) return null;
    for (final preset in all) {
      if (preset.id == key) return preset;
    }
    return null;
  }

  static List<SceneMoodPreset> resolve(Iterable<String> ids) {
    final out = <SceneMoodPreset>[];
    final seen = <String>{};
    for (final raw in ids) {
      final preset = byId(raw);
      if (preset == null || !seen.add(preset.id)) continue;
      out.add(preset);
    }
    return out;
  }
}
