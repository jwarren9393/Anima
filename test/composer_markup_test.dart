import 'package:flutter_test/flutter_test.dart';

import 'package:anima/utils/composer_markup.dart';

void main() {
  group('autoWrapDialogue', () {
    test('wraps plain speech between actions', () {
      expect(
        autoWrapDialogue('*steps closer* what do you want *crosses arms*'),
        '*steps closer* "what do you want" *crosses arms*',
      );
    });

    test('wraps plain-only messages', () {
      expect(autoWrapDialogue('hey there'), '"hey there"');
    });

    test('leaves action-only messages unchanged', () {
      expect(
        autoWrapDialogue('*internal thought only*'),
        '*internal thought only*',
      );
    });

    test('leaves existing dialogue unchanged', () {
      expect(
        autoWrapDialogue('*nods* "already quoted"'),
        '*nods* "already quoted"',
      );
    });

    test('does not double-wrap quoted plain text', () {
      expect(
        autoWrapDialogue('"hello there"'),
        '"hello there"',
      );
    });
  });
}
