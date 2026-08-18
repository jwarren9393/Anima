import 'package:flutter_test/flutter_test.dart';

import 'package:anima/models/chat_session.dart';
import 'package:anima/services/authors_note_composer.dart';

void main() {
  test('merges active scene moods before manual note', () {
    final note = AuthorsNoteComposer.effectiveNote(
      manualAuthorsNote: 'Keep replies short.',
      activeSceneMoodIds: const ['drunk', 'tense'],
    );

    expect(note, contains('SCENE MOOD — DRUNK'));
    expect(note, contains('SCENE MOOD — TENSE'));
    expect(note, endsWith('Keep replies short.'));
  });

  test('hasEffectiveNote is true when only moods are active', () {
    expect(
      AuthorsNoteComposer.hasEffectiveNote(
        manualAuthorsNote: '',
        activeSceneMoodIds: const ['happy'],
      ),
      isTrue,
    );
    expect(
      AuthorsNoteComposer.hasEffectiveNote(
        manualAuthorsNote: '',
        activeSceneMoodIds: const [],
      ),
      isFalse,
    );
  });

  test('chat session persists activeSceneMoodIds', () {
    final session = ChatSession(
      id: 'c1',
      characterId: 'char1',
      title: 'Test',
      updatedAt: DateTime(2026, 1, 1),
      activeSceneMoodIds: const ['drunk', 'sensual'],
    );

    final json = session.toJson();
    expect(json['activeSceneMoodIds'], ['drunk', 'sensual']);

    final restored = ChatSession.fromJson(json);
    expect(restored.activeSceneMoodIds, ['drunk', 'sensual']);
  });
}
