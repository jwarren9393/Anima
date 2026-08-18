import 'package:flutter_test/flutter_test.dart';

import 'package:anima/services/speaker_prefix.dart';

void main() {
  group('stripLeadingSpeakerPrefix', () {
    test('removes Name: prefix', () {
      expect(
        stripLeadingSpeakerPrefix(
          'Morwenna Blackwood: Nineteen. The perfect age.',
          'Morwenna Blackwood',
        ),
        'Nineteen. The perfect age.',
      );
    });

    test('is case-insensitive and keeps body unchanged when no match', () {
      expect(
        stripLeadingSpeakerPrefix(
          'morwenna blackwood: Hello.',
          'Morwenna Blackwood',
        ),
        'Hello.',
      );
      expect(
        stripLeadingSpeakerPrefix('The girl is ready.', 'Morwenna Blackwood'),
        'The girl is ready.',
      );
    });

    test('handles markdown name and dash separators', () {
      expect(
        stripLeadingSpeakerPrefix('**Elara Vance:** Softly…', 'Elara Vance'),
        'Softly…',
      );
      expect(
        stripLeadingSpeakerPrefix('Elara Vance — Softly…', 'Elara Vance'),
        'Softly…',
      );
    });

    test('leaves text alone when name is empty', () {
      expect(
        stripLeadingSpeakerPrefix('Morwenna: hi', null),
        'Morwenna: hi',
      );
    });
  });
}
