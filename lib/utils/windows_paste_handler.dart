import 'package:flutter/scheduler.dart';
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

/// Modifier keys Wispr Flow / clipboard tools often leave "down" after a
/// synthetic Ctrl+V paste on Windows Flutter builds.
const _pasteModifierKeys = <(PhysicalKeyboardKey, LogicalKeyboardKey)>[
  (PhysicalKeyboardKey.controlLeft, LogicalKeyboardKey.controlLeft),
  (PhysicalKeyboardKey.controlRight, LogicalKeyboardKey.controlRight),
  (PhysicalKeyboardKey.metaLeft, LogicalKeyboardKey.metaLeft),
  (PhysicalKeyboardKey.metaRight, LogicalKeyboardKey.metaRight),
  (PhysicalKeyboardKey.altLeft, LogicalKeyboardKey.altLeft),
  (PhysicalKeyboardKey.altRight, LogicalKeyboardKey.altRight),
  (PhysicalKeyboardKey.shiftLeft, LogicalKeyboardKey.shiftLeft),
  (PhysicalKeyboardKey.shiftRight, LogicalKeyboardKey.shiftRight),
];

/// Release modifier keys Flutter still thinks are held after synthetic paste.
void releaseStuckPasteModifiers(HardwareKeyboard keyboard) {
  final pressed = keyboard.logicalKeysPressed;
  for (final (physical, logical) in _pasteModifierKeys) {
    if (!pressed.contains(logical)) continue;
    keyboard.handleKeyEvent(
      KeyUpEvent(
        physicalKey: physical,
        logicalKey: logical,
        timeStamp: Duration.zero,
        synthesized: true,
      ),
    );
  }
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
    _clearStuckModifiers();
  }

  static void _clearStuckModifiers() {
    final keyboard = HardwareKeyboard.instance;
    releaseStuckPasteModifiers(keyboard);
    SchedulerBinding.instance.addPostFrameCallback((_) {
      releaseStuckPasteModifiers(keyboard);
    });
  }
}
