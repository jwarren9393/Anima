import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';

/// Cached blurred image behind the chat message list.
///
/// Wrapped in [RepaintBoundary] so the blur is rasterized once per
/// image/blur pair — not re-computed every scroll frame.
class ChatImageBackground extends StatelessWidget {
  const ChatImageBackground({
    super.key,
    required this.imagePath,
    required this.blurSigma,
    this.dimOpacity = 0.52,
  });

  final String imagePath;
  final double blurSigma;
  final double dimOpacity;

  @override
  Widget build(BuildContext context) {
    if (blurSigma <= 0.5) {
      return _buildStack(
        Image.file(
          File(imagePath),
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          gaplessPlayback: true,
          filterQuality: FilterQuality.medium,
        ),
      );
    }

    return RepaintBoundary(
      child: _buildStack(
        ImageFiltered(
          imageFilter: ImageFilter.blur(
            sigmaX: blurSigma,
            sigmaY: blurSigma,
          ),
          child: Image.file(
            File(imagePath),
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            gaplessPlayback: true,
            filterQuality: FilterQuality.low,
          ),
        ),
      ),
    );
  }

  Widget _buildStack(Widget image) {
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          image,
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: dimOpacity * 0.85),
                  Colors.black.withValues(alpha: dimOpacity),
                  Colors.black.withValues(alpha: dimOpacity * 1.1),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
