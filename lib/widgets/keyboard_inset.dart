import 'package:flutter/material.dart';

/// Extra padding so a focused [TextField] can scroll above the keyboard.
const kAnimaKeyboardScrollPadding = EdgeInsets.fromLTRB(20, 24, 20, 120);

/// Lifts [child] by the on-screen keyboard height.
///
/// Use with [Scaffold.resizeToAvoidBottomInset] set to **false** (chat-style
/// layouts). Form screens should keep the Scaffold default (true) and rely on
/// [kAnimaKeyboardScrollPadding] on text fields instead.
class KeyboardInset extends StatelessWidget {
  const KeyboardInset({
    super.key,
    required this.child,
    this.animate = true,
  });

  final Widget child;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    if (!animate) {
      return Padding(
        padding: EdgeInsets.only(bottom: bottom),
        child: child,
      );
    }
    return AnimatedPadding(
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: bottom),
      child: child,
    );
  }
}
