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
          'Quietest mode. The notebook only changes when you tap '
              'Update world from chat… or edit it in Settings → Living Worlds. '
              'Best while you are still learning the feature.',
        LivingWorldUpdatePolicy.proposeAfterTurn =>
          'After each AI reply, Anima opens a review sheet of suggested facts. '
              'Nothing is saved until you approve. Good when you want to check '
              'every change.',
        LivingWorldUpdatePolicy.autoSafe =>
          'Play quietly: events, flags, who/where, active place, and continuity '
              'loops save on their own. Relationship changes wait on a '
              '“Review pending…” chip (no popup every turn). Undo the last pack '
              'anytime from the chat menu or Worlds hub.',
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
