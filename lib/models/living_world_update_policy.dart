/// How Living World canon is written during play (Phase 5).
enum LivingWorldUpdatePolicy {
  /// Only ⋮ → Update world from chat… (Phases 1–4 default behaviour).
  manual,

  /// After each successful reply, propose updates and show the review sheet.
  proposeAfterTurn,

  /// After each reply, auto-apply safe ops; show review only for risky ones.
  autoSafe,
}

extension LivingWorldUpdatePolicyX on LivingWorldUpdatePolicy {
  String get storageValue => switch (this) {
        LivingWorldUpdatePolicy.manual => 'manual',
        LivingWorldUpdatePolicy.proposeAfterTurn => 'propose',
        LivingWorldUpdatePolicy.autoSafe => 'autoSafe',
      };

  String get menuLabel => switch (this) {
        LivingWorldUpdatePolicy.manual => 'Manual only',
        LivingWorldUpdatePolicy.proposeAfterTurn => 'Propose after each turn',
        LivingWorldUpdatePolicy.autoSafe => 'Auto-apply safe updates',
      };

  String get shortLabel => switch (this) {
        LivingWorldUpdatePolicy.manual => 'Manual',
        LivingWorldUpdatePolicy.proposeAfterTurn => 'Propose',
        LivingWorldUpdatePolicy.autoSafe => 'Auto-safe',
      };

  String get helpText => switch (this) {
        LivingWorldUpdatePolicy.manual =>
          'World notebook stays put during chat unless you open '
              'Update world from chat… or edit it in Settings → Living Worlds.',
        LivingWorldUpdatePolicy.proposeAfterTurn =>
          'After each AI reply, Anima suggests canon updates and you approve '
              'them on a review sheet.',
        LivingWorldUpdatePolicy.autoSafe =>
          'After each AI reply, safe facts (events, flags, who/where, active '
              'place) save automatically. Relationship changes still need your OK. '
              'You can undo the last pack from the chat menu.',
      };

  static LivingWorldUpdatePolicy fromStorage(String? raw) {
    switch ((raw ?? '').trim()) {
      case 'propose':
        return LivingWorldUpdatePolicy.proposeAfterTurn;
      case 'autoSafe':
        return LivingWorldUpdatePolicy.autoSafe;
      case 'manual':
      default:
        return LivingWorldUpdatePolicy.manual;
    }
  }
}
