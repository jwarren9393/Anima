import 'package:flutter_test/flutter_test.dart';

import 'package:anima/services/presence_service.dart';
import 'package:anima/utils/rp_observable_text.dart';

void main() {
  const presence = PresenceService();

  group('sanitizeStagingTextForCharacter', () {
    const narrator =
        'The next morning, Michael comes downstairs and sees the girls sleeping on the couch. '
        'He has no idea that Amanda fooled around with him last night. Neither does Ashley.';

    test('Ashley does not receive secret clauses', () {
      final out = presence.sanitizeStagingTextForCharacter(
        text: narrator,
        focusCharacterName: 'Ashley Heart',
        castNames: ['Michael Heart', 'Amanda Williams', 'Ashley Heart'],
      );
      expect(out, contains('comes downstairs'));
      expect(out, isNot(contains('no idea')));
      expect(out, isNot(contains('fool')));
      expect(out, isNot(contains('Neither does Ashley')));
    });

    test('Amanda keeps secret she is named in', () {
      final out = presence.sanitizeStagingTextForCharacter(
        text: narrator,
        focusCharacterName: 'Amanda Williams',
        castNames: ['Michael Heart', 'Amanda Williams', 'Ashley Heart'],
      );
      expect(out, contains('no idea'));
      expect(out, contains('Amanda'));
    });

    test('Michael drops obliviousness sentence with secret', () {
      final out = presence.sanitizeStagingTextForCharacter(
        text: narrator,
        focusCharacterName: 'Michael Heart',
        castNames: ['Michael Heart', 'Amanda Williams', 'Ashley Heart'],
      );
      expect(out, contains('comes downstairs'));
      expect(out, isNot(contains('fool')));
    });
  });

  group('observableRpTextForOthers', () {
    test('strips internal thought asterisks but keeps dialogue and visible actions', () {
      const raw =
          '*I follow her up the stairs.* "Yeah, I know." *My hands are still shaking.*';
      final out = observableRpTextForOthers(raw);
      expect(out, contains('Yeah, I know'));
      expect(out, contains('follow her up the stairs'));
      expect(out, isNot(contains('still shaking')));
    });

    test('keeps visible actions toward another person', () {
      expect(
        observableRpTextForOthers('*I reach out to shake his hand.*'),
        contains('shake his hand'),
      );
      expect(
        observableRpTextForOthers('*I rub the top of her head playfully.*'),
        contains('rub the top of her head'),
      );
    });

    test('keeps solo visible physical actions', () {
      expect(
        observableRpTextForOthers('*I groan into the couch cushion.*'),
        contains('groan into the couch'),
      );
    });

    test('isLikelyPrivateThought classifies internal vs visible', () {
      expect(isLikelyPrivateThought("I can't believe I did that"), isTrue);
      expect(isLikelyPrivateThought('My hands are still shaking'), isTrue);
      expect(isLikelyPrivateThought('I reach out to shake his hand'), isFalse);
      expect(isLikelyPrivateThought('I rub the top of her head'), isFalse);
      expect(isLikelyPrivateThought('I groan into the couch cushion'), isFalse);
    });
  });
}
