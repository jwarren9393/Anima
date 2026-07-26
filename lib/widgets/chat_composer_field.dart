import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Whether [Enter] should send instead of inserting a newline.
bool shouldSendComposerOnEnter({
  required bool enterToSend,
  required bool isKeyDown,
  required LogicalKeyboardKey key,
  required bool shift,
  required bool control,
  required bool meta,
  required bool alt,
}) {
  if (!enterToSend || !isKeyDown) return false;
  if (key != LogicalKeyboardKey.enter && key != LogicalKeyboardKey.numpadEnter) {
    return false;
  }
  return !shift && !control && !meta && !alt;
}

/// Multiline chat composer with optional desktop Enter-to-send.
///
/// When [enterToSend] is true, plain Enter calls [onSend] and Shift+Enter
/// inserts a new line.
class ChatComposerField extends StatefulWidget {
  const ChatComposerField({
    super.key,
    required this.controller,
    required this.enabled,
    required this.decoration,
    required this.onSend,
    this.focusNode,
    this.enterToSend = false,
    this.minLines = 1,
    this.maxLines = 5,
    this.textCapitalization = TextCapitalization.sentences,
  });

  final TextEditingController controller;
  final bool enabled;
  final InputDecoration decoration;
  final VoidCallback onSend;
  final FocusNode? focusNode;
  final bool enterToSend;
  final int minLines;
  final int maxLines;
  final TextCapitalization textCapitalization;

  @override
  State<ChatComposerField> createState() => _ChatComposerFieldState();
}

class _ChatComposerFieldState extends State<ChatComposerField> {
  FocusNode? _ownedFocusNode;

  FocusNode get _focusNode => widget.focusNode ?? _ownedFocusNode!;

  @override
  void initState() {
    super.initState();
    if (widget.focusNode == null) {
      _ownedFocusNode = FocusNode(onKeyEvent: _onKey);
    }
  }

  @override
  void dispose() {
    _ownedFocusNode?.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final keyboard = HardwareKeyboard.instance;
    if (!shouldSendComposerOnEnter(
      enterToSend: widget.enterToSend && widget.enabled,
      isKeyDown: event is KeyDownEvent,
      key: event.logicalKey,
      shift: keyboard.isShiftPressed,
      control: keyboard.isControlPressed,
      meta: keyboard.isMetaPressed,
      alt: keyboard.isAltPressed,
    )) {
      return KeyEventResult.ignored;
    }

    widget.onSend();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final field = TextField(
      controller: widget.controller,
      focusNode: _focusNode,
      enabled: widget.enabled,
      minLines: widget.minLines,
      maxLines: widget.maxLines,
      textCapitalization: widget.textCapitalization,
      textInputAction:
          widget.enterToSend ? TextInputAction.send : TextInputAction.newline,
      decoration: widget.decoration,
      onSubmitted: widget.enterToSend
          ? (_) {
              if (widget.enabled) widget.onSend();
            }
          : null,
    );

    if (widget.focusNode != null) {
      return Focus(
        focusNode: _focusNode,
        onKeyEvent: _onKey,
        child: field,
      );
    }

    return field;
  }
}
