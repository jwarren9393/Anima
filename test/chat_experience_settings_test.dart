import 'package:flutter_test/flutter_test.dart';

import 'package:anima/models/chat_experience_settings.dart';

void main() {
  test('ChatExperienceSettings storybook preset values', () {
    const s = ChatExperienceSettings.storybook;
    expect(s.layoutMode, ChatLayoutMode.storybook);
    expect(s.portraitBackground, isTrue);
    expect(s.showSpeakerHeader, isTrue);
    expect(s.portraitBlur, 16);
  });

  test('ChatExperienceSettings round-trips JSON', () {
    const original = ChatExperienceSettings.storybook;
    final restored = ChatExperienceSettings.fromJson(original.toJson());
    expect(restored.layoutMode, original.layoutMode);
    expect(restored.portraitBackground, original.portraitBackground);
    expect(restored.portraitBlur, original.portraitBlur);
    expect(restored.showSpeakerHeader, original.showSpeakerHeader);
  });

  test('classic mode defaults stay off', () {
    final restored = ChatExperienceSettings.fromJson({
      'chatLayoutMode': 'classic',
    });
    expect(restored.portraitBackground, isFalse);
    expect(restored.showSpeakerHeader, isFalse);
  });
}
