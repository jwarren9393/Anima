import 'package:flutter_test/flutter_test.dart';

import 'package:anima/models/chat_message.dart';
import 'package:anima/services/message_formatter.dart';
import 'package:anima/services/settings_service.dart';
import 'package:anima/widgets/rp_rich_text.dart';

void main() {
  group('parseRpSegments', () {
    test('splits actions and dialogue', () {
      final parts = parseRpSegments('*smiles* "Hello there." *waves*');
      expect(parts.length, 5);
      expect(parts[0].kind, RpSegmentKind.action);
      expect(parts[0].text, 'smiles');
      expect(parts[1].kind, RpSegmentKind.plain);
      expect(parts[1].text, ' ');
      expect(parts[2].kind, RpSegmentKind.dialogue);
      expect(parts[2].text, 'Hello there.');
      expect(parts[3].kind, RpSegmentKind.plain);
      expect(parts[4].kind, RpSegmentKind.action);
      expect(parts[4].text, 'waves');
    });

    test('handles curly quotes', () {
      final parts = parseRpSegments('“Hi” *nods*');
      expect(parts[0].kind, RpSegmentKind.dialogue);
      expect(parts[0].text, 'Hi');
      expect(parts[2].kind, RpSegmentKind.action);
      expect(parts[2].text, 'nods');
    });

    test('plain text stays plain', () {
      final parts = parseRpSegments('Just saying hello');
      expect(parts, hasLength(1));
      expect(parts.first.kind, RpSegmentKind.plain);
      expect(parts.first.text, 'Just saying hello');
    });
  });

  group('MessageFormatter', () {
    const formatter = MessageFormatter();

    test('buildMessages asks for light format only', () {
      final messages = formatter.buildMessages(
        draft: 'I wave and say hi',
        userName: 'Alex',
        characterName: 'Luna',
        recentMessages: [
          ChatMessage(
            id: '1',
            role: ChatRole.assistant,
            text: '*smiles* "Hey."',
          ),
        ],
        formatNote: 'Never reword.',
      );
      expect(messages, hasLength(2));
      expect(messages[0]['content'], contains('Never reword.'));
      expect(messages[0]['content'], contains('Do NOT reword'));
      expect(messages[0]['content'], contains('*asterisks*'));
      expect(messages[0]['content'], contains('double quotes'));
      expect(messages[1]['content'], contains('preserve wording'));
      expect(messages[1]['content'], contains('Alex'));
      expect(messages[1]['content'], contains('Luna'));
      expect(messages[1]['content'], contains('I wave and say hi'));
      expect(messages[1]['content'], contains('Hey.'));
    });

    test('empty format note falls back to default composer note', () {
      final messages = formatter.buildMessages(
        draft: 'hello',
        userName: 'U',
        characterName: 'C',
        formatNote: '   ',
      );
      expect(
        messages[0]['content'],
        contains(
          CollaboratorSettings.defaultComposerFormatNote.substring(0, 24),
        ),
      );
    });
  });
}
