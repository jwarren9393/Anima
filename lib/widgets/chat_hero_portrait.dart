import 'dart:io';

import 'package:flutter/material.dart';

import '../services/avatar_service.dart';
import 'avatar_fullscreen.dart';

/// Tall side portrait beside a storybook message bubble.
///
/// The inner edge fades into the bubble so the image feels attached to the
/// message, not a separate column on the screen.
class ChatHeroPortrait extends StatelessWidget {
  const ChatHeroPortrait({
    super.key,
    required this.fileName,
    required this.label,
    required this.onLeft,
    this.height = 136,
    this.width = 74,
    this.icon = Icons.person,
    this.avatarService,
    this.onLongPress,
  });

  final String? fileName;
  final String label;

  /// When true the portrait sits on the left (user messages).
  final bool onLeft;
  final double height;
  final double width;
  final IconData icon;
  final AvatarService? avatarService;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final service = avatarService ?? AvatarService();
    final colorScheme = Theme.of(context).colorScheme;
    final initial = _initial(label);

    return FutureBuilder<String?>(
      key: ValueKey(fileName ?? label),
      future: service.resolvePath(fileName),
      builder: (context, snapshot) {
        final path = snapshot.data;
        final image = path != null
            ? Image.file(
                File(path),
                width: width,
                height: height,
                fit: BoxFit.cover,
                alignment: onLeft ? Alignment.centerLeft : Alignment.centerRight,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => _placeholder(
                  colorScheme,
                  initial,
                ),
              )
            : _placeholder(colorScheme, initial);

        final faded = ShaderMask(
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: onLeft ? Alignment.centerRight : Alignment.centerLeft,
              end: onLeft ? Alignment.centerLeft : Alignment.centerRight,
              colors: const [
                Colors.white,
                Colors.white,
                Colors.transparent,
              ],
              stops: const [0.0, 0.42, 1.0],
            ).createShader(bounds);
          },
          blendMode: BlendMode.dstIn,
          child: image,
        );

        final portrait = RepaintBoundary(
          child: SizedBox(
            width: width,
            height: height,
            child: ClipRRect(
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(10),
                topRight: const Radius.circular(10),
                bottomLeft: Radius.circular(onLeft ? 4 : 10),
                bottomRight: Radius.circular(onLeft ? 10 : 4),
              ),
              child: faded,
            ),
          ),
        );

        return Transform.translate(
          offset: Offset(onLeft ? 16 : -16, 0),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => showAvatarFullscreen(
                context,
                fileName: fileName,
                label: label,
                icon: icon,
                avatarService: service,
              ),
              onLongPress: onLongPress,
              child: portrait,
            ),
          ),
        );
      },
    );
  }

  Widget _placeholder(ColorScheme colorScheme, String? initial) {
    return Container(
      width: width,
      height: height,
      color: colorScheme.primaryContainer.withValues(alpha: 0.65),
      alignment: Alignment.center,
      child: initial != null
          ? Text(
              initial,
              style: TextStyle(
                fontSize: width * 0.42,
                fontWeight: FontWeight.w600,
                color: colorScheme.onPrimaryContainer,
              ),
            )
          : Icon(icon, size: width * 0.45, color: colorScheme.onPrimaryContainer),
    );
  }

  static String? _initial(String label) {
    final trimmed = label.trim();
    if (trimmed.isEmpty) return null;
    return String.fromCharCode(trimmed.runes.first).toUpperCase();
  }
}
