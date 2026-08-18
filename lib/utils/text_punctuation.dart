/// Light punctuation helpers for user-typed chat text.
library;

/// Converts `--` to an em dash (—). Each pair becomes one em dash.
String normalizeEmDashes(String text) {
  if (!text.contains('--')) return text;
  return text.replaceAll('--', '\u2014');
}
