import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Whether this key event is a standard Windows paste shortcut.
bool isWindowsPasteShortcut({
  required KeyEvent event,
  required bool control,
  required bool meta,
  required bool shift,
  required bool alt,
}) {
  if (event is! KeyDownEvent) return false;
  if (event.logicalKey == LogicalKeyboardKey.keyV &&
      (control || meta) &&
      !shift &&
      !alt) {
    return true;
  }
  if (event.logicalKey == LogicalKeyboardKey.insert && shift) {
    return true;
  }
  return false;
}

/// Routes Ctrl+V / Shift+Insert directly to the focused field on Windows.
///
/// Flutter's Windows embedder often drops synthesized paste shortcuts from
/// tools like Wispr Flow and clipboard history.
class WindowsPasteHandler {
  WindowsPasteHandler._();

  static bool _installed = false;

  static void install() {
    if (_installed) return;
    _installed = true;
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  static bool _onKey(KeyEvent event) {
    final keyboard = HardwareKeyboard.instance;
    if (!isWindowsPasteShortcut(
      event: event,
      control: keyboard.isControlPressed,
      meta: keyboard.isMetaPressed,
      shift: keyboard.isShiftPressed,
      alt: keyboard.isAltPressed,
    )) {
      return false;
    }
    _pasteToFocusedField();
    return true;
  }

  static Future<void> _pasteToFocusedField() async {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null) return;

    final editable = context.findAncestorStateOfType<EditableTextState>();
    if (editable == null) return;

    await editable.pasteText(SelectionChangedCause.keyboard);
  }
}
