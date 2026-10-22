import 'package:flutter_test/flutter_test.dart';

import 'package:anima/models/chat_session.dart';
import 'package:anima/models/living_world_tick_settings.dart';
import 'package:anima/models/living_world_update_policy.dart';

/// Phase 12 merge-readiness: Living World must stay opt-in.
///
/// Unbound chats + factory defaults = classic Anima. A fresh install must not
/// auto-write notebooks or inject packs until the owner binds a world.
void main() {
  group('Phase 12 defaults (classic Anima until bind)', () {
    test('new ChatSession has no worldId (Living World off)', () {
      final session = ChatSession(
        id: 'c1',
        characterId: 'char1',
        title: 'Solo',
        updatedAt: DateTime.utc(2026, 10, 21),
      );
      expect(session.worldId, isNull);
      expect(session.hasLivingWorld, isFalse);
    });

    test('legacy JSON without worldId stays unbound', () {
      final session = ChatSession.fromJson({
        'id': 'c2',
        'characterId': 'char1',
        'title': 'Old chat',
        'updatedAt': '2026-01-01T00:00:00.000Z',
        'messages': [],
      });
      expect(session.worldId, isNull);
      expect(session.hasLivingWorld, isFalse);
    });

    test('empty / whitespace worldId does not count as bound', () {
      expect(
        ChatSession.fromJson({
          'id': 'c3',
          'characterId': 'char1',
          'title': 'Blank',
          'updatedAt': '2026-01-01T00:00:00.000Z',
          'messages': [],
          'worldId': '   ',
        }).hasLivingWorld,
        isFalse,
      );
    });

    test('update policy defaults to manual (no after-turn writes)', () {
      expect(
        LivingWorldUpdatePolicyX.fromStorage(null),
        LivingWorldUpdatePolicy.manual,
      );
      expect(
        LivingWorldUpdatePolicyX.fromStorage(''),
        LivingWorldUpdatePolicy.manual,
      );
      expect(
        LivingWorldUpdatePolicyX.fromStorage('garbage'),
        LivingWorldUpdatePolicy.manual,
      );
    });

    test('near-scene ticks default to off', () {
      expect(
        LivingWorldTickTriggerX.fromStorage(null),
        LivingWorldTickTrigger.off,
      );
      expect(
        LivingWorldTickTriggerX.fromStorage(''),
        LivingWorldTickTrigger.off,
      );
      expect(LivingWorldTickSettings.defaults.trigger, LivingWorldTickTrigger.off);
      expect(
        LivingWorldTickSettings.defaults.shouldAutoTick(assistantReplyCount: 99),
        isFalse,
      );
    });

    test('resolve-before-narrate storage is off unless explicitly true', () {
      // Mirrors SettingsService.getLivingWorldResolveBeforeNarrate.
      bool parse(String? raw) => raw == '1' || raw == 'true';
      expect(parse(null), isFalse);
      expect(parse('0'), isFalse);
      expect(parse('false'), isFalse);
      expect(parse('1'), isTrue);
      expect(parse('true'), isTrue);
    });
  });
}
