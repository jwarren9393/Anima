/// How long Creation Center opening-scene exports should be.
enum OpeningSceneLength {
  short,
  medium,
  long;

  String get label => switch (this) {
        OpeningSceneLength.short => 'Short',
        OpeningSceneLength.medium => 'Medium',
        OpeningSceneLength.long => 'Long',
      };

  String get subtitle => switch (this) {
        OpeningSceneLength.short => 'Quick setup · ~40–80 words',
        OpeningSceneLength.medium => 'Balanced · ~80–200 words',
        OpeningSceneLength.long => 'Detailed · ~200–400 words',
      };

  String get promptHint => switch (this) {
        OpeningSceneLength.short =>
          'Keep the opening scene SHORT (~40–80 words): place, mood, and what is '
          'happening right now. Minimal dialogue — one line at most.',
        OpeningSceneLength.medium =>
          'Keep the opening scene MEDIUM length (~80–200 words): vivid setup with '
          'key atmosphere and stakes. At most a few short dialogue lines.',
        OpeningSceneLength.long =>
          'Opening scene may be LONGER (~200–400 words): rich atmosphere, sensory '
          'detail, and context. Dialogue only when it sets the scene.',
      };

  static OpeningSceneLength fromJson(dynamic raw) {
    return switch ('$raw'.trim().toLowerCase()) {
      'short' => OpeningSceneLength.short,
      'long' => OpeningSceneLength.long,
      _ => OpeningSceneLength.medium,
    };
  }

  String toJson() => name;
}
