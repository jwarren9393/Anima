import '../services/living_world_update_service.dart';

/// How a Living World turn resolution was produced (Phase 6+).
enum TurnResolutionKind {
  /// Facts decided and persisted before the roleplay reply streamed.
  resolveBeforeNarrate,

  /// Post-hoc extract after the reply (Phase 5 path).
  afterTurn,

  /// Explicit ⋮ → Update world from chat….
  manual,

  /// Narrator scene → who/where sync (Phase 7 presence).
  presenceSync,

  /// Near-scene tick (Phase 8) — active place + connected radius only.
  nearSceneTick,
}

/// Structured result of one Living World resolve / apply pass.
///
/// The engine accepts the same typed ops as [LivingWorldCanonUpdate]; this
/// wrapper records *what* was proposed vs applied and *when* (before narrate
/// vs after).
class TurnResolution {
  const TurnResolution({
    required this.worldId,
    required this.at,
    required this.kind,
    this.proposed = const [],
    this.applied = const [],
    this.deferred = const [],
    this.error,
    this.chatId,
  });

  final String worldId;
  final DateTime at;
  final TurnResolutionKind kind;

  /// Validated proposals from the model (may be empty).
  final List<LivingWorldCanonUpdate> proposed;

  /// Ops that were persisted this pass.
  final List<LivingWorldCanonUpdate> applied;

  /// Ops held for later review (e.g. relationships during resolve-before).
  final List<LivingWorldCanonUpdate> deferred;

  final String? error;
  final String? chatId;

  bool get didPersist => applied.isNotEmpty;
  bool get hasError => (error ?? '').trim().isNotEmpty;
  bool get isEmpty =>
      proposed.isEmpty && applied.isEmpty && deferred.isEmpty && !hasError;

  /// Prompt block so the narrator sees engine-applied facts this turn.
  String? get asOfTurnBlock {
    if (applied.isEmpty) return null;
    return formatAsOfTurnBlock(applied);
  }

  static String formatAsOfTurnBlock(List<LivingWorldCanonUpdate> applied) {
    if (applied.isEmpty) return '';
    final lines = [
      for (final u in applied) '- ${u.reviewLabel}: ${u.summary}',
    ];
    return '## Living World — as of this turn (engine applied)\n'
        '${lines.join('\n')}\n'
        'Treat these as already true when you reply.';
  }

  /// One-line summaries for the World log UI.
  List<String> get logLines {
    if (hasError && applied.isEmpty) {
      return ['Error: ${error!.trim()}'];
    }
    if (applied.isEmpty && deferred.isEmpty) {
      return proposed.isEmpty
          ? const ['No canon changes']
          : const ['Proposed only — nothing applied'];
    }
    return [
      for (final u in applied) 'Applied ${u.reviewLabel}: ${u.summary}',
      for (final u in deferred) 'Deferred ${u.reviewLabel}: ${u.summary}',
      if (hasError) 'Note: ${error!.trim()}',
    ];
  }

  String get kindLabel => switch (kind) {
        TurnResolutionKind.resolveBeforeNarrate => 'Resolve before reply',
        TurnResolutionKind.afterTurn => 'After turn',
        TurnResolutionKind.manual => 'Manual update',
        TurnResolutionKind.presenceSync => 'Presence sync',
        TurnResolutionKind.nearSceneTick => 'Near-scene tick',
      };

  Map<String, dynamic> toJson() => {
        'worldId': worldId,
        'at': at.toIso8601String(),
        'kind': kind.name,
        if (chatId != null && chatId!.isNotEmpty) 'chatId': chatId,
        if (error != null && error!.trim().isNotEmpty) 'error': error!.trim(),
        'applied': [
          for (final u in applied) {'op': u.op.name, 'summary': u.summary},
        ],
        'deferred': [
          for (final u in deferred) {'op': u.op.name, 'summary': u.summary},
        ],
        'proposedCount': proposed.length,
        'lines': logLines,
      };

  factory TurnResolution.fromJson(Map<String, dynamic> json) {
    final kindRaw = '${json['kind'] ?? ''}'.trim();
    final kind = TurnResolutionKind.values.firstWhere(
      (k) => k.name == kindRaw,
      orElse: () => TurnResolutionKind.afterTurn,
    );
    final atRaw = '${json['at'] ?? ''}'.trim();
    final at = DateTime.tryParse(atRaw) ?? DateTime.fromMillisecondsSinceEpoch(0);

    List<LivingWorldCanonUpdate> readSummaries(String key) {
      final list = json[key];
      if (list is! List) return const [];
      final out = <LivingWorldCanonUpdate>[];
      for (final item in list) {
        if (item is! Map) continue;
        final opName = '${item['op'] ?? ''}'.trim();
        final summary = '${item['summary'] ?? ''}'.trim();
        if (summary.isEmpty) continue;
        final op = LivingWorldUpdateOp.values.firstWhere(
          (o) => o.name == opName,
          orElse: () => LivingWorldUpdateOp.addEvent,
        );
        out.add(LivingWorldCanonUpdate(op: op, summary: summary));
      }
      return out;
    }

    // Prefer structured applied/deferred; fall back to lines-only logs.
    var applied = readSummaries('applied');
    var deferred = readSummaries('deferred');
    if (applied.isEmpty && deferred.isEmpty) {
      final lines = json['lines'];
      if (lines is List) {
        for (final line in lines) {
          final text = '$line'.trim();
          if (text.isEmpty) continue;
          applied = [
            ...applied,
            LivingWorldCanonUpdate(
              op: LivingWorldUpdateOp.addEvent,
              summary: text,
            ),
          ];
        }
      }
    }

    return TurnResolution(
      worldId: '${json['worldId'] ?? ''}'.trim(),
      at: at,
      kind: kind,
      applied: applied,
      deferred: deferred,
      error: '${json['error'] ?? ''}'.trim().isEmpty
          ? null
          : '${json['error']}'.trim(),
      chatId: '${json['chatId'] ?? ''}'.trim().isEmpty
          ? null
          : '${json['chatId']}'.trim(),
    );
  }
}
