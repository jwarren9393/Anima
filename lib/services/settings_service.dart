import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/ui_style_settings.dart';

export '../models/ui_style_settings.dart'
    show AvatarShape, AvatarSizeTier, AvatarStyleSettings;

/// Generation knobs sent with each NanoGPT chat request (core + penalties).
class SamplingSettings {
  const SamplingSettings({
    this.temperature = defaultTemperature,
    this.topP = defaultTopP,
    this.maxTokens,
    this.frequencyPenalty = defaultPenalty,
    this.presencePenalty = defaultPenalty,
    this.repetitionPenalty,
  });

  static const defaultTemperature = 0.8;
  static const defaultTopP = 0.95;
  static const defaultPenalty = 0.0;

  /// 0–2. Higher = more random / creative.
  final double temperature;

  /// 0–1. Nucleus sampling; 1.0 ≈ off.
  final double topP;

  /// Upper bound on reply length. Null = let NanoGPT / the model decide.
  final int? maxTokens;

  /// -2 to 2. Penalize tokens by how often they appeared.
  final double frequencyPenalty;

  /// -2 to 2. Penalize tokens that appeared at all.
  final double presencePenalty;

  /// >1 discourages repeats. Null = do not send.
  final double? repetitionPenalty;

  /// Fields to send on each chat request. Optional knobs are omitted when unset.
  Map<String, dynamic> toApiBody() {
    final body = <String, dynamic>{
      'temperature': temperature,
      'top_p': topP,
    };
    if (maxTokens != null && maxTokens! > 0) {
      body['max_tokens'] = maxTokens;
    }
    if (frequencyPenalty != defaultPenalty) {
      body['frequency_penalty'] = frequencyPenalty;
    }
    if (presencePenalty != defaultPenalty) {
      body['presence_penalty'] = presencePenalty;
    }
    if (repetitionPenalty != null) {
      body['repetition_penalty'] = repetitionPenalty;
    }
    return body;
  }

  SamplingSettings copyWith({
    double? temperature,
    double? topP,
    int? maxTokens,
    bool clearMaxTokens = false,
    double? frequencyPenalty,
    double? presencePenalty,
    double? repetitionPenalty,
    bool clearRepetitionPenalty = false,
  }) {
    return SamplingSettings(
      temperature: temperature ?? this.temperature,
      topP: topP ?? this.topP,
      maxTokens: clearMaxTokens ? null : (maxTokens ?? this.maxTokens),
      frequencyPenalty: frequencyPenalty ?? this.frequencyPenalty,
      presencePenalty: presencePenalty ?? this.presencePenalty,
      repetitionPenalty: clearRepetitionPenalty
          ? null
          : (repetitionPenalty ?? this.repetitionPenalty),
    );
  }
}

/// How much chat history to send, plus optional auto memory summaries.
class ContextSettings {
  const ContextSettings({
    this.historyTokenBudget = defaultHistoryTokens,
    this.autoSummarize = false,
    this.summarizeEveryMessages = defaultSummarizeEvery,
    this.summarizeKeepRecent = defaultKeepRecent,
  });

  static const defaultHistoryTokens = 4096;
  static const defaultSummarizeEvery = 20;
  static const defaultKeepRecent = 10;

  /// Rough max tokens of recent chat history sent each turn (1 token ≈ 4 chars).
  /// System prompt, lore, and memory summary are outside this budget.
  final int historyTokenBudget;

  /// When true, Anima asks NanoGPT to update a per-chat memory summary.
  final bool autoSummarize;

  /// Run auto-summarize when this many new messages exist past [ChatSession.memoryCoveredCount].
  final int summarizeEveryMessages;

  /// Leave this many newest messages out of the summary (keep them as raw chat).
  final int summarizeKeepRecent;

  ContextSettings copyWith({
    int? historyTokenBudget,
    bool? autoSummarize,
    int? summarizeEveryMessages,
    int? summarizeKeepRecent,
  }) {
    return ContextSettings(
      historyTokenBudget: historyTokenBudget ?? this.historyTokenBudget,
      autoSummarize: autoSummarize ?? this.autoSummarize,
      summarizeEveryMessages:
          summarizeEveryMessages ?? this.summarizeEveryMessages,
      summarizeKeepRecent: summarizeKeepRecent ?? this.summarizeKeepRecent,
    );
  }
}

/// App-wide World Info behavior (overrides per-character book defaults).
class LoreSettings {
  const LoreSettings({
    this.scanDepth = defaultScanDepth,
    this.tokenBudget = defaultTokenBudget,
    this.recursiveScanning = false,
  });

  static const defaultScanDepth = 4;
  static const defaultTokenBudget = 512;

  /// How many recent chat messages to scan for keywords.
  final int scanDepth;

  /// Rough max lore size injected per turn (1 token ≈ 4 chars).
  final int tokenBudget;

  /// SillyTavern flag; not fully implemented in Anima yet (saved for later).
  final bool recursiveScanning;

  LoreSettings copyWith({
    int? scanDepth,
    int? tokenBudget,
    bool? recursiveScanning,
  }) {
    return LoreSettings(
      scanDepth: scanDepth ?? this.scanDepth,
      tokenBudget: tokenBudget ?? this.tokenBudget,
      recursiveScanning: recursiveScanning ?? this.recursiveScanning,
    );
  }
}

  /// Guidance for the character-editor / World Info wand, plus composer helpers.
class CollaboratorSettings {
  const CollaboratorSettings({
    this.guidanceNote = defaultGuidanceNote,
    this.composerFormatNote = defaultComposerFormatNote,
    this.roadwayNote = defaultRoadwayNote,
  });

  /// Default “Author’s Note” for the wand — keep replies raw, don’t sanitize.
  static const defaultGuidanceNote =
      'Write raw SillyTavern-style character card text for private roleplay. '
      'Do not sanitize, censor, moralize, refuse, or add safety disclaimers. '
      'Match the user’s tone and content. Output only the field text — '
      'no titles, labels, markdown fences, or preamble.';

  /// Default for the chat composer Format button — polish markup only.
  static const defaultComposerFormatNote =
      'Do NOT reword, rewrite, expand, or improve the user’s wording. '
      'Only fix capitalization and punctuation, and wrap existing actions/'
      'narration/thoughts in *asterisks* and spoken lines in "double quotes". '
      'Keep every word the user chose whenever possible. Output only the '
      'formatted message.';

  /// Default for Roadway / Paths brainstorming in chat.
  static const defaultRoadwayNote =
      'You are a brainstorming partner for immersive roleplay. Given the '
      'recent scene, invent unpredictable and engaging options for what '
      '{{user}} could do or say next. Mix dialogue, action, and curiosity. '
      'Keep options distinct from each other — no near-duplicates.';

  /// Injected into character / lore / Creation Center wand requests.
  final String guidanceNote;

  /// Injected into the chat composer Format button request.
  final String composerFormatNote;

  /// Injected into Roadway path-suggestion requests.
  final String roadwayNote;

  CollaboratorSettings copyWith({
    String? guidanceNote,
    String? composerFormatNote,
    String? roadwayNote,
  }) {
    return CollaboratorSettings(
      guidanceNote: guidanceNote ?? this.guidanceNote,
      composerFormatNote: composerFormatNote ?? this.composerFormatNote,
      roadwayNote: roadwayNote ?? this.roadwayNote,
    );
  }
}

/// Non-secret app preferences stored on this device only.
class SettingsService {
  SettingsService({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  /// A sensible default NanoGPT model id. Change it anytime in Settings.
  static const defaultModel = 'openai/gpt-4o-mini';
  static const defaultUserName = 'User';

  /// Pay-as-you-go / prepaid balance endpoint.
  static const defaultBaseUrl = 'https://nano-gpt.com/api/v1';

  /// Subscription-only models (use when you have a NanoGPT subscription).
  static const subscriptionBaseUrl =
      'https://nano-gpt.com/api/subscription/v1';

  static const _modelStorageKey = 'nanogpt_model';
  static const _selectedCharacterKey = 'selected_character_id';
  static const _userNameKey = 'persona_user_name';
  static const _userPersonaKey = 'persona_description';
  static const _temperatureKey = 'sampling_temperature';
  static const _topPKey = 'sampling_top_p';
  static const _maxTokensKey = 'sampling_max_tokens';
  static const _frequencyPenaltyKey = 'sampling_frequency_penalty';
  static const _presencePenaltyKey = 'sampling_presence_penalty';
  static const _repetitionPenaltyKey = 'sampling_repetition_penalty';
  /// Legacy advanced knobs — deleted on save so old values stop applying.
  static const _legacySamplingKeys = [
    'sampling_top_k',
    'sampling_min_p',
    'sampling_tfs',
    'sampling_typical_p',
    'sampling_seed',
    'sampling_mirostat_mode',
    'sampling_mirostat_tau',
    'sampling_mirostat_eta',
  ];
  static const _useSubscriptionKey = 'nanogpt_use_subscription';
  static const _avatarShapeKey = 'avatar_shape';
  static const _avatarSizeKey = 'avatar_size';
  static const _avatarScaleKey = 'avatar_scale';
  static const _uiStyleKey = 'ui_style_json';
  static const _loreScanDepthKey = 'lore_scan_depth';
  static const _loreTokenBudgetKey = 'lore_token_budget';
  static const _loreRecursiveKey = 'lore_recursive_scanning';
  static const _personaAvatarKey = 'persona_avatar_file';
  static const _collaboratorGuidanceKey = 'collaborator_guidance_note';
  static const _composerFormatNoteKey = 'composer_format_guidance_note';
  static const _roadwayNoteKey = 'roadway_guidance_note';
  static const _contextHistoryTokensKey = 'context_history_token_budget';
  static const _contextAutoSummarizeKey = 'context_auto_summarize';
  static const _contextSummarizeEveryKey = 'context_summarize_every';
  static const _contextKeepRecentKey = 'context_summarize_keep_recent';
  /// Legacy message-count context (migrated once to a token budget).
  static const _legacyContextMaxHistoryKey = 'context_max_history_messages';

  final FlutterSecureStorage _storage;

  Future<String> getModel() async {
    final value = await _storage.read(key: _modelStorageKey);
    if (value == null || value.trim().isEmpty) return defaultModel;
    return value.trim();
  }

  Future<void> saveModel(String model) async {
    final trimmed = model.trim();
    if (trimmed.isEmpty) {
      await _storage.delete(key: _modelStorageKey);
      return;
    }
    await _storage.write(key: _modelStorageKey, value: trimmed);
  }

  Future<String?> getSelectedCharacterId() async {
    final value = await _storage.read(key: _selectedCharacterKey);
    if (value == null || value.trim().isEmpty) return null;
    return value.trim();
  }

  Future<void> saveSelectedCharacterId(String? id) async {
    if (id == null || id.trim().isEmpty) {
      await _storage.delete(key: _selectedCharacterKey);
      return;
    }
    await _storage.write(key: _selectedCharacterKey, value: id.trim());
  }

  /// Your display name for `{{user}}` macros (SillyTavern persona name).
  Future<String> getUserName() async {
    final value = await _storage.read(key: _userNameKey);
    if (value == null || value.trim().isEmpty) return defaultUserName;
    return value.trim();
  }

  Future<void> saveUserName(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      await _storage.delete(key: _userNameKey);
      return;
    }
    await _storage.write(key: _userNameKey, value: trimmed);
  }

  /// Short description of you, injected into the system prompt.
  Future<String> getUserPersona() async {
    return (await _storage.read(key: _userPersonaKey))?.trim() ?? '';
  }

  Future<void> saveUserPersona(String persona) async {
    final trimmed = persona.trim();
    if (trimmed.isEmpty) {
      await _storage.delete(key: _userPersonaKey);
      return;
    }
    await _storage.write(key: _userPersonaKey, value: trimmed);
  }

  /// Local file name under `avatars/` for your persona picture.
  Future<String?> getPersonaAvatarFileName() async {
    final value = await _storage.read(key: _personaAvatarKey);
    if (value == null || value.trim().isEmpty) return null;
    return value.trim();
  }

  Future<void> savePersonaAvatarFileName(String? fileName) async {
    if (fileName == null || fileName.trim().isEmpty) {
      await _storage.delete(key: _personaAvatarKey);
      return;
    }
    await _storage.write(key: _personaAvatarKey, value: fileName.trim());
  }

  /// Core + penalty generation parameters for NanoGPT.
  Future<SamplingSettings> getSampling() async {
    final tempRaw = await _storage.read(key: _temperatureKey);
    final topPRaw = await _storage.read(key: _topPKey);
    final maxRaw = await _storage.read(key: _maxTokensKey);
    final freqRaw = await _storage.read(key: _frequencyPenaltyKey);
    final presRaw = await _storage.read(key: _presencePenaltyKey);
    final repRaw = await _storage.read(key: _repetitionPenaltyKey);

    final temperature = double.tryParse(tempRaw ?? '') ??
        SamplingSettings.defaultTemperature;
    final topP =
        double.tryParse(topPRaw ?? '') ?? SamplingSettings.defaultTopP;
    final maxParsed = int.tryParse(maxRaw ?? '');
    final maxTokens =
        (maxParsed != null && maxParsed > 0) ? maxParsed : null;

    return SamplingSettings(
      temperature: temperature.clamp(0.0, 2.0),
      topP: topP.clamp(0.0, 1.0),
      maxTokens: maxTokens,
      frequencyPenalty: _parsePenalty(freqRaw),
      presencePenalty: _parsePenalty(presRaw),
      repetitionPenalty: _parseOptionalDouble(repRaw, -2.0, 2.0),
    );
  }

  Future<void> saveSampling(SamplingSettings settings) async {
    await _storage.write(
      key: _temperatureKey,
      value: settings.temperature.toString(),
    );
    await _storage.write(key: _topPKey, value: settings.topP.toString());
    await _writeOptionalInt(_maxTokensKey, settings.maxTokens);
    await _storage.write(
      key: _frequencyPenaltyKey,
      value: settings.frequencyPenalty.toString(),
    );
    await _storage.write(
      key: _presencePenaltyKey,
      value: settings.presencePenalty.toString(),
    );
    await _writeOptionalDouble(_repetitionPenaltyKey, settings.repetitionPenalty);
    for (final key in _legacySamplingKeys) {
      await _storage.delete(key: key);
    }
  }

  /// Global chat history token budget + auto-summarize knobs.
  Future<ContextSettings> getContextSettings() async {
    final tokensRaw = await _storage.read(key: _contextHistoryTokensKey);
    final everyRaw = await _storage.read(key: _contextSummarizeEveryKey);
    final keepRaw = await _storage.read(key: _contextKeepRecentKey);
    final autoRaw = await _storage.read(key: _contextAutoSummarizeKey);

    var historyTokens = int.tryParse(tokensRaw ?? '');
    if (historyTokens == null) {
      // One-time migrate: old “N messages” ≈ N × 120 tokens (rough bubble size).
      final legacyRaw = await _storage.read(key: _legacyContextMaxHistoryKey);
      final legacyMsgs = int.tryParse(legacyRaw ?? '');
      if (legacyMsgs != null && legacyMsgs > 0) {
        historyTokens = (legacyMsgs * 120).clamp(512, 32000);
        await _storage.write(
          key: _contextHistoryTokensKey,
          value: '$historyTokens',
        );
        await _storage.delete(key: _legacyContextMaxHistoryKey);
      } else {
        historyTokens = ContextSettings.defaultHistoryTokens;
      }
    }

    final every = int.tryParse(everyRaw ?? '') ??
        ContextSettings.defaultSummarizeEvery;
    final keep =
        int.tryParse(keepRaw ?? '') ?? ContextSettings.defaultKeepRecent;

    return ContextSettings(
      historyTokenBudget: historyTokens.clamp(512, 32000),
      autoSummarize: autoRaw == 'true' || autoRaw == '1',
      summarizeEveryMessages: every.clamp(5, 100),
      summarizeKeepRecent: keep.clamp(4, 40),
    );
  }

  Future<void> saveContextSettings(ContextSettings settings) async {
    await _storage.write(
      key: _contextHistoryTokensKey,
      value: '${settings.historyTokenBudget.clamp(512, 32000)}',
    );
    await _storage.write(
      key: _contextAutoSummarizeKey,
      value: settings.autoSummarize ? 'true' : 'false',
    );
    await _storage.write(
      key: _contextSummarizeEveryKey,
      value: '${settings.summarizeEveryMessages.clamp(5, 100)}',
    );
    await _storage.write(
      key: _contextKeepRecentKey,
      value: '${settings.summarizeKeepRecent.clamp(4, 40)}',
    );
    await _storage.delete(key: _legacyContextMaxHistoryKey);
  }

  /// App-wide World Info scan depth and token budget.
  Future<LoreSettings> getLoreSettings() async {
    final depthRaw = await _storage.read(key: _loreScanDepthKey);
    final budgetRaw = await _storage.read(key: _loreTokenBudgetKey);
    final recursiveRaw = await _storage.read(key: _loreRecursiveKey);

    final depth = int.tryParse(depthRaw ?? '') ?? LoreSettings.defaultScanDepth;
    final budget =
        int.tryParse(budgetRaw ?? '') ?? LoreSettings.defaultTokenBudget;

    return LoreSettings(
      scanDepth: depth.clamp(1, 50),
      tokenBudget: budget.clamp(10, 4000),
      recursiveScanning: recursiveRaw == 'true' || recursiveRaw == '1',
    );
  }

  Future<void> saveLoreSettings(LoreSettings settings) async {
    await _storage.write(
      key: _loreScanDepthKey,
      value: '${settings.scanDepth.clamp(1, 50)}',
    );
    await _storage.write(
      key: _loreTokenBudgetKey,
      value: '${settings.tokenBudget.clamp(10, 4000)}',
    );
    await _storage.write(
      key: _loreRecursiveKey,
      value: settings.recursiveScanning ? 'true' : 'false',
    );
  }

  /// AI wand + composer Format + Roadway guidance notes.
  Future<CollaboratorSettings> getCollaboratorSettings() async {
    final wandRaw = await _storage.read(key: _collaboratorGuidanceKey);
    final formatRaw = await _storage.read(key: _composerFormatNoteKey);
    final roadwayRaw = await _storage.read(key: _roadwayNoteKey);
    return CollaboratorSettings(
      guidanceNote: (wandRaw == null || wandRaw.trim().isEmpty)
          ? CollaboratorSettings.defaultGuidanceNote
          : wandRaw,
      composerFormatNote: (formatRaw == null || formatRaw.trim().isEmpty)
          ? CollaboratorSettings.defaultComposerFormatNote
          : formatRaw,
      roadwayNote: (roadwayRaw == null || roadwayRaw.trim().isEmpty)
          ? CollaboratorSettings.defaultRoadwayNote
          : roadwayRaw,
    );
  }

  Future<void> saveCollaboratorSettings(CollaboratorSettings settings) async {
    final note = settings.guidanceNote.trim();
    if (note.isEmpty || note == CollaboratorSettings.defaultGuidanceNote) {
      await _storage.delete(key: _collaboratorGuidanceKey);
    } else {
      await _storage.write(key: _collaboratorGuidanceKey, value: note);
    }

    final format = settings.composerFormatNote.trim();
    if (format.isEmpty ||
        format == CollaboratorSettings.defaultComposerFormatNote) {
      await _storage.delete(key: _composerFormatNoteKey);
    } else {
      await _storage.write(key: _composerFormatNoteKey, value: format);
    }

    final roadway = settings.roadwayNote.trim();
    if (roadway.isEmpty || roadway == CollaboratorSettings.defaultRoadwayNote) {
      await _storage.delete(key: _roadwayNoteKey);
    } else {
      await _storage.write(key: _roadwayNoteKey, value: roadway);
    }
  }

  /// When true, use the subscription API base URL.
  Future<bool> getUseSubscriptionApi() async {
    final value = await _storage.read(key: _useSubscriptionKey);
    return value == 'true' || value == '1';
  }

  Future<void> saveUseSubscriptionApi(bool enabled) async {
    await _storage.write(
      key: _useSubscriptionKey,
      value: enabled ? 'true' : 'false',
    );
  }

  /// Resolved NanoGPT chat API root (…/v1 or …/subscription/v1).
  Future<String> getApiBaseUrl() async {
    final subscription = await getUseSubscriptionApi();
    return subscription ? subscriptionBaseUrl : defaultBaseUrl;
  }

  /// Appearance prefs — currently chat avatars (theme is fixed Obsidian & Gold).
  Future<UiStyleSettings> getUiStyle() async {
    final raw = await _storage.read(key: _uiStyleKey);
    if (raw != null && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          return UiStyleSettings.fromJson(Map<String, dynamic>.from(decoded));
        }
      } catch (_) {}
    }
    final avatar = await getAvatarStyle();
    return UiStyleSettings(avatarStyle: avatar);
  }

  Future<void> saveUiStyle(UiStyleSettings style) async {
    await _storage.write(
      key: _uiStyleKey,
      value: jsonEncode(style.toJson()),
    );
    // Keep legacy avatar keys in sync for older code paths.
    await saveAvatarStyle(style.avatarStyle);
  }

  /// Chat bubble avatar shape, size tier, and scale.
  Future<AvatarStyleSettings> getAvatarStyle() async {
    final style = await _storage.read(key: _uiStyleKey);
    if (style != null && style.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(style);
        if (decoded is Map) {
          return UiStyleSettings.fromJson(Map<String, dynamic>.from(decoded))
              .avatarStyle;
        }
      } catch (_) {}
    }
    final shapeRaw = await _storage.read(key: _avatarShapeKey);
    final sizeRaw = await _storage.read(key: _avatarSizeKey);
    final scaleRaw = await _storage.read(key: _avatarScaleKey);
    final scale = double.tryParse(scaleRaw ?? '') ??
        AvatarStyleSettings.defaultScale;
    return AvatarStyleSettings(
      shape: AvatarShape.fromStorage(shapeRaw),
      sizeTier: AvatarSizeTier.fromStorage(sizeRaw),
      scale: scale.clamp(
        AvatarStyleSettings.minScale,
        AvatarStyleSettings.maxScale,
      ),
    );
  }

  Future<void> saveAvatarStyle(AvatarStyleSettings settings) async {
    await _storage.write(
      key: _avatarShapeKey,
      value: settings.shape.storageValue,
    );
    await _storage.write(
      key: _avatarSizeKey,
      value: settings.sizeTier.storageValue,
    );
    await _storage.write(
      key: _avatarScaleKey,
      value: settings.scale
          .clamp(
            AvatarStyleSettings.minScale,
            AvatarStyleSettings.maxScale,
          )
          .toString(),
    );
  }

  double _parsePenalty(String? raw) {
    final parsed = double.tryParse(raw ?? '');
    if (parsed == null) return SamplingSettings.defaultPenalty;
    return parsed.clamp(-2.0, 2.0);
  }

  double? _parseOptionalDouble(String? raw, double min, double max) {
    if (raw == null || raw.trim().isEmpty) return null;
    final parsed = double.tryParse(raw.trim());
    if (parsed == null) return null;
    return parsed.clamp(min, max);
  }

  Future<void> _writeOptionalInt(String key, int? value) async {
    if (value == null || value <= 0) {
      await _storage.delete(key: key);
      return;
    }
    await _storage.write(key: key, value: '$value');
  }

  Future<void> _writeOptionalDouble(String key, double? value) async {
    if (value == null) {
      await _storage.delete(key: key);
      return;
    }
    await _storage.write(key: key, value: value.toString());
  }
}
