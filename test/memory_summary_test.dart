import 'package:flutter_test/flutter_test.dart';

import 'package:anima/models/chat_message.dart';
import 'package:anima/models/memory_summary.dart';
import 'package:anima/services/chat_context_service.dart';

void main() {
  group('MemorySummaryDocument', () {
    test('parses unlabeled Location/Present into Scene', () {
      const raw = '''
- Location: The tower
- Present: Jay, Edric
- Thread: Find the hidden key
- Promise: Edric will wait at dawn
''';
      final doc = MemorySummaryDocument.parse(raw);
      expect(doc.scene.map((f) => f.kind), containsAll(['location', 'present']));
      expect(doc.ledger.map((f) => f.kind), containsAll(['thread', 'promise']));
    });

    test('round-trips sections and pins', () {
      const raw = '''
## Scene
- Location: Harbor
- Present: Jay, Mira

## Ledger
- [pin] Promise: Mira keeps the letter
- Thread: Return to the vault
''';
      final encoded = MemorySummaryDocument.parse(raw).encode();
      final again = MemorySummaryDocument.parse(encoded);
      expect(again.scene, hasLength(2));
      expect(again.ledger, hasLength(2));
      expect(again.ledger.first.pinned, isTrue);
      expect(again.ledger.first.text, contains('letter'));
      expect(encoded, contains('- [pin] Promise:'));
      expect(encoded, contains('## Scene'));
      expect(encoded, contains('## Ledger'));
    });

    test('restores pins the model dropped', () {
      const existing = '''
## Scene
- Location: Inn

## Ledger
- [pin] Thread: Go back for Mira
- Event (witnesses: Jay): They paid the innkeep
''';
      const generated = '''
## Scene
- Location: Road north

## Ledger
- Event (witnesses: Jay): They paid the innkeep
- Item: A spare lantern
''';
      final out = MemorySummaryDocument.finalize(
        existing: existing,
        generated: generated,
      );
      expect(out, contains('[pin] Thread: Go back for Mira'));
      expect(out, contains('spare lantern'));
      expect(out, contains('Road north'));
      expect(out, isNot(contains('Location: Inn')));
    });

    test('re-applies pin when model kept the fact but dropped the marker', () {
      const existing = '''
## Ledger
- [pin] Promise: Edric will wait
''';
      const generated = '''
## Ledger
- Promise: Edric will wait
''';
      final out = MemorySummaryDocument.finalize(
        existing: existing,
        generated: generated,
      );
      expect(out, contains('[pin] Promise: Edric will wait'));
    });

    test('empty model output keeps existing memory', () {
      const existing = '''
## Ledger
- Thread: Open plot
''';
      final out = MemorySummaryDocument.finalize(
        existing: existing,
        generated: '   ',
      );
      expect(out, contains('Open plot'));
    });

    test('ledger target grows with covered messages', () {
      expect(MemorySummaryDocument.ledgerBulletTarget(0), 35);
      expect(MemorySummaryDocument.ledgerBulletTarget(80), 45);
      expect(MemorySummaryDocument.ledgerBulletTarget(500), 90);
    });
  });

  group('ChatContextService summarize merge', () {
    const service = ChatContextService();

    test('prompt asks for Scene/Ledger merge and not newest-wins', () {
      final messages = service.buildSummarizeMessages(
        chunk: [
          ChatMessage(
            id: '1',
            role: ChatRole.user,
            text: 'We enter the throne room.',
          ),
        ],
        existingSummary: '''
## Ledger
- [pin] Thread: Rescue Mira
''',
        userName: 'Jay',
        charName: 'Edric',
        coveredMessageCount: 40,
      );
      final system = messages.first['content'] ?? '';
      final user = messages.last['content'] ?? '';
      expect(system, contains('## Scene'));
      expect(system, contains('## Ledger'));
      expect(system, contains('newest does NOT win'));
      expect(system, contains('NEVER drop a Thread'));
      expect(system, isNot(contains('Prefer the NEWEST')));
      expect(system, contains('FACT INDEX only'));
      expect(user, contains('PINNED FACTS'));
      expect(user, contains('[pin] Thread: Rescue Mira'));
      expect(user, contains('MERGE'));
    });
  });
}
