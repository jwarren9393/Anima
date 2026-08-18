import 'package:flutter/material.dart';

/// Sparkle wand with tap (quick expand) and long-press (full menu).
class FieldWandIconButton extends StatelessWidget {
  const FieldWandIconButton({
    super.key,
    required this.busy,
    required this.enabled,
    required this.onTap,
    required this.onLongPress,
  });

  final bool busy;
  final bool enabled;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'AI wand — tap quick expand, long-press for options',
      onPressed: enabled ? onTap : null,
      onLongPress: enabled ? onLongPress : null,
      icon: busy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.auto_awesome),
    );
  }
}
