import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anima/models/ui_style_settings.dart';
import 'package:anima/theme/anima_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  AnimaTheme.useSystemFonts = true;

  test('UiStyleSettings round-trips JSON with color overrides', () {
    const style = UiStyleSettings(
      preset: VisualPreset.ember,
      primaryColor: Color(0xFF112233),
      fontPairing: FontPairing.cleanSans,
      fontScale: 1.1,
      chatFontScale: 1.2,
      backgroundStyle: BackgroundStyle.softGradient,
      showTexture: false,
      motion: MotionPreference.slow,
      density: UiDensity.compact,
    );
    final restored = UiStyleSettings.fromJson(style.toJson());
    expect(restored.preset, VisualPreset.ember);
    expect(restored.primaryColor?.toARGB32(), 0xFF112233);
    expect(restored.fontPairing, FontPairing.cleanSans);
    expect(restored.fontScale, closeTo(1.1, 0.001));
    expect(restored.showTexture, isFalse);
    expect(restored.motion, MotionPreference.slow);
    expect(restored.density, UiDensity.compact);
  });

  test('withPreset clears color overrides', () {
    final styled = const UiStyleSettings(
      primaryColor: Color(0xFFABCDEF),
    ).withPreset(VisualPreset.midnight);
    expect(styled.preset, VisualPreset.midnight);
    expect(styled.primaryColor, isNull);
  });

  test('AnimaTheme builds light and dark for each preset', () {
    for (final preset in VisualPreset.values) {
      final style = UiStyleSettings(preset: preset);
      final light = AnimaTheme.light(style);
      final dark = AnimaTheme.dark(style);
      expect(light.brightness, Brightness.light);
      expect(dark.brightness, Brightness.dark);
      expect(light.extension<AnimaUiTheme>(), isNotNull);
    }
  });
}
