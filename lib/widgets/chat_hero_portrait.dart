import 'dart:io';

import 'package:flutter/material.dart';

import '../services/avatar_service.dart';
import 'avatar_fullscreen.dart';

/// Fixed-size portrait tile inside a storybook bubble.
///
/// Size never grows with message length — it stays anchored to the top corner
/// while text wraps beside (and below) it. The inner edge fades to transparent
/// so the bubble background shows through seamlessly.
class ChatHeroPortraitStrip extends StatelessWidget {
  const ChatHeroPortraitStrip({
    super.key,
    required this.fileName,
    required this.label,
    required this.portraitOnStart,
    this.width = defaultWidth,
    this.height = defaultHeight,
    this.icon = Icons.person,
    this.avatarService,
    this.onLongPress,
  });

  static const defaultWidth = 76.0;
  static const defaultHeight = 112.0;

  final String? fileName;
  final String label;

  /// True when the portrait sits at the start of the bubble row (user / left).
  final bool portraitOnStart;
  final double width;
  final double height;
  final IconData icon;
  final AvatarService? avatarService;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final service = avatarService ?? AvatarService();
    final colorScheme = Theme.of(context).colorScheme;
    final initial = _initial(label);

    return SizedBox(
      width: width,
      height: height,
      child: FutureBuilder<String?>(
        key: ValueKey(fileName ?? label),
        future: service.resolvePath(fileName),
        builder: (context, snapshot) {
          final path = snapshot.data;
          final imageAlignment =
              portraitOnStart ? Alignment.topLeft : Alignment.topRight;

          Widget image = path != null
              ? Image.file(
                  File(path),
                  width: width,
                  height: height,
                  fit: BoxFit.cover,
                  alignment: imageAlignment,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) =>
                      _placeholder(colorScheme, initial),
                )
              : _placeholder(colorScheme, initial);

          image = ShaderMask(
            shaderCallback: (bounds) {
              return LinearGradient(
                begin: portraitOnStart
                    ? Alignment.centerLeft
                    : Alignment.centerRight,
                end: portraitOnStart
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
                colors: const [
                  Colors.white,
                  Colors.white,
                  Color(0xB3FFFFFF),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.28, 0.58, 1.0],
              ).createShader(bounds);
            },
            blendMode: BlendMode.dstIn,
            child: image,
          );

          return GestureDetector(
            onTap: () => showAvatarFullscreen(
              context,
              fileName: fileName,
              label: label,
              icon: icon,
              avatarService: service,
            ),
            onLongPress: onLongPress,
            child: image,
          );
        },
      ),
    );
  }

  Widget _placeholder(ColorScheme colorScheme, String? initial) {
    return ColoredBox(
      color: colorScheme.primaryContainer.withValues(alpha: 0.55),
      child: Center(
        child: initial != null
            ? Text(
                initial,
                style: TextStyle(
                  fontSize: width * 0.38,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onPrimaryContainer,
                ),
              )
            : Icon(
                icon,
                size: width * 0.42,
                color: colorScheme.onPrimaryContainer,
              ),
      ),
    );
  }

  static String? _initial(String label) {
    final trimmed = label.trim();
    if (trimmed.isEmpty) return null;
    return String.fromCharCode(trimmed.runes.first).toUpperCase();
  }
}
