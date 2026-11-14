import 'package:flutter_test/flutter_test.dart';

import 'package:anima/services/avatar_prompt_builder.dart';
import 'package:anima/services/nanogpt_service.dart';

void main() {
  group('AvatarPromptBuilder', () {
    const builder = AvatarPromptBuilder();

    test('includes name and visual card details', () {
      final prompt = builder.buildPrompt(
        name: 'Mira',
        description: 'Dock smuggler in oilskin with dark hair.',
        personality: 'Wry and loyal.',
        scenario: 'Rainy night on the piers.',
        tags: const ['smuggler', 'harbor'],
      );
      expect(prompt, contains('Mira'));
      expect(prompt, contains('oilskin'));
      expect(prompt, contains('dark hair'));
      expect(prompt, contains('smuggler'));
      expect(prompt, contains('no watermark'));
    });

    test('skips non-visual personality, scenario, and backstory', () {
      final prompt = builder.buildPrompt(
        name: 'Seraphina',
        description: '''
Seraphina is a 28-year-old elven diplomat with silver hair and violet eyes. She wears an emerald silk gown with gold embroidery.

She grew up in the forest courts and learned statecraft from her mother. She despises corruption and will manipulate nobles when necessary.

Relationships: allied with the merchant guild; estranged from her brother Marcus.
''',
        personality:
            'Cunning, patient, fiercely loyal to her people. She never raises her voice but always gets what she wants through careful negotiation.',
        scenario:
            'A tense summit in the crystal palace where three kingdoms negotiate a trade treaty.',
        tags: const ['elf', 'diplomat', 'fantasy', 'roleplay'],
      );

      expect(prompt.length, lessThanOrEqualTo(AvatarPromptBuilder.maxPromptLength));
      expect(prompt, contains('silver hair'));
      expect(prompt, contains('violet eyes'));
      expect(prompt, contains('emerald silk gown'));
      expect(prompt, contains('elf'));
      expect(prompt, isNot(contains('manipulate nobles')));
      expect(prompt, isNot(contains('crystal palace')));
      expect(prompt, isNot(contains('Cunning, patient')));
      expect(prompt, isNot(contains('Style tags: elf, diplomat, fantasy, roleplay')));
    });

    test('works with empty optional fields', () {
      final prompt = builder.buildPrompt(name: '');
      expect(prompt, contains('a character'));
      expect(prompt, contains('Portrait avatar'));
      expect(prompt.length, lessThanOrEqualTo(AvatarPromptBuilder.maxPromptLength));
    });

    test('clips very long description under the NanoGPT limit', () {
      final long = List.filled(80, 'appearance detail').join(' ');
      final prompt = builder.buildPrompt(name: 'Vex', description: long);
      expect(prompt.length, lessThanOrEqualTo(AvatarPromptBuilder.maxPromptLength));
      expect(prompt, contains('…'));
    });

    test('buildPersonaPrompt prioritizes appearance over identity text', () {
      final prompt = builder.buildPersonaPrompt(
        name: 'Sam',
        description:
            'Soft-spoken cartographer with ink-stained fingers and a love of old maps.',
        appearance: 'Silver hair and a green travel cloak.',
        personality: 'Patient and curious.',
      );
      expect(prompt, contains('Sam'));
      expect(prompt, contains('player / user persona'));
      expect(prompt, contains('Silver hair'));
      expect(prompt, contains('green travel cloak'));
      expect(prompt, isNot(contains('love of old maps')));
      expect(prompt.length, lessThanOrEqualTo(AvatarPromptBuilder.maxPromptLength));
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
