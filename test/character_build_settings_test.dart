import 'package:flutter_test/flutter_test.dart';

import 'package:anima/services/settings_service.dart';

void main() {
  group('CharacterBuildSettings', () {
    test('resolvedModel uses main chat model when enabled', () {
      const settings = CharacterBuildSettings(
        useMainChatModel: true,
        modelId: 'anthropic/claude-sonnet',
      );
      expect(settings.resolvedModel('openai/gpt-4o-mini'), 'openai/gpt-4o-mini');
    });

    test('resolvedModel uses override when main chat model is off', () {
      const settings = CharacterBuildSettings(
        useMainChatModel: false,
        modelId: 'google/gemini-2.0-flash',
      );
      expect(
        settings.resolvedModel('openai/gpt-4o-mini'),
        'google/gemini-2.0-flash',
      );
    });

    test('toSampling clamps values', () {
      const settings = CharacterBuildSettings(
        maxTokens: 99999,
        temperature: 5,
        topP: 2,
      );
      final sampling = settings.toSampling();
      expect(sampling.maxTokens, 8192);
      expect(sampling.temperature, 2.0);
      expect(sampling.topP, 1.0);
    });

    test('effectivePromptNote falls back to default', () {
      const settings = CharacterBuildSettings(promptNote: '   ');
      expect(
        settings.effectivePromptNote(),
        CharacterBuildSettings.defaultPromptNote,
      );
    });
  });
}
