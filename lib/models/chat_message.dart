import 'group_beat_part.dart';
import '../services/group_beat_codec.dart';

/// How an AI-filled bubble was produced — kept so Regenerate / New swipe can
/// re-apply the same direction (My line… steer or Guide AI note).
enum MessageGenerationKind {
  /// AI wrote the player's next line (Impersonate / My line…).
  impersonate,

  /// Guide AI wrote this character reply from a player direction note.
  characterGuide,
}

/// One bubble in the chat: either from you or from the AI.
///
/// Assistant messages can store several “swipes” (alternate generations),
/// like SillyTavern. [text] is whatever swipe is currently showing.
///
/// [ChatRole.groupBeat] stores multiple character reactions in one timeline
/// card via [beatLines].
class ChatMessage {
  ChatMessage({
    required this.id,
    required this.role,
    required this.text,
    List<String>? swipes,
    this.swipeIndex = 0,
    this.speakerId,
    this.speakerName,
    this.generationKind,
    this.generationGuide,
    List<GroupBeatPart>? beatLines,
    List<List<GroupBeatPart>>? beatSwipes,
  }) : beatLines = beatLines == null
            ? null
            : List<GroupBeatPart>.unmodifiable(beatLines),
        beatSwipes = beatSwipes == null
            ? null
            : List<List<GroupBeatPart>>.unmodifiable(
                beatSwipes
                    .map((v) => List<GroupBeatPart>.unmodifiable(v))
                    .toList(),
              ),
        swipes = List<String>.unmodifiable(
          _normalizeSwipes(
            role: role,
            text: text,
            swipes: swipes,
            swipeIndex: swipeIndex,
            beatLines: beatLines,
            beatSwipes: beatSwipes,
          ),
        ) {
    assert(
      role != ChatRole.groupBeat ||
          (this.beatLines != null && this.beatLines!.isNotEmpty),
      'groupBeat messages require beatLines',
    );
  }

  /// Stable id for edit/delete/swipe on this device.
  final String id;

  final ChatRole role;

  /// Flattened display text (for group beats: all lines joined).
  final String text;

  /// Alternate AI generations (JSON-encoded beats for [ChatRole.groupBeat]).
  final List<String> swipes;

  final int swipeIndex;

  /// Group chats: which character said this (solo assistant bubbles).
  final String? speakerId;
  final String? speakerName;

  /// Why the AI filled this bubble (Impersonate / Guide AI), if applicable.
  final MessageGenerationKind? generationKind;

  /// Player steer / Guide AI note used to produce this bubble (may be empty for
  /// plain Impersonate). Survives so regen and new swipes reuse the same note.
  final String? generationGuide;

  /// Lines in the visible group-beat swipe.
  final List<GroupBeatPart>? beatLines;

  /// Alternate full group beats (swipe variants).
  final List<List<GroupBeatPart>>? beatSwipes;

  bool get isUser => role == ChatRole.user;

  bool get isNarrator => role == ChatRole.narrator;

  /// Player scene direction — commands the next AI reply (not in-character speech).
  bool get isDirector => role == ChatRole.director;

  bool get isGroupBeat => role == ChatRole.groupBeat;

  bool get isAssistant => role == ChatRole.assistant;

  /// AI wrote this bubble (character reply, Guide AI, or Impersonate / My line…).
  bool get isAiGenerated =>
      isAssistant ||
      isGroupBeat ||
      generationKind == MessageGenerationKind.impersonate;

  bool get hasGenerationGuide =>
      generationGuide != null && generationGuide!.trim().isNotEmpty;

  bool get canSwipe {
    if (isNarrator || isDirector) return false;
    if (isUser && generationKind != MessageGenerationKind.impersonate) {
      return false;
    }
    if (isGroupBeat) {
      return (beatSwipes?.length ?? swipes.length) > 1;
    }
    return swipes.length > 1;
  }

  /// Creates a coordinated multi-character beat message.
  factory ChatMessage.groupBeat({
    required String id,
    required List<GroupBeatPart> lines,
    List<List<GroupBeatPart>>? beatSwipes,
    int swipeIndex = 0,
  }) {
    final variants = beatSwipes ?? [lines];
    final idx = swipeIndex.clamp(0, variants.length - 1);
    final active = variants[idx];
    return ChatMessage(
      id: id,
      role: ChatRole.groupBeat,
      text: GroupBeatCodec.flatten(active),
      beatLines: active,
      beatSwipes: variants,
      swipeIndex: idx,
      swipes: GroupBeatCodec.encodeAllSwipes(variants),
    );
  }

  ChatMessage copyWith({
    String? id,
    ChatRole? role,
    String? text,
    List<String>? swipes,
    int? swipeIndex,
    String? speakerId,
    String? speakerName,
    bool clearSpeaker = false,
    MessageGenerationKind? generationKind,
    String? generationGuide,
    bool clearGeneration = false,
    List<GroupBeatPart>? beatLines,
    List<List<GroupBeatPart>>? beatSwipes,
    bool clearBeat = false,
  }) {
    final nextRole = role ?? this.role;
    final nextBeatLines = clearBeat ? null : (beatLines ?? this.beatLines);
    final nextBeatSwipes = clearBeat ? null : (beatSwipes ?? this.beatSwipes);
    final nextText = text ??
        (nextBeatLines != null
            ? GroupBeatCodec.flatten(nextBeatLines)
            : this.text);
    final nextSwipes = swipes ??
        (nextBeatSwipes != null
            ? GroupBeatCodec.encodeAllSwipes(nextBeatSwipes)
            : this.swipes);
    final nextIndex = swipeIndex ?? this.swipeIndex;
    return ChatMessage(
      id: id ?? this.id,
      role: nextRole,
      text: nextText,
      swipes: nextSwipes,
      swipeIndex: nextIndex.clamp(0, (nextSwipes.length - 1).clamp(0, 9999)),
      speakerId: clearSpeaker ? null : (speakerId ?? this.speakerId),
      speakerName: clearSpeaker ? null : (speakerName ?? this.speakerName),
      generationKind:
          clearGeneration ? null : (generationKind ?? this.generationKind),
      generationGuide:
          clearGeneration ? null : (generationGuide ?? this.generationGuide),
      beatLines: nextBeatLines,
      beatSwipes: nextBeatSwipes,
    );
  }

  ChatMessage withEditedText(String newText) {
    final trimmed = newText.trim();
    if (isUser || isNarrator || isDirector || isGroupBeat) {
      if (isGroupBeat) return this;
      return copyWith(text: trimmed, swipes: [trimmed], swipeIndex: 0);
    }
    final updated = List<String>.from(swipes);
    final index = swipeIndex.clamp(0, updated.length - 1);
    updated[index] = trimmed;
    return copyWith(text: trimmed, swipes: updated, swipeIndex: index);
  }

  ChatMessage withEditedBeatLines(List<GroupBeatPart> lines) {
    if (!isGroupBeat || beatSwipes == null) return this;
    final variants = List<List<GroupBeatPart>>.from(beatSwipes!);
    final idx = swipeIndex.clamp(0, variants.length - 1);
    variants[idx] = List<GroupBeatPart>.from(lines);
    return ChatMessage.groupBeat(
      id: id,
      lines: lines,
      beatSwipes: variants,
      swipeIndex: idx,
    );
  }

  ChatMessage withNewSwipe(String newText) {
    if (isGroupBeat) return this;
    final trimmed = newText.trim();
    final updated = [...swipes, trimmed];
    return copyWith(
      text: trimmed,
      swipes: updated,
      swipeIndex: updated.length - 1,
    );
  }

  ChatMessage withNewGroupBeatSwipe(List<GroupBeatPart> lines) {
    if (!isGroupBeat) return this;
    final variants = beatSwipes != null
        ? [...beatSwipes!, lines]
        : [lines];
    return ChatMessage.groupBeat(
      id: id,
      lines: lines,
      beatSwipes: variants,
      swipeIndex: variants.length - 1,
    );
  }

  ChatMessage withSwipeIndex(int index) {
    if (isGroupBeat && beatSwipes != null && beatSwipes!.isNotEmpty) {
      final clamped = index.clamp(0, beatSwipes!.length - 1);
      return ChatMessage.groupBeat(
        id: id,
        lines: beatSwipes![clamped],
        beatSwipes: beatSwipes,
        swipeIndex: clamped,
      );
    }
    if (swipes.isEmpty) return this;
    final clamped = index.clamp(0, swipes.length - 1);
    return copyWith(text: swipes[clamped], swipeIndex: clamped);
  }

  ChatMessage prepareEmptySwipe({required bool asNewSwipe}) {
    if (!isGroupBeat) {
      if (asNewSwipe) {
        return copyWith(
          text: '',
          swipes: [...swipes, ''],
          swipeIndex: swipes.length,
        );
      }
      final nextSwipes = List<String>.from(swipes);
      if (nextSwipes.isEmpty) nextSwipes.add('');
      final idx = swipeIndex.clamp(0, nextSwipes.length - 1);
      nextSwipes[idx] = '';
      return copyWith(text: '', swipes: nextSwipes, swipeIndex: idx);
    }

    final lines = beatLines;
    final emptyLine = lines != null && lines.isNotEmpty
        ? [
            for (final line in lines)
              GroupBeatPart(
                speakerId: line.speakerId,
                speakerName: line.speakerName,
                text: '',
              ),
          ]
        : <GroupBeatPart>[];

    if (asNewSwipe) {
      final variants = [...beatSwipes ?? [emptyLine], emptyLine];
      return ChatMessage.groupBeat(
        id: id,
        lines: emptyLine,
        beatSwipes: variants,
        swipeIndex: variants.length - 1,
      );
    }

    final variants = List<List<GroupBeatPart>>.from(beatSwipes ?? [emptyLine]);
    final idx = swipeIndex.clamp(0, variants.length - 1);
    variants[idx] = emptyLine;
    return ChatMessage.groupBeat(
      id: id,
      lines: emptyLine,
      beatSwipes: variants,
      swipeIndex: idx,
    );
  }

  Map<String, String> toApiMap() => {
        'role': isUser ? 'user' : 'assistant',
        'content': text,
      };

  static String roleToJson(ChatRole role) => switch (role) {
        ChatRole.user => 'user',
        ChatRole.narrator => 'narrator',
        ChatRole.director => 'director',
        ChatRole.groupBeat => 'groupBeat',
        ChatRole.assistant => 'assistant',
      };

  static ChatRole roleFromJson(String? raw) {
    switch (raw) {
      case 'user':
        return ChatRole.user;
      case 'narrator':
        return ChatRole.narrator;
      case 'director':
        return ChatRole.director;
      case 'groupBeat':
        return ChatRole.groupBeat;
      default:
        return ChatRole.assistant;
    }
  }

  static String? generationKindToJson(MessageGenerationKind? kind) =>
      switch (kind) {
        MessageGenerationKind.impersonate => 'impersonate',
        MessageGenerationKind.characterGuide => 'characterGuide',
        null => null,
      };

  static MessageGenerationKind? generationKindFromJson(String? raw) {
    switch ((raw ?? '').trim()) {
      case 'impersonate':
        return MessageGenerationKind.impersonate;
      case 'characterGuide':
        return MessageGenerationKind.characterGuide;
      default:
        return null;
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'role': roleToJson(role),
        'text': text,
        'swipes': swipes,
        'swipeIndex': swipeIndex,
        if (speakerId != null && speakerId!.isNotEmpty) 'speakerId': speakerId,
        if (speakerName != null && speakerName!.isNotEmpty)
          'speakerName': speakerName,
        if (generationKind != null)
          'generationKind': generationKindToJson(generationKind),
        // Persist even when empty — plain Impersonate still needs the kind flag
        // and an empty guide means "no steer" on regen.
        if (generationKind != null) 'generationGuide': generationGuide ?? '',
        if (beatLines != null)
          'beatLines': beatLines!.map((l) => l.toJson()).toList(),
        if (beatSwipes != null)
          'beatSwipes': beatSwipes!
              .map((v) => v.map((l) => l.toJson()).toList())
              .toList(),
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final roleRaw = json['role'] as String? ?? 'assistant';
    final role = roleFromJson(roleRaw);
    final text = (json['text'] as String? ?? '').trim();
    final generationKind = generationKindFromJson(
      json['generationKind'] as String?,
    );
    final generationGuideRaw = json['generationGuide'];
    final generationGuide = generationKind == null
        ? null
        : (generationGuideRaw == null ? '' : '$generationGuideRaw');

    List<GroupBeatPart>? beatLines;
    List<List<GroupBeatPart>>? beatSwipes;

    final beatLinesRaw = json['beatLines'];
    if (beatLinesRaw is List) {
      beatLines = beatLinesRaw
          .map((e) => GroupBeatPart.fromJson(Map<String, dynamic>.from(e as Map)))
          .where((p) => p.text.trim().isNotEmpty)
          .toList(growable: false);
    }

    final beatSwipesRaw = json['beatSwipes'];
    if (beatSwipesRaw is List) {
      beatSwipes = beatSwipesRaw
          .map((variant) {
            if (variant is! List) return <GroupBeatPart>[];
            return variant
                .map(
                  (e) =>
                      GroupBeatPart.fromJson(Map<String, dynamic>.from(e as Map)),
                )
                .where((p) => p.text.trim().isNotEmpty)
                .toList(growable: false);
          })
          .where((v) => v.isNotEmpty)
          .toList(growable: false);
    }

    final swipesRaw = json['swipes'];
    final swipes = swipesRaw is List
        ? swipesRaw.map((e) => '$e').where((s) => s.trim().isNotEmpty).toList()
        : <String>[];

    if (role == ChatRole.groupBeat) {
      if (beatSwipes == null && swipes.isNotEmpty) {
        beatSwipes = GroupBeatCodec.decodeAllSwipes(swipes);
      }
      if (beatLines == null && beatSwipes != null) {
        final variants = beatSwipes;
        if (variants.isNotEmpty) {
          final idx = (json['swipeIndex'] as int? ?? 0)
              .clamp(0, variants.length - 1);
          beatLines = variants[idx];
        }
      }
      final resolvedBeatLines = beatLines;
      if (resolvedBeatLines != null && resolvedBeatLines.isNotEmpty) {
        return ChatMessage.groupBeat(
          id: json['id'] as String? ??
              'msg_${DateTime.now().millisecondsSinceEpoch}',
          lines: resolvedBeatLines,
          beatSwipes: beatSwipes,
          swipeIndex: json['swipeIndex'] as int? ?? 0,
        );
      }
    }

    return ChatMessage(
      id: json['id'] as String? ??
          'msg_${DateTime.now().millisecondsSinceEpoch}',
      role: role,
      text: text,
      swipes: swipes.isEmpty && text.isNotEmpty ? [text] : swipes,
      swipeIndex: json['swipeIndex'] as int? ?? 0,
      speakerId: (json['speakerId'] as String?)?.trim(),
      speakerName: (json['speakerName'] as String?)?.trim(),
      generationKind: generationKind,
      generationGuide: generationGuide,
      beatLines: beatLines,
      beatSwipes: beatSwipes,
    );
  }

  static String newId() => 'msg_${DateTime.now().microsecondsSinceEpoch}';

  static List<String> _normalizeSwipes({
    required ChatRole role,
    required String text,
    required List<String>? swipes,
    required int swipeIndex,
    required List<GroupBeatPart>? beatLines,
    required List<List<GroupBeatPart>>? beatSwipes,
  }) {
    if (role == ChatRole.groupBeat && beatSwipes != null) {
      return GroupBeatCodec.encodeAllSwipes(beatSwipes);
    }
    if (swipes == null || swipes.isEmpty) {
      return [text];
    }
    final cleaned = List<String>.from(swipes);
    final index = swipeIndex.clamp(0, cleaned.length - 1);
    if (index >= 0 && index < cleaned.length && role != ChatRole.groupBeat) {
      cleaned[index] = text;
    }
    return cleaned;
  }
}

enum ChatRole { user, assistant, narrator, director, groupBeat }
