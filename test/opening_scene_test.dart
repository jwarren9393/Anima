import 'package:flutter_test/flutter_test.dart';

import 'package:anima/services/prompt_builder.dart';

void main() {
  const builder = PromptBuilder();

  test('buildOpeningSceneBlock applies macros and framing', () {
    final block = builder.buildOpeningSceneBlock(
      openingScene: '{{user}} arrives while {{char}} waits.',
      charName: 'Lyra',
      userName: 'Jay',
    );

    expect(block, contains('Opening scene'));
    expect(block, contains('Jay arrives while Lyra waits.'));
    expect(block, contains('background'));
  });

  test('buildOpeningSceneBlock returns empty for blank scene', () {
    expect(
      builder.buildOpeningSceneBlock(
        openingScene: '   ',
        charName: 'Lyra',
        userName: 'Jay',
      ),
      '',
    );
  });
}
