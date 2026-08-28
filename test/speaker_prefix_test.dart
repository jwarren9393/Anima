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

    test('hides prefix-only partial during streaming', () {
      expect(
        stripLeadingSpeakerPrefix('Morwenna Blackwood:', 'Morwenna Blackwood'),
        '',
      );
      expect(
        stripLeadingSpeakerPrefix('**Elara Vance:**', 'Elara Vance'),
        '',
      );
    });
  });

  group('stripLeadingCastPrefix', () {
    test('strips any cast member prefix', () {
      expect(
        stripLeadingCastPrefix(
          'Ashley: *steps forward*',
          ['Mira', 'Ashley', 'Jay'],
        ),
        '*steps forward*',
      );
      expect(
        stripLeadingCastPrefix(
          'Mira: Hello.',
          ['Mira', 'Ashley'],
        ),
        'Hello.',
      );
    });

    test('leaves text alone when no cast prefix matches', () {
      expect(
        stripLeadingCastPrefix(
          'The room is quiet.',
          ['Mira', 'Ashley'],
        ),
        'The room is quiet.',
      );
    });
  });
}
