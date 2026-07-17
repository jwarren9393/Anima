import 'package:flutter_tts/flutter_tts.dart';

/// Optional text-to-speech for reading assistant messages aloud.
///
/// Uses the device's built-in voices. Failures are soft — chat still works
/// if TTS is unavailable on a platform.
class TtsService {
  TtsService({FlutterTts? tts}) : _tts = tts ?? FlutterTts();

  final FlutterTts _tts;
  bool _ready = false;

  Future<void> _ensureReady() async {
    if (_ready) return;
    try {
      await _tts.setSpeechRate(0.45);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
      _ready = true;
    } catch (_) {
      // Keep trying later; some platforms init lazily.
    }
  }

  Future<void> speak(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    await _ensureReady();
    try {
      await _tts.stop();
      await _tts.speak(trimmed);
    } catch (_) {
      // Ignore — TTS is optional.
    }
  }

  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }

  void dispose() {
    // FlutterTts has no dispose; stop is enough.
    stop();
  }
}
