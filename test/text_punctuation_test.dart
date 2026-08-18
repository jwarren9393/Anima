import 'package:flutter_test/flutter_test.dart';

import 'package:anima/utils/text_punctuation.dart';

void main() {
  test('normalizeEmDashes converts double hyphens', () {
    expect(normalizeEmDashes('Wait--what?'), 'Wait—what?');
    expect(normalizeEmDashes('a--b--c'), 'a—b—c');
    expect(normalizeEmDashes('---'), '—-');
    expect(normalizeEmDashes('----'), '——');
  });

  test('normalizeEmDashes leaves text without double hyphens', () {
    expect(normalizeEmDashes('Hello—already'), 'Hello—already');
    expect(normalizeEmDashes('single-dash'), 'single-dash');
    expect(normalizeEmDashes(''), '');
  });
}
