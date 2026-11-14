import 'package:anima/models/chat_message.dart';
import 'package:anima/models/field_wand_options.dart';
import 'package:anima/services/field_wand_context_builder.dart';
import 'package:anima/services/world_workshop_builder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final builder = FieldWandContextBuilder(WorldWorkshopBuilder());

  test('chatSource includes recent transcript', () {
    final source = builder.chatSource(
      messages: [
        ChatMessage(id: 'u1', role: ChatRole.user, text: 'Hello there'),
        ChatMessage(
          id: 'a1',
          role: ChatRole.assistant,
          text: 'Hi back',
          speakerName: 'Mira',
        ),
      ],
      chatTitle: 'Test thread',
    );
    expect(source, isNotNull);
    expect(source!.id, 'chat');
    expect(source.label, 'Test thread');
    expect(source.contextBlock, contains('Hello there'));
    expect(source.contextBlock, contains('Hi back'));
  });

  test('workshopSource bundles summary and transcript', () {
    final source = builder.workshopSource(
      conversation: [
        ChatMessage(
          id: 'u1',
          role: ChatRole.user,
          text: 'World detail about the castle',
        ),
      ],
      worldSummary: 'A haunted castle setting',
    );
    expect(source, isNotNull);
    expect(source!.id, 'workshop');
    expect(source.contextBlock, contains('haunted castle'));
    expect(source.contextBlock, contains('castle'));
  });

  test('WorkshopCardMergeDepth enrich adds merge rules', () {
    expect(
      WorkshopCardMergeDepth.enrich.mergeRules,
      contains('ENRICH MODE'),
    );
    expect(WorkshopCardMergeDepth.standard.mergeRules, isEmpty);
  });
}
