import 'package:anima/widgets/chat_composer_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';import 'package:flutter_test/flutter_test.dart';

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

  group('handleComposerEnterAction', () {
    test('non-empty text calls onSend', () {
      var sent = false;
      var continued = false;
      final controller = TextEditingController(text: 'hello');
      handleComposerEnterAction(
        controller: controller,
        onSend: () => sent = true,
        onContinue: () => continued = true,
      );
      expect(sent, isTrue);
      expect(continued, isFalse);
      controller.dispose();
    });

    test('empty text calls onContinue when set', () {
      var sent = false;
      var continued = false;
      final controller = TextEditingController();
      handleComposerEnterAction(
        controller: controller,
        onSend: () => sent = true,
        onContinue: () => continued = true,
      );
      expect(sent, isFalse);
      expect(continued, isTrue);
      controller.dispose();
    });

    test('empty text does nothing without onContinue', () {
      var sent = false;
      final controller = TextEditingController();
      handleComposerEnterAction(
        controller: controller,
        onSend: () => sent = true,
      );
      expect(sent, isFalse);
      controller.dispose();
    });
  });
}
