import 'package:flutter_test/flutter_test.dart';

import 'package:anima/models/anima_presets.dart';

void main() {
  group('AnimaPresets', () {
    test('sampling presets cover core packs', () {
      expect(AnimaPresets.sampling, isNotEmpty);
      final ids = AnimaPresets.sampling.map((p) => p.id).toSet();
      expect(ids, containsAll(['balanced', 'creative', 'focused', 'short']));
      for (final preset in AnimaPresets.sampling) {
        expect(preset.name, isNotEmpty);
        expect(preset.description, isNotEmpty);
        expect(preset.settings.temperature, inInclusiveRange(0, 2));
        expect(preset.settings.topP, inInclusiveRange(0, 1));
      }
    });

    test('text presets have names and descriptions', () {
      for (final list in [
        AnimaPresets.authorsNotes,
        AnimaPresets.systemPrompts,
        AnimaPresets.postHistory,
        AnimaPresets.collaboratorGuidance,
      ]) {
        expect(list, isNotEmpty);
        for (final preset in list) {
          expect(preset.name, isNotEmpty);
          expect(preset.description, isNotEmpty);
        }
      }
    });

    test('context size presets exist', () {
      expect(AnimaPresets.contextSize.length, greaterThanOrEqualTo(6));
      expect(
        AnimaPresets.contextSize.map((p) => p.historyTokenBudget),
        containsAll([2048, 4096, 8192, 16384]),
      );
    });

    test('each preset menu has solid variety', () {
      expect(AnimaPresets.sampling.length, greaterThanOrEqualTo(10));
      expect(AnimaPresets.authorsNotes.length, greaterThanOrEqualTo(10));
      expect(AnimaPresets.systemPrompts.length, greaterThanOrEqualTo(8));
      expect(AnimaPresets.postHistory.length, greaterThanOrEqualTo(7));
      expect(AnimaPresets.collaboratorGuidance.length, greaterThanOrEqualTo(8));
    });

    test('field help strings are present', () {
      expect(AnimaPresets.temperatureHelp.length, greaterThan(40));
      expect(AnimaPresets.topPHelp.length, greaterThan(40));
      expect(AnimaPresets.maxTokensHelp.length, greaterThan(40));
      expect(AnimaPresets.contextMaxHistoryHelp.length, greaterThan(40));
    });
  });
}
