import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Non-secret app preferences stored on this device only.
///
/// The AI model name is not a secret, but we reuse secure storage so we do not
/// add extra packages yet. It still never goes to GitHub.
class SettingsService {
  SettingsService({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  /// A sensible default NanoGPT model id. Change it anytime in Settings.
  static const defaultModel = 'openai/gpt-4o-mini';

  static const _modelStorageKey = 'nanogpt_model';

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
}
