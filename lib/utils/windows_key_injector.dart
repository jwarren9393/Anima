import 'dart:ui';

/// Fixes malformed synthesized Ctrl+V key events on Windows (clipboard history,
/// Wispr Flow, and similar tools that simulate paste).
///
/// See https://github.com/flutter/flutter/issues/143997
class WindowsKeyInjector {
  WindowsKeyInjector._();

  static bool _installed = false;
  static bool _injectingPaste = false;

  static void install() {
    if (_installed) return;
    _installed = true;

    // Wait for Flutter to register its built-in handler first.
    Future<void>.delayed(const Duration(seconds: 1), _wrapKeyDataCallback);
  }

  static void _wrapKeyDataCallback() {
    final callback = PlatformDispatcher.instance.onKeyData;
    if (callback == null) return;

    PlatformDispatcher.instance.onKeyData = (KeyData data) {
      if (!_injectingPaste &&
          data.physical == 0x1600000000 &&
          data.logical == 0x200000100 &&
          data.type == KeyEventType.down &&
          !data.synthesized) {
        _injectingPaste = true;
        data = KeyData(
          timeStamp: data.timeStamp,
          type: KeyEventType.down,
          physical: 0x700e0,
          logical: 0x200000100,
          character: null,
          synthesized: false,
        );
      } else if (_injectingPaste &&
          data.physical == 0 &&
          data.logical == 0 &&
          data.type == KeyEventType.down &&
          !data.synthesized) {
        return true;
      } else if (_injectingPaste &&
          data.physical == 0x1600000000 &&
          data.logical == 0x200000100 &&
          data.type == KeyEventType.up &&
          !data.synthesized) {
        data = KeyData(
          timeStamp: data.timeStamp,
          type: KeyEventType.down,
          physical: 0x70019,
          logical: 0x76,
          character: null,
          synthesized: false,
        );
      } else if (_injectingPaste &&
          data.physical == 0x1600000000 &&
          data.logical == 0x200000100 &&
          data.type == KeyEventType.down &&
          data.synthesized) {
        data = KeyData(
          timeStamp: data.timeStamp,
          type: KeyEventType.up,
          physical: 0x70019,
          logical: 0x76,
          character: null,
          synthesized: false,
        );
      } else if (_injectingPaste &&
          data.physical == 0x1600000000 &&
          data.logical == 0x200000100 &&
          data.type == KeyEventType.up &&
          data.synthesized) {
        data = KeyData(
          timeStamp: data.timeStamp,
          type: KeyEventType.up,
          physical: 0x700e0,
          logical: 0x200000100,
          character: null,
          synthesized: false,
        );
        _injectingPaste = false;
      } else {
        _injectingPaste = false;
      }

      return callback(data);
    };
  }
}
