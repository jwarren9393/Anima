/// How much new text the field wand should add.
enum FieldWandExpansion {
  light,
  medium,
  deep,
}

extension FieldWandExpansionLabels on FieldWandExpansion {
  String get menuTitle => switch (this) {
        FieldWandExpansion.light => 'Quick expand',
        FieldWandExpansion.medium => 'More detail',
        FieldWandExpansion.deep => 'Deep fill',
      };

  String get menuSubtitle => switch (this) {
        FieldWandExpansion.light =>
          'Add a few sentences from what is already on the card.',
        FieldWandExpansion.medium =>
          'Add a solid paragraph of new relevant detail.',
        FieldWandExpansion.deep =>
          'Fill in everything implied — relationships, beats, texture.',
      };

  String get promptInstruction => switch (this) {
        FieldWandExpansion.light =>
          'Add only a SHORT addition (roughly 1–3 sentences). Do not repeat '
          'what is already in the field or other card fields.',
        FieldWandExpansion.medium =>
          'Add a FULL PARAGRAPH of new relevant detail. Do not repeat existing '
          'wording unless needed for continuity.',
        FieldWandExpansion.deep =>
          'Add SUBSTANTIAL new detail — sensory specifics, relationships, '
          'history beats, speech quirks, and scene texture that were left out '
          'for brevity. Several short paragraphs are fine. Do not pad with '
          'generic filler.',
      };
}

/// External transcript / workshop material for the field wand.
class FieldWandExternalSource {
  const FieldWandExternalSource({
    required this.id,
    required this.label,
    required this.contextBlock,
  });

  final String id;
  final String label;
  final String contextBlock;

  bool get isEmpty => contextBlock.trim().isEmpty;
}

/// User choice from the field wand menu.
class FieldWandChoice {
  const FieldWandChoice({
    required this.expansion,
    this.externalSourceId,
  });

  final FieldWandExpansion expansion;

  /// When set, pull from [FieldWandExternalSource] with this id instead of
  /// card-only context.
  final String? externalSourceId;

  bool get usesExternal => externalSourceId != null;
}

/// Depth for whole-card workshop merge (Create / Update cast).
enum WorkshopCardMergeDepth {
  standard,
  enrich,
}

extension WorkshopCardMergeDepthLabels on WorkshopCardMergeDepth {
  String get title => switch (this) {
        WorkshopCardMergeDepth.standard => 'Standard update',
        WorkshopCardMergeDepth.enrich => 'Add more workshop details',
      };

  String get subtitle => switch (this) {
        WorkshopCardMergeDepth.standard =>
          'Merge workshop changes into the card — preserve what already fits.',
        WorkshopCardMergeDepth.enrich =>
          'Keep the card but actively add relevant workshop details that were '
          'left out for token savings.',
      };

  String get mergeRules => switch (this) {
        WorkshopCardMergeDepth.standard => '',
        WorkshopCardMergeDepth.enrich =>
          '\nENRICH MODE (important):\n'
          '- The card may already look complete — still ADD relevant workshop '
          'details that are missing (relationships, sensory beats, backstory '
          'fragments, speech quirks, goals, secrets, etc.).\n'
          '- Do not shorten fields unless the workshop explicitly revises them '
          'shorter.\n'
          '- Prefer concrete workshop facts over generic padding.\n',
      };
}
