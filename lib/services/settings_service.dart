import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Non-secret app preferences stored on this device only.
///
/// Preferences are not secrets, but we reuse secure storage so we keep the
/// dependency list small. Nothing here is committed to GitHub.
class SettingsService {
  SettingsService({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  /// A sensible default NanoGPT model id. Change it anytime in Settings.
  static const defaultModel = 'openai/gpt-4o-mini';

  static const _modelStorageKey = 'nanogpt_model';
  static const _selectedCharacterKey = 'selected_character_id';

  final FlutterSecureStorage _storage;

  /// Returns the saved model id, or [defaultModel] if none is saved.
  Future<String> getModel() async {
    final value = await _storage.read(key: _modelStorageKey);
    if (value == null || value.trim().isEmpty) {
      return defaultModel;
    }
    return value.trim();
  }

  /// Saves the NanoGPT model id (for example `openai/gpt-4o-mini`).
  Future<void> saveModel(String model) async {
    final trimmed = model.trim();
    if (trimmed.isEmpty) {
      await _storage.delete(key: _modelStorageKey);
      return;
    }
    await _storage.write(key: _modelStorageKey, value: trimmed);
  }

  /// Returns the id of the character you are currently chatting with, if any.
  Future<String?> getSelectedCharacterId() async {
    final value = await _storage.read(key: _selectedCharacterKey);
    if (value == null || value.trim().isEmpty) return null;
    return value.trim();
  }

  /// Remembers which character is selected for chat.
  Future<void> saveSelectedCharacterId(String? id) async {
    if (id == null || id.trim().isEmpty) {
      await _storage.delete(key: _selectedCharacterKey);
      return;
    }
    await _storage.write(key: _selectedCharacterKey, value: id.trim());
  }
}
