import '../models/chat_message.dart';
import '../models/field_wand_options.dart';
import '../models/lorebook.dart';
import '../models/world_workshop.dart';
import 'world_workshop_builder.dart';

/// Builds external context blocks for per-field wand expansion.
class FieldWandContextBuilder {
  const FieldWandContextBuilder(this._builder);

  final WorldWorkshopBuilder _builder;

  static const _maxContextChars = 12000;

  FieldWandExternalSource? workshopSource({
    required List<ChatMessage> conversation,
    Lorebook? sourceLorebook,
    WorkshopSourceContext? importedSource,
    String worldSummary = '',
    List<String> canonPinMessageIds = const [],
  }) {
    final parts = <String>[];
    final summary = worldSummary.trim();
    if (summary.isNotEmpty) {
      parts.add('World summary:\n$summary');
    }
    final lore = _builder.formatLorebookContext(sourceLorebook);
    if (lore.isNotEmpty) {
      parts.add('Linked lorebook (reference only):\n$lore');
    }
    final imported = _builder.formatImportedSource(importedSource);
    if (imported.isNotEmpty) {
      parts.add(imported.trim());
    }
    final canon = _builder.formatCanonPins(conversation, canonPinMessageIds);
    if (canon.isNotEmpty) {
      parts.add(canon.trim());
    }
    final transcript = _trimContext(
      _builder.formatTranscript(_recentMessages(conversation, max: 40)),
    );
    if (transcript.isNotEmpty) {
      parts.add('Workshop conversation:\n$transcript');
    }
    if (parts.isEmpty) return null;
    return FieldWandExternalSource(
      id: 'workshop',
      label: 'Workshop',
      contextBlock: parts.join('\n\n'),
    );
  }

  FieldWandExternalSource? chatSource({
    required List<ChatMessage> messages,
    String chatTitle = 'This chat',
    int maxMessages = 32,
  }) {
    final transcript = _trimContext(
      _builder.formatTranscript(_recentMessages(messages, max: maxMessages)),
    );
    if (transcript.isEmpty) return null;
    return FieldWandExternalSource(
      id: 'chat',
      label: chatTitle.trim().isEmpty ? 'Chat' : chatTitle.trim(),
      contextBlock: 'Roleplay transcript:\n$transcript',
    );
  }

  List<ChatMessage> _recentMessages(List<ChatMessage> messages, {int max = 32}) {
    final withText =
        messages.where((m) => m.text.trim().isNotEmpty).toList(growable: false);
    if (withText.length <= max) return withText;
    return withText.sublist(withText.length - max);
  }

  String _trimContext(String input) {
    final text = input.trim();
    if (text.length <= _maxContextChars) return text;
    return '…(trimmed)\n${text.substring(text.length - _maxContextChars)}';
  }
}
