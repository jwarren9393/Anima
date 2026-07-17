import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anima/models/ui_style_settings.dart';
import 'package:anima/theme/anima_theme.dart';

void main() {
  AnimaTheme.useSystemFonts = true;

  test('UiStyleSettings round-trips avatar JSON', () {
    const style = UiStyleSettings(
      avatarStyle: AvatarStyleSettings(
        shape: AvatarShape.roundedRect,
        sizeTier: AvatarSizeTier.large,
        scale: 1.25,
      ),
    );
    final restored = UiStyleSettings.fromJson(style.toJson());
    expect(restored.avatarStyle.shape, AvatarShape.roundedRect);
    expect(restored.avatarStyle.sizeTier, AvatarSizeTier.large);
    expect(restored.avatarStyle.scale, closeTo(1.25, 0.001));
  });

  test('legacy appearance JSON still yields avatar settings', () {
    final restored = UiStyleSettings.fromJson({
      'preset': 'parchment',
      'showTexture': true,
      'avatarShape': 'square',
      'avatarSize': 'small',
      'avatarScale': 0.9,
    });
    expect(restored.avatarStyle.shape, AvatarShape.square);
    expect(restored.avatarStyle.sizeTier, AvatarSizeTier.small);
    expect(restored.avatarStyle.scale, closeTo(0.9, 0.001));
  });

  test('dark theme includes glass AnimaUiTheme extension', () {
    final theme = AnimaTheme.dark();
    final ui = theme.extension<AnimaUiTheme>();
    expect(ui, isNotNull);
    expect(ui!.chatBubbleRadius, greaterThan(0));
    expect(theme.colorScheme.brightness, Brightness.dark);
    expect(theme.colorScheme.primary, AnimaTheme.gold);
  });
}
