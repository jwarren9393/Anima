import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anima/models/theme_palette.dart';
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
    expect(restored.presetId, ThemePresets.obsidianGold.id);
  });

  test(
    'legacy appearance JSON still yields avatar settings + default theme',
    () {
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
      expect(restored.presetId, ThemePresets.obsidianGold.id);
    },
  );

  test('full theme JSON round-trips custom palette', () {
    final style = UiStyleSettings.fromPreset(ThemePresets.cyberViolet).copyWith(
      palette: ThemePresets.cyberViolet.palette.copyWith(
        accent: const Color(0xFFFF00AA),
      ),
      markCustom: true,
    );
    final restored = UiStyleSettings.fromJson(style.toJson());
    expect(restored.presetId, ThemePresets.customId);
    expect(restored.visualStyle, VisualStyle.solid);
    expect(restored.palette.accent.toARGB32(), 0xFFFF00AA);
  });

  test('all presets build ThemeData with readable text contrast', () {
    for (final preset in ThemePresets.all) {
      final settings = UiStyleSettings.fromPreset(preset);
      final theme = AnimaTheme.fromSettings(settings);
      expect(theme.extension<AnimaUiTheme>(), isNotNull);
      final ratio = ThemePalette.contrastRatio(
        preset.palette.text,
        preset.palette.background,
      );
      expect(ratio, greaterThan(3.5), reason: preset.name);
    }
  });

  test('dark() default remains Obsidian Gold accent', () {
    final theme = AnimaTheme.dark();
    final ui = theme.extension<AnimaUiTheme>();
    expect(ui, isNotNull);
    expect(ui!.chatBubbleRadius, greaterThan(0));
    expect(theme.colorScheme.primary, AnimaTheme.gold);
  });

  test('ivory ink produces light brightness', () {
    final theme = AnimaTheme.fromSettings(
      UiStyleSettings.fromPreset(ThemePresets.ivoryInk),
    );
    expect(theme.brightness, Brightness.light);
    expect(theme.scaffoldBackgroundColor, isNot(Colors.transparent));
  });
}
