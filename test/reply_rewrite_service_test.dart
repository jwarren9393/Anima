import 'package:flutter_test/flutter_test.dart';

import 'package:anima/models/chat_message.dart';
import 'package:anima/services/reply_rewrite_service.dart';

void main() {
  const service = ReplyRewriteService();

  test('buildRewriteMessages includes instruction and original draft', () {
    final messages = service.buildRewriteMessages(
      mode: ReplyRewriteMode.shorten,
      originalReply: '*She smiles.* "Hello there."',
      characterName: 'Lyra',
      contextMessages: [
        ChatMessage(id: 'u1', role: ChatRole.user, text: 'Hi!'),
      ],
    );

    expect(messages.length, 2);
    expect(messages.first['role'], 'system');
    expect(messages.last['role'], 'user');
    expect(messages.last['content'], contains('SHORTEN'));
    expect(messages.last['content'], contains('*She smiles.*'));
    expect(messages.last['content'], contains('Hi!'));
  });

  test('custom mode requires instruction text', () {
    expect(
      () => service.instructionFor(ReplyRewriteMode.custom),
      throwsArgumentError,
    );
    expect(
      service.instructionFor(
        ReplyRewriteMode.custom,
        customInstruction: 'Make her sound wary.',
      ),
      'Make her sound wary.',
    );
  });
}
