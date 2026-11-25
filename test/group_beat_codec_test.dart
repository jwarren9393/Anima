import 'package:anima/models/chat_message.dart';
import 'package:anima/models/group_beat_part.dart';
import 'package:anima/services/group_beat_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final sampleLines = [
    GroupBeatPart(
      speakerId: 'a',
      speakerName: 'Alice',
      text: '*waves* "Hi!"',
    ),
    GroupBeatPart(
      speakerId: 'b',
      speakerName: 'Bob',
      text: '*nods*',
    ),
  ];

  test('flatten joins speaker lines', () {
    expect(
      GroupBeatCodec.flatten(sampleLines),
      'Alice: *waves* "Hi!"\nBob: *nods*',
    );
  });

  test('formatForPrompt wraps group moment header', () {
    expect(
      GroupBeatCodec.formatForPrompt(sampleLines),
      'Group moment (simultaneous reactions):\n'
          'Alice: *waves* "Hi!"\nBob: *nods*',
    );
  });

  test('encode and decode swipe round-trip', () {
    final encoded = GroupBeatCodec.encodeSwipe(sampleLines);
    final decoded = GroupBeatCodec.decodeSwipe(encoded);
    expect(decoded.length, 2);
    expect(decoded[0].speakerName, 'Alice');
    expect(decoded[1].text, '*nods*');
  });

  test('ChatMessage.groupBeat JSON round-trip', () {
    final message = ChatMessage.groupBeat(
      id: 'gb1',
      lines: sampleLines,
    );
    final restored = ChatMessage.fromJson(message.toJson());
    expect(restored.isGroupBeat, isTrue);
    expect(restored.beatLines?.length, 2);
    expect(restored.text, message.text);
    expect(restored.swipes.length, 1);
  });

  test('group beat swipes preserve variants', () {
    final alt = [
      GroupBeatPart(speakerId: 'a', speakerName: 'Alice', text: 'Alt'),
      GroupBeatPart(speakerId: 'b', speakerName: 'Bob', text: 'Alt too'),
    ];
    final message = ChatMessage.groupBeat(
      id: 'gb2',
      lines: sampleLines,
      beatSwipes: [sampleLines, alt],
      swipeIndex: 1,
    );
    expect(message.swipeIndex, 1);
    expect(message.beatLines![0].text, 'Alt');
    final restored = ChatMessage.fromJson(message.toJson());
    expect(restored.swipeIndex, 1);
    expect(restored.beatLines![0].text, 'Alt');
  });
}
