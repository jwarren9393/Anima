/// When near-scene Living World ticks run during play (Phase 8).
enum LivingWorldTickTrigger {
  /// Never auto-tick — only ⋮ / hub → Advance world a beat….
  off,

  /// After every successful AI reply in a bound chat.
  afterTurn,

  /// After every N successful AI replies in a bound chat (N from settings).
  everyN,
}

extension LivingWorldTickTriggerX on LivingWorldTickTrigger {
  String get storageValue => switch (this) {
        LivingWorldTickTrigger.off => 'off',
        LivingWorldTickTrigger.afterTurn => 'afterTurn',
        LivingWorldTickTrigger.everyN => 'everyN',
      };

  String get menuLabel => switch (this) {
        LivingWorldTickTrigger.off => 'Off (manual only)',
        LivingWorldTickTrigger.afterTurn => 'After each turn',
        LivingWorldTickTrigger.everyN => 'Every N turns',
      };

  String get helpText => switch (this) {
        LivingWorldTickTrigger.off =>
          'Near-scene ticks never run automatically. Use Advance world a beat… '
              'from the chat menu or Living Worlds hub when you want a small '
              'nearby shift.',
        LivingWorldTickTrigger.afterTurn =>
          'After each AI reply in a bound chat, Anima runs a tiny near-scene '
              'tick (active place + connected places only). Unbound chats never '
              'tick.',
        LivingWorldTickTrigger.everyN =>
          'Same as after each turn, but only every N replies (set N below). '
              'Keeps API/latency quieter on long sessions.',
      };

  static LivingWorldTickTrigger fromStorage(String? raw) {
    switch ((raw ?? '').trim()) {
      case 'afterTurn':
        return LivingWorldTickTrigger.afterTurn;
      case 'everyN':
        return LivingWorldTickTrigger.everyN;
      case 'off':
      default:
        return LivingWorldTickTrigger.off;
    }
  }
}

/// Caps and trigger for Phase 8 near-scene simulation.
class LivingWorldTickSettings {
  const LivingWorldTickSettings({
    this.trigger = LivingWorldTickTrigger.off,
    this.everyN = 3,
    this.maxPeople = 6,
    this.maxOps = 8,
    this.radiusHops = 1,
    this.lastEventCount = 8,
  });

  final LivingWorldTickTrigger trigger;

  /// Used when [trigger] is [LivingWorldTickTrigger.everyN]. Clamped 2–20.
  final int everyN;

  /// Max people a tick may touch. Clamped 1–12.
  final int maxPeople;

  /// Max validated ops a tick may emit. Clamped 1–12.
  final int maxOps;

  /// Place-graph hops from the active place. Clamped 0–2.
  final int radiusHops;

  /// Recent events considered when picking near-scene people. Clamped 2–20.
  final int lastEventCount;

  static const defaults = LivingWorldTickSettings();

  LivingWorldTickSettings copyWith({
    LivingWorldTickTrigger? trigger,
    int? everyN,
    int? maxPeople,
    int? maxOps,
    int? radiusHops,
    int? lastEventCount,
  }) {
    return LivingWorldTickSettings(
      trigger: trigger ?? this.trigger,
      everyN: everyN ?? this.everyN,
      maxPeople: maxPeople ?? this.maxPeople,
      maxOps: maxOps ?? this.maxOps,
      radiusHops: radiusHops ?? this.radiusHops,
      lastEventCount: lastEventCount ?? this.lastEventCount,
    ).clamped();
  }

  LivingWorldTickSettings clamped() {
    return LivingWorldTickSettings(
      trigger: trigger,
      everyN: everyN.clamp(2, 20),
      maxPeople: maxPeople.clamp(1, 12),
      maxOps: maxOps.clamp(1, 12),
      radiusHops: radiusHops.clamp(0, 2),
      lastEventCount: lastEventCount.clamp(2, 20),
    );
  }

  /// Whether an automatic tick should run after this reply.
  ///
  /// [assistantReplyCount] = number of assistant bubbles in the chat after
  /// the reply just finished (including it).
  bool shouldAutoTick({required int assistantReplyCount}) {
    if (assistantReplyCount <= 0) return false;
    switch (trigger) {
      case LivingWorldTickTrigger.off:
        return false;
      case LivingWorldTickTrigger.afterTurn:
        return true;
      case LivingWorldTickTrigger.everyN:
        final n = everyN.clamp(2, 20);
        return assistantReplyCount % n == 0;
    }
  }
}
