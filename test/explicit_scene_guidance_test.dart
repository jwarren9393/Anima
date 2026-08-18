import 'package:flutter_test/flutter_test.dart';

import 'package:anima/models/explicit_scene_guidance.dart';
import 'package:anima/services/authors_note_composer.dart';

void main() {
  group('ExplicitSceneGuidance', () {
    test('explicit mood ids trigger vocabulary rule check', () {
      expect(
        ExplicitSceneGuidance.needsVocabularyRule(const ['explicit']),
        isTrue,
      );
      expect(
        ExplicitSceneGuidance.needsVocabularyRule(
          const ['intimate_buildup', 'drunk'],
        ),
        isTrue,
      );
      expect(
        ExplicitSceneGuidance.needsVocabularyRule(const ['romantic', 'tense']),
        isFalse,
      );
      expect(
        ExplicitSceneGuidance.needsVocabularyRule(const ['sensual']),
        isFalse,
      );
    });

    test('vocabulary rule bans common LLM tropes', () {
      const rule = ExplicitSceneGuidance.vocabularyRule;
      expect(rule, contains('his member'));
      expect(rule, contains('her core'));
      expect(rule, contains('still connected'));
      expect(rule, contains('cock'));
      expect(rule, contains('{{user}}'));
      expect(rule, contains('{{char}}'));
    });
  });

  group('AuthorsNoteComposer explicit moods', () {
    test('injects vocabulary law once when explicit mood is active', () {
      final note = AuthorsNoteComposer.effectiveNote(
        manualAuthorsNote: '',
        activeSceneMoodIds: const ['explicit'],
      );

      expect(note, contains('SCENE MOOD — EXPLICIT'));
      expect(note, contains('EXPLICIT VOCABULARY LAW'));
      expect(note.split('EXPLICIT VOCABULARY LAW').length, 2);
    });

    test('does not inject vocabulary law for sensual-only mood', () {
      final note = AuthorsNoteComposer.effectiveNote(
        manualAuthorsNote: '',
        activeSceneMoodIds: const ['sensual'],
      );

      expect(note, contains('SCENE MOOD — SENSUAL'));
      expect(note, isNot(contains('EXPLICIT VOCABULARY LAW')));
    });
  });
}
