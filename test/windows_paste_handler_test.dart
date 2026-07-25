import 'package:anima/utils/windows_paste_handler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isWindowsPasteShortcut', () {
    test('Ctrl+V is paste', () {
      expect(
        isWindowsPasteShortcut(
          event: KeyDownEvent(
            physicalKey: PhysicalKeyboardKey.keyV,
            logicalKey: LogicalKeyboardKey.keyV,
            timeStamp: Duration.zero,
          ),
          control: true,
          meta: false,
          shift: false,
          alt: false,
        ),
        isTrue,
      );
    });

    test('Shift+Insert is paste', () {
      expect(
        isWindowsPasteShortcut(
          event: KeyDownEvent(
            physicalKey: PhysicalKeyboardKey.insert,
            logicalKey: LogicalKeyboardKey.insert,
            timeStamp: Duration.zero,
          ),
          control: false,
          meta: false,
          shift: true,
          alt: false,
        ),
        isTrue,
      );
    });

    test('plain Enter is not paste', () {
      expect(
        isWindowsPasteShortcut(
          event: KeyDownEvent(
            physicalKey: PhysicalKeyboardKey.enter,
            logicalKey: LogicalKeyboardKey.enter,
            timeStamp: Duration.zero,
          ),
          control: false,
          meta: false,
          shift: false,
          alt: false,
        ),
        isFalse,
      );
    });
  });
}
