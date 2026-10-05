import 'package:anima/models/chat_message.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('generation guide round-trips for My line / Impersonate', () {
    final message = ChatMessage(
      id: 'u1',
      role: ChatRole.user,
      text: '*I walk out.*',
      swipes: const ['*I walk out.*'],
      generationKind: MessageGenerationKind.impersonate,
      generationGuide: 'lose my temper and leave',
    );

    final restored = ChatMessage.fromJson(message.toJson());
    expect(restored.generationKind, MessageGenerationKind.impersonate);
    expect(restored.generationGuide, 'lose my temper and leave');
    expect(restored.hasGenerationGuide, isTrue);
    expect(restored.isAiGenerated, isTrue);
    expect(restored.canSwipe, isFalse);
  });

  test('plain Impersonate keeps empty guide for regen', () {
    final message = ChatMessage(
      id: 'u2',
      role: ChatRole.user,
      text: '"Hey."',
      swipes: const ['"Hey."', '"Hi."'],
      swipeIndex: 1,
      generationKind: MessageGenerationKind.impersonate,
      generationGuide: '',
    );

    final restored = ChatMessage.fromJson(message.toJson());
    expect(restored.generationKind, MessageGenerationKind.impersonate);
    expect(restored.generationGuide, '');
    expect(restored.hasGenerationGuide, isFalse);
    expect(restored.canSwipe, isTrue);
  });

  test('Guide AI note survives prepareEmptySwipe', () {
    final message = ChatMessage(
      id: 'a1',
      role: ChatRole.assistant,
      text: '*She nods.*',
      swipes: const ['*She nods.*'],
      speakerId: 'c1',
      speakerName: 'Mira',
      generationKind: MessageGenerationKind.characterGuide,
      generationGuide: 'she pushes back and leaves',
    );

    final next = message.prepareEmptySwipe(asNewSwipe: true);
    expect(next.generationKind, MessageGenerationKind.characterGuide);
    expect(next.generationGuide, 'she pushes back and leaves');
    expect(next.swipes.length, 2);
    expect(next.swipeIndex, 1);
    expect(next.text, '');
  });

  test('legacy messages without generation fields still load', () {
    final restored = ChatMessage.fromJson({
      'id': 'old',
      'role': 'assistant',
      'text': 'Hello',
      'swipes': ['Hello'],
      'swipeIndex': 0,
    });
    expect(restored.generationKind, isNull);
    expect(restored.generationGuide, isNull);
    expect(restored.isAiGenerated, isTrue);
  });
}
