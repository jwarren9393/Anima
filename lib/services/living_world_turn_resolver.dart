import '../models/living_world.dart';
import '../models/living_world_update_policy.dart';
import '../models/turn_resolution.dart';
import 'living_world_update_service.dart';

/// Phase 6 spine: decide which validated deltas to persist before narrate.
///
/// Does not call NanoGPT — chat owns the propose API call. This service only
/// partitions + applies so tests can prove persist-before-narrate ordering.
class LivingWorldTurnResolver {
  const LivingWorldTurnResolver({
    this.updates = const LivingWorldUpdateService(),
  });

  final LivingWorldUpdateService updates;

  /// Ops that may be written immediately during resolve-before-narrate.
  ///
  /// Manual policy → nothing (Living mode alone never silent-writes).
  /// Otherwise → safe ops only; relationships stay deferred for review.
  List<LivingWorldCanonUpdate> selectForImmediateApply(
    List<LivingWorldCanonUpdate> proposed, {
    required LivingWorldUpdatePolicy policy,
  }) {
    if (policy == LivingWorldUpdatePolicy.manual) return const [];
    return updates.partitionForAutoSafe(proposed).safe;
  }

  /// Relationships (and anything else not auto-safe) held for after-turn review.
  List<LivingWorldCanonUpdate> selectDeferred(
    List<LivingWorldCanonUpdate> proposed, {
    required LivingWorldUpdatePolicy policy,
  }) {
    if (policy == LivingWorldUpdatePolicy.manual) return const [];
    return updates.partitionForAutoSafe(proposed).risky;
  }

  /// Apply [toApply] onto [world] in memory (caller saves + undo).
  ({LivingWorld world, TurnResolution resolution}) resolveBeforeNarrate({
    required LivingWorld world,
    required List<LivingWorldCanonUpdate> proposed,
    required LivingWorldUpdatePolicy policy,
    String? chatId,
    DateTime? at,
  }) {
    final when = at ?? DateTime.now();
    final immediate = selectForImmediateApply(proposed, policy: policy);
    final deferred = selectDeferred(proposed, policy: policy);
    final next = immediate.isEmpty
        ? world
        : updates.applyUpdates(world, immediate);
    return (
      world: next,
      resolution: TurnResolution(
        worldId: world.id,
        at: when,
        kind: TurnResolutionKind.resolveBeforeNarrate,
        proposed: proposed,
        applied: immediate,
        deferred: deferred,
        chatId: chatId,
      ),
    );
  }
}
