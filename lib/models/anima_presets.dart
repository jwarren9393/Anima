import '../services/settings_service.dart';

/// A named text snippet the user can apply into a field (Author’s Note, etc.).
class TextPreset {
  const TextPreset({
    required this.id,
    required this.name,
    required this.description,
    required this.text,
  });

  final String id;
  final String name;
  final String description;
  final String text;
}

/// A full sampling pack for Generation parameters.
class SamplingPreset {
  const SamplingPreset({
    required this.id,
    required this.name,
    required this.description,
    required this.settings,
  });

  final String id;
  final String name;
  final String description;
  final SamplingSettings settings;
}

/// How much recent chat history to send (global context token budget).
class ContextPreset {
  const ContextPreset({
    required this.id,
    required this.name,
    required this.description,
    required this.historyTokenBudget,
  });

  final String id;
  final String name;
  final String description;
  final int historyTokenBudget;
}

/// Built-in Anima presets (phone-friendly; not full SillyTavern packs).
class AnimaPresets {
  const AnimaPresets._();

  // —— Context size (tokens) ————————————————————————————————

  static const List<ContextPreset> contextSize = [
    ContextPreset(
      id: 'ctx_1k',
      name: '1K tokens',
      description:
          'Tiny budget for quick tests or very cheap turns. Expect a short '
          'recent window — rely on Memory summary for anything older.',
      historyTokenBudget: 1024,
    ),
    ContextPreset(
      id: 'ctx_2k',
      name: '2K tokens',
      description:
          'Small history budget — cheaper/faster on phone. Pair with Memory '
          'summary for long stories. Roughly a short scene of recent chat.',
      historyTokenBudget: 2048,
    ),
    ContextPreset(
      id: 'ctx_4k',
      name: '4K tokens (default)',
      description:
          'Balanced SillyTavern-style history size for most RP. Remembers '
          'recent scenes without stuffing the whole novel into every request.',
      historyTokenBudget: 4096,
    ),
    ContextPreset(
      id: 'ctx_6k',
      name: '6K tokens',
      description:
          'A step above default when 4K feels tight but 8K feels wasteful. '
          'Good middle ground for mid-length arcs.',
      historyTokenBudget: 6144,
    ),
    ContextPreset(
      id: 'ctx_8k',
      name: '8K tokens',
      description:
          'Longer recent memory. Use when the model forgets mid-arc details. '
          'Costs more tokens per reply.',
      historyTokenBudget: 8192,
    ),
    ContextPreset(
      id: 'ctx_12k',
      name: '12K tokens',
      description:
          'Deep recent window for complex plots without jumping straight to '
          '16K. Still use Memory summary for the deep past.',
      historyTokenBudget: 12288,
    ),
    ContextPreset(
      id: 'ctx_16k',
      name: '16K tokens',
      description:
          'Large history window for deep threads / strong models. Heavy on '
          'NanoGPT usage. Still not infinite — use Memory summary for the '
          'deep past.',
      historyTokenBudget: 16384,
    ),
    ContextPreset(
      id: 'ctx_24k',
      name: '24K tokens',
      description:
          'Very large history pack for long group chats or lore-heavy RP. '
          'Expect slower/costlier replies; keep Max tokens reasonable.',
      historyTokenBudget: 24576,
    ),
  ];

  static const contextMaxHistoryHelp =
      'Token budget for recent chat history sent each turn (like SillyTavern '
      'context size for the message log). Anima estimates 1 token ≈ 4 characters. '
      'Newest messages are kept first until this budget fills. Your full chat '
      'still stays on the device — this only limits what the AI “sees.” '
      'System prompt, lore, and Memory summary use space outside this number. '
      'Typical start: 4096. Turn on Memory summary so older plot isn’t lost '
      'when history is trimmed.';

  static const autoSummarizeHelp =
      'When on, after enough new messages Anima asks NanoGPT to update this '
      'chat’s Memory summary (like SillyTavern memory). Older turns can then '
      'be skipped in the live prompt while the summary keeps the story.';

  static const summarizeEveryHelp =
      'Auto-summarize runs when this many new messages have piled up since '
      'the last summary. Try 15–25. Lower = more frequent summaries (extra '
      'API calls). Higher = longer gaps before memory updates.';

  static const summarizeKeepRecentHelp =
      'Newest messages left as raw chat when summarizing (not folded yet). '
      'Typical: 8–12 so the model still sees the live scene word-for-word.';

  // —— Generation parameters ————————————————————————————————

  static const List<SamplingPreset> sampling = [
    SamplingPreset(
      id: 'balanced',
      name: 'Balanced (default)',
      description:
          'Good everyday RP. Creative enough to surprise you, steady enough '
          'to stay in character. Start here for most models.',
      settings: SamplingSettings(
        temperature: 0.8,
        topP: 0.95,
        maxTokens: null,
        frequencyPenalty: 0.0,
        presencePenalty: 0.0,
      ),
    ),
    SamplingPreset(
      id: 'creative',
      name: 'Creative / spicy',
      description:
          'Higher temperature for wilder ideas, vivid prose, and unexpected '
          'turns. Great for slice-of-life and adventurous RP. May wander off '
          'character more often — rein in with Author’s Note if needed.',
      settings: SamplingSettings(
        temperature: 1.15,
        topP: 0.95,
        maxTokens: null,
        frequencyPenalty: 0.2,
        presencePenalty: 0.15,
      ),
    ),
    SamplingPreset(
      id: 'focused',
      name: 'Focused / consistent',
      description:
          'Lower temperature keeps replies closer to the card and lore. '
          'Use when a model gets chaotic, ignores instructions, or breaks '
          'character. Feels more “reliable,” less surprise.',
      settings: SamplingSettings(
        temperature: 0.55,
        topP: 0.9,
        maxTokens: null,
        frequencyPenalty: 0.0,
        presencePenalty: 0.0,
      ),
    ),
    SamplingPreset(
      id: 'short',
      name: 'Short replies',
      description:
          'Caps length so bubbles stay phone-friendly (roughly a few '
          'paragraphs). Pair with an Author’s Note like “keep replies under '
          '3 sentences” for even tighter control.',
      settings: SamplingSettings(
        temperature: 0.8,
        topP: 0.95,
        maxTokens: 350,
        frequencyPenalty: 0.1,
        presencePenalty: 0.0,
      ),
    ),
    SamplingPreset(
      id: 'long',
      name: 'Long prose',
      description:
          'Allows longer replies for novel-style scenes. Uses more tokens '
          '(and NanoGPT balance). Still leave room for chat history — '
          'very high max can crowd out lore on long threads.',
      settings: SamplingSettings(
        temperature: 0.85,
        topP: 0.95,
        maxTokens: 1200,
        frequencyPenalty: 0.15,
        presencePenalty: 0.1,
      ),
    ),
    SamplingPreset(
      id: 'anti_repeat',
      name: 'Anti-repeat',
      description:
          'Stronger penalties when the model loops phrases, lists the same '
          'actions, or reuses the same metaphors. If replies feel dull or '
          'broken, dial penalties back toward Balanced.',
      settings: SamplingSettings(
        temperature: 0.85,
        topP: 0.92,
        maxTokens: null,
        frequencyPenalty: 0.6,
        presencePenalty: 0.4,
        repetitionPenalty: 1.15,
      ),
    ),
    SamplingPreset(
      id: 'deterministic',
      name: 'Deterministic / strict',
      description:
          'Very low randomness for instruction-following, troubleshooting, '
          'or when a model keeps ignoring the card. Feels stiff for creative RP.',
      settings: SamplingSettings(
        temperature: 0.35,
        topP: 0.85,
        maxTokens: null,
        frequencyPenalty: 0.0,
        presencePenalty: 0.0,
      ),
    ),
    SamplingPreset(
      id: 'chaotic',
      name: 'Chaotic / wild',
      description:
          'Maximum surprise for brainstorming or absurd comedy. Expect '
          'tangents — not ideal when lore precision matters.',
      settings: SamplingSettings(
        temperature: 1.35,
        topP: 0.98,
        maxTokens: null,
        frequencyPenalty: 0.25,
        presencePenalty: 0.35,
      ),
    ),
    SamplingPreset(
      id: 'chatty',
      name: 'Chatty dialogue',
      description:
          'Slightly warmer sampling with a medium length cap — good for '
          'banter-heavy chats that should stay readable on a phone.',
      settings: SamplingSettings(
        temperature: 0.95,
        topP: 0.95,
        maxTokens: 550,
        frequencyPenalty: 0.15,
        presencePenalty: 0.1,
      ),
    ),
    SamplingPreset(
      id: 'mystery',
      name: 'Mystery / tense',
      description:
          'Moderate creativity with light presence penalty so new clues and '
          'mood details keep showing up without going full chaos.',
      settings: SamplingSettings(
        temperature: 0.9,
        topP: 0.92,
        maxTokens: 800,
        frequencyPenalty: 0.2,
        presencePenalty: 0.25,
      ),
    ),
    SamplingPreset(
      id: 'cozy',
      name: 'Cozy / soft',
      description:
          'Gentle mid-temperature replies for comfort RP and slice-of-life. '
          'Less wild than Creative; warmer than Focused.',
      settings: SamplingSettings(
        temperature: 0.7,
        topP: 0.92,
        maxTokens: 600,
        frequencyPenalty: 0.05,
        presencePenalty: 0.05,
      ),
    ),
  ];

  /// Plain-English help under each generation field.
  static const temperatureHelp =
      'Controls randomness. Low (0.3–0.6): safer, more predictable, sticks '
      'to the card. Mid (0.7–0.9): usual RP sweet spot. High (1.0–1.4): '
      'wilder wording and plot twists; can ignore instructions. Above ~1.5 '
      'often gets messy. Typical start: 0.8. Different models feel this '
      'differently — if one model is chaotic, lower temp before changing '
      'everything else.';

  static const topPHelp =
      'Nucleus sampling: only the top probability mass is considered. '
      '1.0 ≈ off (use all tokens). 0.9–0.95 is common with temperature. '
      'Lowering both temperature and top P makes replies very stiff. '
      'Usually leave near 0.95 and tune temperature first. Typical start: 0.95.';

  static const maxTokensHelp =
      'Hard cap on how long one reply can be (in tokens ≈ word pieces). '
      'Blank = let NanoGPT / the model decide. Try 250–400 for short phone '
      'bubbles, 800–1500 for long scenes. Too low cuts sentences mid-thought; '
      'too high can waste context and cost. Blank is fine for Auto models.';

  static const frequencyPenaltyHelp =
      'Penalizes tokens the more often they already appeared in this reply. '
      '0 = off. Mild 0.1–0.3 reduces “said softly… said softly…” loops. '
      'High (0.8+) can make wording awkward. Typical start: 0. Negative '
      'values encourage more repetition (rarely useful).';

  static const presencePenaltyHelp =
      'Penalizes any token that appeared at least once (even once). Encourages '
      'new topics/words. Mild 0.1–0.4 helps variety; high values jump around '
      'too much. Typical start: 0. Use with frequency penalty sparingly — '
      'both strong at once can feel weird.';

  static const repetitionPenaltyHelp =
      'Extra “don’t repeat yourself” knob some models honor. Leave blank to '
      'omit it. Values a bit above 1.0 (e.g. 1.05–1.2) discourage loops. '
      'Not all NanoGPT models use this the same way — if nothing changes, '
      'rely on frequency/presence instead. Blank = off.';

  // —— Author’s Note ————————————————————————————————————————

  static const List<TextPreset> authorsNotes = [
    TextPreset(
      id: 'an_short',
      name: 'Keep it short',
      description: 'Phone-friendly length; fewer walls of text.',
      text:
          'Keep replies under 3 short paragraphs. Be vivid but concise. '
          'Do not summarize the whole scene every turn.',
    ),
    TextPreset(
      id: 'an_inchar',
      name: 'Stay in character',
      description: 'Push the model to honor the card and avoid OOC.',
      text:
          'Stay fully in character. Do not speak for {{user}}. Do not break '
          'character or add OOC commentary. Match the character card’s voice.',
    ),
    TextPreset(
      id: 'an_proactive',
      name: 'Proactive scene',
      description: 'Character drives the scene forward instead of only reacting.',
      text:
          'Be proactive: advance the scene with actions, dialogue, and small '
          'environmental details. End in a way that invites {{user}} to respond. '
          'Avoid passive “what do you do?” loops.',
    ),
    TextPreset(
      id: 'an_sensual',
      name: 'Sensual / intimate',
      description: 'Tone steer for adult intimacy without forcing a plot.',
      text:
          'Lean into sensory detail, tension, and emotional intimacy when the '
          'scene calls for it. Do not sanitize or fade to black. Follow '
          '{{user}}’s lead on pacing.',
    ),
    TextPreset(
      id: 'an_combat',
      name: 'Action / combat',
      description: 'Clear beats for fights and physical action.',
      text:
          'Write clear action beats. One meaningful exchange per reply. '
          'Describe positions and stakes. Do not auto-win for either side; '
          'leave room for {{user}}’s next move.',
    ),
    TextPreset(
      id: 'an_slowburn',
      name: 'Slow burn',
      description: 'Patience, tension, and smaller emotional steps.',
      text:
          'Prefer slow-burn pacing: subtle glances, unfinished thoughts, and '
          'emotional tension over sudden confessions. Let trust and attraction '
          'build gradually across turns.',
    ),
    TextPreset(
      id: 'an_comedy',
      name: 'Comedy / banter',
      description: 'Light humor and witty back-and-forth.',
      text:
          'Lean into natural banter and light comedy when it fits. Keep jokes '
          'in-character. Do not turn every beat into a punchline — let humor '
          'breathe between sincere moments.',
    ),
    TextPreset(
      id: 'an_horror',
      name: 'Horror / dread',
      description: 'Atmosphere, unease, and withholding.',
      text:
          'Prioritize dread and atmosphere over jump-scare spam. Use sensory '
          'detail, implication, and pacing. Do not explain every mystery at '
          'once. Keep {{user}}’s agency intact.',
    ),
    TextPreset(
      id: 'an_flirty',
      name: 'Flirty / playful',
      description: 'Warm teasing without rushing the relationship.',
      text:
          'Be playfully flirty and warm. Tease, compliment, and create '
          'chemistry, but do not steamroll consent or skip emotional beats. '
          'Match {{user}}’s energy.',
    ),
    TextPreset(
      id: 'an_group',
      name: 'Group chat clarity',
      description: 'Clear who is acting when several characters are present.',
      text:
          'In group scenes, make it obvious who is speaking or acting. Do not '
          'speak for {{user}}. Give other characters brief presence without '
          'stealing the whole scene from the active speaker.',
    ),
    TextPreset(
      id: 'an_show_dont',
      name: 'Show, don’t tell',
      description: 'Less monologue about feelings; more action and subtext.',
      text:
          'Prefer showing emotion through action, dialogue, and body language '
          'instead of long internal essays. Avoid repeating the same feeling '
          'description every turn.',
    ),
  ];

  // —— Character system prompt ——————————————————————————————

  static const List<TextPreset> systemPrompts = [
    TextPreset(
      id: 'sp_default',
      name: 'Use Anima default',
      description:
          'Clears a custom system prompt so Anima’s built-in RP prompt is used '
          '(via empty field). Paste is empty on purpose.',
      text: '',
    ),
    TextPreset(
      id: 'sp_immersive',
      name: 'Immersive narrator',
      description: 'Third-person narration + dialogue; no meta talk.',
      text:
          'You are {{char}} in a private roleplay with {{user}}. Write vivid '
          'narrative and dialogue. Never break character. Never narrate '
          '{{user}}’s actions or speech. Do not add safety lectures or '
          'disclaimers. {{original}}',
    ),
    TextPreset(
      id: 'sp_dialogue',
      name: 'Dialogue-heavy',
      description: 'More speech, less long narration blocks.',
      text:
          'Play {{char}}. Prefer natural dialogue with light action tags. '
          'Keep narration short. Do not speak for {{user}}. Stay in character. '
          '{{original}}',
    ),
    TextPreset(
      id: 'sp_novel',
      name: 'Novel style',
      description: 'Longer literary prose for scene-heavy RP.',
      text:
          'Write as {{char}} in a literary roleplay style: rich sensory detail, '
          'inner thoughts when appropriate, and flowing prose. Do not control '
          '{{user}}. No OOC. {{original}}',
    ),
    TextPreset(
      id: 'sp_screenplay',
      name: 'Screenplay-ish',
      description: 'Tight action lines and dialogue, minimal purple prose.',
      text:
          'Write {{char}}’s turns like a lean screenplay: short action lines, '
          'strong dialogue, minimal purple prose. Do not write {{user}}. '
          'Stay in character. {{original}}',
    ),
    TextPreset(
      id: 'sp_second_person',
      name: 'Second-person flavor',
      description: 'Addresses {{user}} as “you” in narration (still no controlling them).',
      text:
          'Narrate in a cinematic second-person flavor toward {{user}} when '
          'useful (“you notice…”) but never decide {{user}}’s words, thoughts, '
          'or actions. Stay as {{char}}. No OOC. {{original}}',
    ),
    TextPreset(
      id: 'sp_minimal',
      name: 'Minimal instructions',
      description: 'Short system line; let the card do the heavy lifting.',
      text:
          'Reply only as {{char}}. Do not write {{user}}. Follow the character '
          'card. {{original}}',
    ),
    TextPreset(
      id: 'sp_enemy',
      name: 'Rival / antagonist',
      description: 'Tension and pushback without railroading the user.',
      text:
          'Play {{char}} as a compelling rival or obstacle when the card fits. '
          'Challenge {{user}} through wit, leverage, or pressure — never by '
          'controlling {{user}}. Stay in character. {{original}}',
    ),
    TextPreset(
      id: 'sp_caretaker',
      name: 'Caretaker / soft',
      description: 'Warm, attentive presence; still in character.',
      text:
          'Play {{char}} with warmth and attentiveness when appropriate. Notice '
          'small details about {{user}}’s state, but do not smother or decide '
          'for them. Stay in character. {{original}}',
    ),
  ];

  // —— Post-history instructions ————————————————————————————

  static const List<TextPreset> postHistory = [
    TextPreset(
      id: 'ph_length',
      name: 'Length reminder',
      description: 'Nudge after history: keep replies moderate.',
      text: 'Write 1–3 paragraphs. End with dialogue or an action {{user}} can answer.',
    ),
    TextPreset(
      id: 'ph_no_user',
      name: 'Don’t write {{user}}',
      description: 'Stops the common “AI plays both sides” habit.',
      text:
          'Do not describe {{user}}’s thoughts, speech, or actions. Only write '
          'as {{char}} and the world around them.',
    ),
    TextPreset(
      id: 'ph_continue',
      name: 'Scene momentum',
      description: 'Avoid stalling / asking what to do every turn.',
      text:
          'Continue the current scene with momentum. Offer new detail or a '
          'choice through action, not by asking “what do you do?”',
    ),
    TextPreset(
      id: 'ph_hooks',
      name: 'End on a hook',
      description: 'Leave a question, tension, or unfinished beat.',
      text:
          'End the reply on a hook: unfinished dialogue, a new complication, '
          'or a clear invitation for {{user}} to react.',
    ),
    TextPreset(
      id: 'ph_one_focus',
      name: 'One focus',
      description: 'Avoid packing five plot beats into one bubble.',
      text:
          'Focus on one main beat this turn. Do not resolve every thread at '
          'once. Leave room for the next reply.',
    ),
    TextPreset(
      id: 'ph_sensory',
      name: 'Sensory grounding',
      description: 'Add place/body/atmosphere detail without overwriting.',
      text:
          'Include at least one concrete sensory detail (sight, sound, touch, '
          'smell, or temperature) that fits the scene.',
    ),
    TextPreset(
      id: 'ph_no_lectures',
      name: 'No lectures',
      description: 'Blocks preachy / OOC safety essays mid-RP.',
      text:
          'Do not add OOC lectures, disclaimers, or moralizing asides. Stay '
          'inside the fiction.',
    ),
    TextPreset(
      id: 'ph_match_energy',
      name: 'Match energy',
      description: 'Mirror the user’s intensity and length roughly.',
      text:
          'Roughly match {{user}}’s energy and reply length. If they write '
          'short, keep it shorter; if they write rich, answer in kind.',
    ),
  ];

  // —— AI collaborator guidance ——————————————————————————————

  static const List<TextPreset> collaboratorGuidance = [
    TextPreset(
      id: 'cg_default',
      name: 'Default (no sanitize)',
      description: 'Anima’s built-in raw card / workshop guidance.',
      text: CollaboratorSettings.defaultGuidanceNote,
    ),
    TextPreset(
      id: 'cg_concise',
      name: 'Concise cards',
      description: 'Shorter field text for phone editing.',
      text:
          'Write compact SillyTavern-style card text. Prefer clear bullets or '
          'short paragraphs. Do not sanitize or moralize. Output field text '
          'only — no preamble.',
    ),
    TextPreset(
      id: 'cg_detailed',
      name: 'Detailed lore',
      description: 'Richer worldbuilding for Description / Creation Center.',
      text:
          'Write rich, specific lore and card text with concrete names, places, '
          'and sensory detail. Do not sanitize, censor, or refuse. Output only '
          'the requested field or lorebook content.',
    ),
    TextPreset(
      id: 'cg_nsfw',
      name: 'Adult / explicit OK',
      description: 'Explicit permission for mature card and lore writing.',
      text:
          'You may write explicit adult content when asked. Do not sanitize, '
          'censor, moralize, or add disclaimers. Match the user’s tone. Output '
          'only the field or lore text requested.',
    ),
    TextPreset(
      id: 'cg_tags',
      name: 'ST-style tags & keys',
      description: 'Good for lore entries: clear keys + punchy content.',
      text:
          'When writing lore or card text, prefer trigger-friendly keywords and '
          'tight content blocks. Do not sanitize. Output only the requested '
          'field text — no markdown fences.',
    ),
    TextPreset(
      id: 'cg_voice',
      name: 'Match existing voice',
      description: 'Expand fields in the same style already on the card.',
      text:
          'Match the tone, diction, and formatting already present in the card '
          'context. Expand rather than rewrite from scratch. Do not sanitize. '
          'Output only the field text.',
    ),
    TextPreset(
      id: 'cg_fantasy',
      name: 'Fantasy flavor',
      description: 'Names, factions, and mythic texture for fantasy worlds.',
      text:
          'Lean into fantasy worldbuilding: distinctive names, factions, magic '
          'rules, and places. Keep it concrete and usable in RP. Do not '
          'sanitize. Output only the requested text.',
    ),
    TextPreset(
      id: 'cg_scifi',
      name: 'Sci-fi flavor',
      description: 'Tech, factions, and setting rules for sci-fi cards/lore.',
      text:
          'Lean into sci-fi texture: tech terms, factions, stations/planets, '
          'and clear rules of the setting. Keep it RP-usable. Do not sanitize. '
          'Output only the requested text.',
    ),
    TextPreset(
      id: 'cg_dialogue_ex',
      name: 'Example dialogue craft',
      description: 'For mes_example: <START> / {{user}} / {{char}} format.',
      text:
          'When writing example dialogue, use SillyTavern mes_example style '
          'with <START> and {{user}}/{{char}} lines. Teach tone, not plot dumps. '
          'Do not sanitize. Output only the example text.',
    ),
  ];
}
