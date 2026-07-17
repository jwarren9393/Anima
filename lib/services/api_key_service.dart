import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Saves and loads the NanoGPT API key from the device's secure storage.
///
/// On Android this uses the system Keystore (encrypted vault).
/// On Windows it uses the Windows Credential Manager.
/// On Linux it uses the desktop secret service (libsecret).
///
/// The key is NEVER written into project files, so it cannot leak to GitHub.
class ApiKeyService {
  ApiKeyService({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _apiKeyStorageKey = 'nanogpt_api_key';

  final FlutterSecureStorage _storage;

  /// Returns the saved API key, or null if none has been saved yet.
  Future<String?> getApiKey() async {
    final key = await _storage.read(key: _apiKeyStorageKey);
    if (key == null || key.trim().isEmpty) {
      return null;
    }
    return key.trim();
  }

  /// Saves the API key securely on this device.
  Future<void> saveApiKey(String apiKey) async {
    final trimmed = apiKey.trim();
    if (trimmed.isEmpty) {
      await clearApiKey();
      return;
    }
    await _storage.write(key: _apiKeyStorageKey, value: trimmed);
  }

  /// Removes the API key from this device.
  Future<void> clearApiKey() async {
    await _storage.delete(key: _apiKeyStorageKey);
  }

  /// True when a non-empty API key is stored.
  Future<bool> hasApiKey() async {
    final key = await getApiKey();
    return key != null;
  }
}
