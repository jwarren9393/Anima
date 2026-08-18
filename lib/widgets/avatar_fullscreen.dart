import 'dart:io';

import 'package:flutter/material.dart';

import '../services/avatar_service.dart';
import 'anima_avatar.dart';

/// Opens a full-screen portrait view. Tap anywhere to close.
Future<void> showAvatarFullscreen(
  BuildContext context, {
  required String? fileName,
  String label = '',
  IconData icon = Icons.person,
  AvatarService? avatarService,
}) {
  return Navigator.of(context).push<void>(
    PageRouteBuilder<void>(
      opaque: false,
      barrierDismissible: true,
      pageBuilder: (context, animation, secondaryAnimation) {
        return _AvatarFullscreenPage(
          fileName: fileName,
          label: label,
          icon: icon,
          avatarService: avatarService,
        );
      },
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(opacity: animation, child: child);
      },
    ),
  );
}

class _AvatarFullscreenPage extends StatelessWidget {
  const _AvatarFullscreenPage({
    required this.fileName,
    required this.label,
    required this.icon,
    this.avatarService,
  });

  final String? fileName;
  final String label;
  final IconData icon;
  final AvatarService? avatarService;

  @override
  Widget build(BuildContext context) {
    final service = avatarService ?? AvatarService();

    return GestureDetector(
      onTap: () => Navigator.pop(context),
      behavior: HitTestBehavior.opaque,
      child: Scaffold(
        backgroundColor: Colors.black.withValues(alpha: 0.94),
        body: SafeArea(
          child: Stack(
            children: [
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 48),
                  child: FutureBuilder<String?>(
                    future: service.resolvePath(fileName),
                    builder: (context, snapshot) {
                      final path = snapshot.data;
                      if (path != null) {
                        return Image.file(
                          File(path),
                          fit: BoxFit.contain,
                          width: double.infinity,
                          height: double.infinity,
                          errorBuilder: (_, _, _) => _fallbackPortrait(context),
                        );
                      }
                      return _fallbackPortrait(context);
                    },
                  ),
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: Colors.white70),
                ),
              ),
              if (label.trim().isNotEmpty)
                Positioned(
                  left: 20,
                  right: 20,
                  bottom: 16,
                  child: Text(
                    label.trim(),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Colors.white70,
                        ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fallbackPortrait(BuildContext context) {
    return AnimaAvatar(
      fileName: fileName,
      label: label,
      radius: 120,
      icon: icon,
      avatarService: avatarService,
      interactive: false,
    );
  }
}
