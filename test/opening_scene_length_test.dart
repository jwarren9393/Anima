import 'package:flutter_test/flutter_test.dart';

import 'package:anima/models/opening_scene_length.dart';

void main() {
  test('OpeningSceneLength round-trips JSON', () {
    for (final length in OpeningSceneLength.values) {
      expect(OpeningSceneLength.fromJson(length.toJson()), length);
    }
    expect(OpeningSceneLength.fromJson('unknown'), OpeningSceneLength.medium);
  });

  test('OpeningSceneLength prompt hints mention target length', () {
    expect(OpeningSceneLength.short.promptHint.toLowerCase(), contains('short'));
    expect(OpeningSceneLength.long.promptHint.toLowerCase(), contains('long'));
  });
}
