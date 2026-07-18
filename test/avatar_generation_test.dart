import 'package:flutter_test/flutter_test.dart';

import 'package:anima/services/avatar_prompt_builder.dart';
import 'package:anima/services/nanogpt_service.dart';

void main() {
  group('AvatarPromptBuilder', () {
    const builder = AvatarPromptBuilder();

    test('includes name and card fields', () {
      final prompt = builder.buildPrompt(
        name: 'Mira',
        description: 'Dock smuggler in oilskin with dark hair.',
        personality: 'Wry and loyal.',
        scenario: 'Rainy night on the piers.',
        tags: const ['smuggler', 'harbor'],
      );
      expect(prompt, contains('Mira'));
      expect(prompt, contains('oilskin'));
      expect(prompt, contains('Wry and loyal'));
      expect(prompt, contains('piers'));
      expect(prompt, contains('smuggler'));
      expect(prompt, contains('no watermark'));
    });

    test('works with empty optional fields', () {
      final prompt = builder.buildPrompt(name: '');
      expect(prompt, contains('a character'));
      expect(prompt, contains('Portrait avatar'));
    });

    test('clips very long description', () {
      final long = List.filled(80, 'appearance detail').join(' ');
      final prompt = builder.buildPrompt(
        name: 'Vex',
        description: long,
      );
      expect(prompt.length, lessThan(long.length + 200));
      expect(prompt, contains('…'));
    });

    test('buildPersonaPrompt uses name and about text', () {
      final prompt = builder.buildPersonaPrompt(
        name: 'Sam',
        description: 'Soft-spoken cartographer with ink-stained fingers.',
      );
      expect(prompt, contains('Sam'));
      expect(prompt, contains('player / user persona'));
      expect(prompt, contains('cartographer'));
      expect(prompt, contains('no watermark'));
    });

    test('buildPersonaPrompt works with empty fields', () {
      final prompt = builder.buildPersonaPrompt(name: '');
      expect(prompt, contains('a person'));
      expect(prompt, contains('Portrait avatar'));
    });
  });

  group('NanoGptImageModelInfo', () {
    test('prefers square resolution when available', () {
      const model = NanoGptImageModelInfo(
        id: 'test',
        ownedBy: 'x',
        name: 'Test',
        resolutions: ['1376x768', '1024x1024', '1184x896'],
      );
      expect(model.preferredSquareResolution, '1024x1024');
    });

    test('falls back to first resolution', () {
      const model = NanoGptImageModelInfo(
        id: 'test',
        ownedBy: 'x',
        name: 'Test',
        resolutions: ['1376x768'],
      );
      expect(model.preferredSquareResolution, '1376x768');
    });

    test('accepts symbolic square sizes', () {
      const model = NanoGptImageModelInfo(
        id: 'test',
        ownedBy: 'x',
        name: 'Test',
        resolutions: ['landscape_16_9', 'square_hd'],
        subscriptionIncluded: true,
      );
      expect(model.preferredSquareResolution, 'square_hd');
      expect(model.subscriptionIncluded, isTrue);
    });
  });

  group('NanoGptModelInfo context', () {
    test('parses context_length and formats labels', () {
      expect(
        NanoGptModelInfo.parseContextLength({'context_length': 128000}),
        128000,
      );
      expect(
        NanoGptModelInfo.parseContextLength({'contextLength': 16000}),
        16000,
      );
      expect(NanoGptModelInfo.parseContextLength({}), isNull);

      const model = NanoGptModelInfo(
        id: 'demo',
        ownedBy: 'openai',
        name: 'Demo',
        contextLength: 16000,
        maxOutputTokens: 4096,
      );
      expect(model.contextLabel, '16K ctx');
      expect(model.displayNameWithContext, 'Demo · 16K ctx');
      expect(NanoGptModelInfo.formatTokenCount(128000), '128K');
    });
  });
}
