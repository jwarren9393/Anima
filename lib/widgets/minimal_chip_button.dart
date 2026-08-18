import 'package:flutter/material.dart';

/// Compact tappable chip used across minimal UI chrome (chat, setup, filters).
class MinimalChipButton extends StatelessWidget {
  const MinimalChipButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.selected = false,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fg = selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant;
    final bg = selected
        ? scheme.primaryContainer
        : scheme.surfaceContainerHighest.withValues(alpha: 0.85);

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: fg),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(color: fg),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Horizontal row wrapper for [MinimalChipButton] chips.
class MinimalChipRow extends StatelessWidget {
  const MinimalChipRow({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(children: children),
    );
  }
}
