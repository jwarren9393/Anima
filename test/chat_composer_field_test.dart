import 'package:anima/widgets/chat_composer_field.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('shouldSendComposerOnEnter', () {
    test('plain Enter sends when enabled', () {
      expect(
        shouldSendComposerOnEnter(
          enterToSend: true,
          isKeyDown: true,
          key: LogicalKeyboardKey.enter,
          shift: false,
          control: false,
          meta: false,
          alt: false,
        ),
        isTrue,
      );
    });

    test('Shift+Enter does not send', () {
      expect(
        shouldSendComposerOnEnter(
          enterToSend: true,
          isKeyDown: true,
          key: LogicalKeyboardKey.enter,
          shift: true,
          control: false,
          meta: false,
          alt: false,
        ),
        isFalse,
      );
    });

    test('Ctrl+Enter does not send', () {
      expect(
        shouldSendComposerOnEnter(
          enterToSend: true,
          isKeyDown: true,
          key: LogicalKeyboardKey.enter,
          shift: false,
          control: true,
          meta: false,
          alt: false,
        ),
        isFalse,
      );
    });

    test('disabled when enterToSend is off', () {
      expect(
        shouldSendComposerOnEnter(
          enterToSend: false,
          isKeyDown: true,
          key: LogicalKeyboardKey.enter,
          shift: false,
          control: false,
          meta: false,
          alt: false,
        ),
        isFalse,
      );
    });

    test('numpad Enter sends', () {
      expect(
        shouldSendComposerOnEnter(
          enterToSend: true,
          isKeyDown: true,
          key: LogicalKeyboardKey.numpadEnter,
          shift: false,
          control: false,
          meta: false,
          alt: false,
        ),
        isTrue,
      );
    });
  });
}
