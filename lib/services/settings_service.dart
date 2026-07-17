import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Non-secret app preferences stored on this device only.
class SettingsService {
  SettingsService({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  /// A sensible default NanoGPT model id. Change it anytime in Settings.
  static const defaultModel = 'openai/gpt-4o-mini';
  static const defaultUserName = 'User';

  static const _modelStorageKey = 'nanogpt_model';
  static const _selectedCharacterKey = 'selected_character_id';
  static const _userNameKey = 'persona_user_name';
  static const _userPersonaKey = 'persona_description';

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
}
