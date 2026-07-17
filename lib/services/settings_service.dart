import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Generation knobs sent with each NanoGPT chat request.
class SamplingSettings {
  const SamplingSettings({
    this.temperature = defaultTemperature,
    this.topP = defaultTopP,
    this.maxTokens,
  });

  static const defaultTemperature = 0.8;
  static const defaultTopP = 0.95;

  /// 0–2. Higher = more random / creative.
  final double temperature;

  /// 0–1. Nucleus sampling; 1.0 ≈ off.
  final double topP;

  /// Upper bound on reply length. Null = let NanoGPT / the model decide.
  final int? maxTokens;

  SamplingSettings copyWith({
    double? temperature,
    double? topP,
    int? maxTokens,
    bool clearMaxTokens = false,
  }) {
    return SamplingSettings(
      temperature: temperature ?? this.temperature,
      topP: topP ?? this.topP,
      maxTokens: clearMaxTokens ? null : (maxTokens ?? this.maxTokens),
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
  static const _useSubscriptionKey = 'nanogpt_use_subscription';
  static const _themeModeKey = 'theme_mode';
  static const _ttsEnabledKey = 'tts_enabled';

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

  /// Temperature, top_p, and optional max_tokens.
  Future<SamplingSettings> getSampling() async {
    final tempRaw = await _storage.read(key: _temperatureKey);
    final topPRaw = await _storage.read(key: _topPKey);
    final maxRaw = await _storage.read(key: _maxTokensKey);

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
    );
  }

  Future<void> saveSampling(SamplingSettings settings) async {
    await _storage.write(
      key: _temperatureKey,
      value: settings.temperature.toString(),
    );
    await _storage.write(
      key: _topPKey,
      value: settings.topP.toString(),
    );
    if (settings.maxTokens == null || settings.maxTokens! <= 0) {
      await _storage.delete(key: _maxTokensKey);
    } else {
      await _storage.write(
        key: _maxTokensKey,
        value: '${settings.maxTokens}',
      );
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

  /// system / light / dark
  Future<String> getThemeModeName() async {
    final value = await _storage.read(key: _themeModeKey);
    switch (value) {
      case 'light':
      case 'dark':
        return value!;
      default:
        return 'system';
    }
  }

  Future<void> saveThemeModeName(String mode) async {
    final normalized = mode.trim().toLowerCase();
    if (normalized != 'light' && normalized != 'dark' && normalized != 'system') {
      await _storage.delete(key: _themeModeKey);
      return;
    }
    await _storage.write(key: _themeModeKey, value: normalized);
  }

  Future<bool> getTtsEnabled() async {
    final value = await _storage.read(key: _ttsEnabledKey);
    return value == 'true' || value == '1';
  }

  Future<void> saveTtsEnabled(bool enabled) async {
    await _storage.write(
      key: _ttsEnabledKey,
      value: enabled ? 'true' : 'false',
    );
  }
}
