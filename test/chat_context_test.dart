import 'package:flutter_test/flutter_test.dart';

import 'package:anima/models/chat_message.dart';
import 'package:anima/services/chat_context_service.dart';
import 'package:anima/services/settings_service.dart';

void main() {
  const service = ChatContextService();

  ChatMessage msg(String id, String text, {bool user = true}) {
    return ChatMessage(
      id: id,
      role: user ? ChatRole.user : ChatRole.assistant,
      text: text,
    );
  }

  group('ChatContextService', () {
    test('selectHistory packs by token budget newest-first', () {
      // Each "line XX" is short; force many messages and a tiny budget.
      final messages = [
        for (var i = 0; i < 20; i++)
          msg('m$i', 'Word$i ' * 20, user: i.isEven), // ~100+ chars each
      ];
      final selected = service.selectHistory(
        messages: messages,
        endExclusive: 20,
        memoryCoveredCount: 0,
        historyTokenBudget: 80,
      );
      expect(selected, isNotEmpty);
      expect(selected.last.text, messages.last.text);
      // Should not include the entire chat under a small budget.
      expect(selected.length, lessThan(20));
    });

    test('selectHistory skips covered messages', () {
      final messages = [
        for (var i = 0; i < 10; i++) msg('m$i', 'line $i padded text here'),
      ];
      final selected = service.selectHistory(
        messages: messages,
        endExclusive: 10,
        memoryCoveredCount: 7,
        historyTokenBudget: 4000,
      );
      expect(selected.first.text, contains('line 7'));
      expect(selected.length, 3);
    });

    test('shouldAutoSummarize respects threshold', () {
      const context = ContextSettings(
        autoSummarize: true,
        summarizeEveryMessages: 20,
      );
      expect(
        service.shouldAutoSummarize(
          messageCount: 25,
          memoryCoveredCount: 0,
          context: context,
        ),
        isTrue,
      );
      expect(
        service.shouldAutoSummarize(
          messageCount: 25,
          memoryCoveredCount: 10,
          context: context,
        ),
        isFalse,
      );
      expect(
        service.shouldAutoSummarize(
          messageCount: 40,
          memoryCoveredCount: 0,
          context: const ContextSettings(autoSummarize: false),
        ),
        isFalse,
      );
    });

    test('summarizeCutIndex leaves recent raw', () {
      expect(
        service.summarizeCutIndex(
          messageCount: 30,
          memoryCoveredCount: 0,
          summarizeKeepRecent: 10,
        ),
        20,
      );
      expect(
        service.summarizeCutIndex(
          messageCount: 12,
          memoryCoveredCount: 5,
          summarizeKeepRecent: 10,
        ),
        5,
      );
    });

    test('estimateTokens matches lore rule of thumb', () {
      expect(service.estimateTokens('abcd'), 1);
      expect(service.estimateTokens('abcdefgh'), 2);
    });

    test('estimateWorkshop and estimateChat produce usable gauges', () {
      final messages = [
        msg('1', 'Hello there, world builder.'),
        msg('2', 'A rainy harbor city with rival guilds.', user: false),
      ];
      final workshop = service.estimateWorkshop(
        messages: messages,
        linkedLorebookJson: '{"name":"Harbor","entries":[{"content":"docks"}]}',
        importedSourceText: 'IMPORTED CHAT SOURCE\nMemory summary: dock heist.',
        worldSummary: 'A rainy harbor with rival guilds.',
        worldSummaryCoveredCount: 0,
        historyTokenBudget: 4000,
        modelContextLength: 16000,
      );
      expect(workshop.messageCount, 2);
      expect(workshop.estimatedSentTokens, greaterThan(0));
      expect(workshop.loreTokens, greaterThan(0));
      expect(workshop.memoryTokens, greaterThan(0));
      expect(workshop.notes, contains('history budget'));
      expect(workshop.fillRatio, isNotNull);
      expect(workshop.compactBannerLine, contains('2 msgs'));
      expect(workshop.compactBannerLine, contains('16K'));

      final longWorkshop = service.estimateWorkshop(
        messages: [
          for (var i = 0; i < 20; i++)
            msg('w$i', 'Long workshop brainstorm line $i ' * 40),
        ],
        worldSummary: 'Established canon.',
        worldSummaryCoveredCount: 10,
        historyTokenBudget: 300,
        modelContextLength: 16000,
      );
      expect(longWorkshop.messagesTrimmedAway, greaterThan(0));
      expect(
        longWorkshop.estimatedSentTokens,
        lessThan(longWorkshop.fullTranscriptTokens),
      );

      final chat = service.estimateChat(
        messages: [
          for (var i = 0; i < 30; i++)
            msg('m$i', 'Pad this message with enough text $i ' * 10),
        ],
        memoryCoveredCount: 0,
        historyTokenBudget: 200,
        memorySummary: 'Earlier the party entered town.',
        modelContextLength: 8000,
      );
      expect(chat.messageCount, 30);
      expect(chat.messagesTrimmedAway, greaterThan(0));
      expect(chat.estimatedSentTokens, lessThan(chat.fullTranscriptTokens));
      expect(chat.memoryTokens, greaterThan(0));
    });

    test('ContextEstimate.formatTokenCount', () {
      expect(ContextEstimate.formatTokenCount(850), '850');
      expect(ContextEstimate.formatTokenCount(1200), '1.2K');
      expect(ContextEstimate.formatTokenCount(16000), '16K');
    });

    test('summarizeSampling uses generous defaults and caps at 2048', () {
      const unset = SamplingSettings(
        maxTokens: null,
        temperature: 0.9,
        topP: 1.0,
      );
      final fromUnset = ChatContextService.summarizeSampling(unset);
      expect(
        fromUnset.maxTokens,
        ChatContextService.summarizeDefaultMaxTokens,
      );

      const low = SamplingSettings(
        maxTokens: 512,
        temperature: 0.9,
        topP: 1.0,
      );
      final fromLow = ChatContextService.summarizeSampling(low);
      expect(fromLow.maxTokens, ChatContextService.summarizeDefaultMaxTokens);

      const high = SamplingSettings(
        maxTokens: 4096,
        temperature: 0.9,
        topP: 1.0,
      );
      final fromHigh = ChatContextService.summarizeSampling(high);
      expect(fromHigh.maxTokens, ChatContextService.summarizeMaxCap);
      expect(fromHigh.temperature, lessThanOrEqualTo(0.3));
    });

    test('buildSummarizeMessages uses clinical bullet system prompt', () {
      final messages = service.buildSummarizeMessages(
        chunk: [msg('1', 'We enter the throne room.')],
        existingSummary: '',
        userName: 'Jay',
        charName: 'Edric',
      );
      final system = messages.first['content'] ?? '';
      expect(system, contains('FACT INDEX only'));
      expect(system, contains('bullet list only'));
      expect(system, contains('NO metaphors'));
      expect(system, isNot(contains('emotional tone and character voice')));
    });

    test('formatMemoryForPrompt discourages style mimicry', () {
      final block = ChatContextService.formatMemoryForPrompt(
        '- Location: Tower\n- Event: They met.',
      );
      expect(block, contains('reference only'));
      expect(block, contains('Do NOT mimic'));
      expect(block, contains('Tower'));
    });
  });
}
