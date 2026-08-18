import 'dart:io';

import 'package:flutter/material.dart';

import '../services/avatar_service.dart';
import '../services/settings_service.dart';
import 'avatar_fullscreen.dart';

/// Avatar that loads a local file, or shows initials / an icon.
///
/// List screens can keep using [radius] (circle). Chat uses [style] for
/// shape, size, and scale from Appearance settings.
///
/// When [interactive] is true (default), tap opens a full-screen portrait
/// unless [onTap] is set. Use [onLongPress] for a secondary action (e.g.
/// edit card from chat).
class AnimaAvatar extends StatelessWidget {
  const AnimaAvatar({
    super.key,
    this.fileName,
    this.label = '',
    this.radius = 24,
    this.style,
    this.icon = Icons.person,
    this.avatarService,
    this.onTap,
    this.onLongPress,
    this.interactive = true,
  });

  /// Relative name under `avatars/` (from [AvatarService]).
  final String? fileName;

  /// Used for a letter initial when there is no image.
  final String label;

  /// Circle radius when [style] is null (list tiles, editors).
  final double radius;

  /// Chat / Appearance style. When set, overrides [radius].
  final AvatarStyleSettings? style;

  final IconData icon;
  final AvatarService? avatarService;

  /// Custom tap handler. When null and [interactive] is true, opens fullscreen.
  final VoidCallback? onTap;

  final VoidCallback? onLongPress;

  /// When true, tap opens the portrait viewer unless [onTap] is set.
  final bool interactive;

  Size get _dimensions {
    if (style != null) {
      final height = style!.resolvedSize;
      final width = switch (style!.shape) {
        AvatarShape.roundedRect => height * 0.78,
        AvatarShape.circle || AvatarShape.square => height,
      };
      return Size(width, height);
    }
    final d = radius * 2;
    return Size(d, d);
  }

  BorderRadius get _borderRadius {
    final dims = _dimensions;
    if (style == null) {
      return BorderRadius.circular(dims.shortestSide / 2);
    }
    return switch (style!.shape) {
      AvatarShape.circle => BorderRadius.circular(dims.shortestSide / 2),
      AvatarShape.square => BorderRadius.circular(8),
      AvatarShape.roundedRect => BorderRadius.circular(12),
    };
  }

  ShapeBorder get _tapShape {
    if (style == null || style!.shape == AvatarShape.circle) {
      return const CircleBorder();
    }
    return RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(
        style!.shape == AvatarShape.square ? 8 : 12,
      ),
    );
  }

  void _handleTap(BuildContext context) {
    if (onTap != null) {
      onTap!();
      return;
    }
    if (!interactive) return;
    showAvatarFullscreen(
      context,
      fileName: fileName,
      label: label,
      icon: icon,
      avatarService: avatarService,
    );
  }

  @override
  Widget build(BuildContext context) {
    final service = avatarService ?? AvatarService();
    final colorScheme = Theme.of(context).colorScheme;
    final initial = _initial(label);
    final dims = _dimensions;
    final fontSize = dims.shortestSide * 0.42;
    final iconSize = dims.shortestSide * 0.5;
    final canInteract = interactive;

    return FutureBuilder<String?>(
      key: ValueKey(fileName ?? ''),
      future: service.resolvePath(fileName),
      builder: (context, snapshot) {
        final path = snapshot.data;
        final hasImage = path != null;

        final core = ClipRRect(
          borderRadius: _borderRadius,
          child: Container(
            width: dims.width,
            height: dims.height,
            color: colorScheme.primaryContainer,
            alignment: Alignment.center,
            child: hasImage
                ? Image.file(
                    File(path),
                    width: dims.width,
                    height: dims.height,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => _placeholder(
                      colorScheme,
                      initial,
                      fontSize,
                      iconSize,
                    ),
                  )
                : _placeholder(colorScheme, initial, fontSize, iconSize),
          ),
        );

        if (!canInteract && onLongPress == null) return core;

        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: canInteract ? () => _handleTap(context) : null,
            onLongPress: onLongPress,
            customBorder: _tapShape,
            child: core,
          ),
        );
      },
    );
  }

  Widget _placeholder(
    ColorScheme colorScheme,
    String? initial,
    double fontSize,
    double iconSize,
  ) {
    if (initial != null) {
      return Text(
        initial,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
          color: colorScheme.onPrimaryContainer,
        ),
      );
    }
    return Icon(icon, size: iconSize, color: colorScheme.onPrimaryContainer);
  }

  static String? _initial(String label) {
    final trimmed = label.trim();
    if (trimmed.isEmpty) return null;
    return String.fromCharCode(trimmed.runes.first).toUpperCase();
  }
}
