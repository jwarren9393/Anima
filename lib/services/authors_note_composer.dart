import '../models/scene_mood_presets.dart';

/// Merges per-chat scene moods with the manual Author's Note field.
class AuthorsNoteComposer {
  const AuthorsNoteComposer();

  static String effectiveNote({
    required String manualAuthorsNote,
    required List<String> activeSceneMoodIds,
  }) {
    final parts = <String>[];
    for (final preset in SceneMoodPresets.resolve(activeSceneMoodIds)) {
      parts.add(preset.text.trim());
    }
    final manual = manualAuthorsNote.trim();
    if (manual.isNotEmpty) parts.add(manual);
    return parts.join('\n\n');
  }

  static bool hasEffectiveNote({
    required String manualAuthorsNote,
    required List<String> activeSceneMoodIds,
  }) {
    return manualAuthorsNote.trim().isNotEmpty ||
        activeSceneMoodIds.isNotEmpty;
  }
}
