import 'package:flutter_test/flutter_test.dart';

import 'package:anima/models/explicit_scene_guidance.dart';
import 'package:anima/services/authors_note_composer.dart';

void main() {
  group('ExplicitSceneGuidance', () {
    test('intimacy mood ids trigger vocabulary rule check', () {
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
        ExplicitSceneGuidance.needsVocabularyRule(const ['sensual']),
        isTrue,
      );
      expect(
        ExplicitSceneGuidance.needsVocabularyRule(const ['no_porn_script']),
        isTrue,
      );
      expect(
        ExplicitSceneGuidance.needsVocabularyRule(const ['romantic', 'tense']),
        isFalse,
      );
    });

    test('vocabulary rule bans common LLM tropes and porn-script lines', () {
      const rule = ExplicitSceneGuidance.vocabularyRule;
      expect(rule, contains('his member'));
      expect(rule, contains('her core'));
      expect(rule, contains('still connected'));
      expect(rule, contains('cock'));
      expect(rule, contains('{{user}}'));
      expect(rule, contains('{{char}}'));
      expect(rule, contains('right there'));
      expect(rule, contains("don't you dare stop"));
      expect(rule, contains('PORN-SCRIPT DIALOGUE LAW'));
      expect(rule, contains('*grips the sheets*'));
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

    test('injects vocabulary law for sensual and anti-script moods', () {
      final sensual = AuthorsNoteComposer.effectiveNote(
        manualAuthorsNote: '',
        activeSceneMoodIds: const ['sensual'],
      );
      expect(sensual, contains('SCENE MOOD — SENSUAL'));
      expect(sensual, contains('EXPLICIT VOCABULARY LAW'));

      final antiScript = AuthorsNoteComposer.effectiveNote(
        manualAuthorsNote: '',
        activeSceneMoodIds: const ['no_porn_script'],
      );
      expect(antiScript, contains('REAL VOICE / ANTI-SCRIPT'));
      expect(antiScript, contains('EXPLICIT VOCABULARY LAW'));
    });
  });
}
