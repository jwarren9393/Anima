import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anima/models/chat_experience_settings.dart';

void main() {
  test('ChatExperienceSettings storybook preset values', () {
    const s = ChatExperienceSettings.storybook;
    expect(s.layoutMode, ChatLayoutMode.storybook);
    expect(s.backgroundEnabled, isTrue);
    expect(s.showSpeakerHeader, isTrue);
    expect(s.showSideHeroPortrait, isTrue);
    expect(s.backgroundBlur, 16);
    expect(s.bubbleOpacity, closeTo(0.48, 0.001));
  });

  test('ChatExperienceSettings round-trips JSON', () {
    const original = ChatExperienceSettings(
      layoutMode: ChatLayoutMode.storybook,
      backgroundEnabled: true,
      backgroundImageFileName: 'chat_bg_1.jpg',
      backgroundBlur: 12,
      showSpeakerHeader: true,
      bubbleOpacity: 0.55,
      showSideHeroPortrait: true,
    );
    final restored = ChatExperienceSettings.fromJson(original.toJson());
    expect(restored.layoutMode, original.layoutMode);
    expect(restored.backgroundEnabled, original.backgroundEnabled);
    expect(restored.backgroundImageFileName, original.backgroundImageFileName);
    expect(restored.backgroundBlur, original.backgroundBlur);
    expect(restored.showSpeakerHeader, original.showSpeakerHeader);
    expect(restored.showSideHeroPortrait, original.showSideHeroPortrait);
    expect(restored.bubbleOpacity, original.bubbleOpacity);
  });

  test('classic mode defaults stay off', () {
    final restored = ChatExperienceSettings.fromJson({
      'chatLayoutMode': 'classic',
    });
    expect(restored.backgroundEnabled, isFalse);
    expect(restored.showSpeakerHeader, isFalse);
    expect(restored.showSideHeroPortrait, isFalse);
    expect(restored.bubbleOpacity, 1.0);
  });

  test('bubbleFill scales palette alpha', () {
    const settings = ChatExperienceSettings(bubbleOpacity: 0.5);
    const color = Color(0x80FF0000);
    final fill = settings.bubbleFill(color);
    expect(fill.a, closeTo(0.25, 0.01));
  });

  test('legacy portrait background key still loads', () {
    final restored = ChatExperienceSettings.fromJson({
      'chatLayoutMode': 'classic',
      'chatPortraitBackground': true,
      'chatPortraitBlur': 8,
    });
    expect(restored.backgroundEnabled, isTrue);
    expect(restored.backgroundBlur, 8);
  });
}
