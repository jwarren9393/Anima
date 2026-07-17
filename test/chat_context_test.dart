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
  });
}
