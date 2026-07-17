import 'package:flutter_test/flutter_test.dart';

import 'package:anima/main.dart';
import 'package:anima/services/api_key_service.dart';
import 'package:anima/services/character_service.dart';
import 'package:anima/services/chat_service.dart';
import 'package:anima/services/nanogpt_service.dart';
import 'package:anima/services/settings_service.dart';

void main() {
  testWidgets('Anima chat screen loads with character tools', (
    WidgetTester tester,
  ) async {
    final apiKeyService = ApiKeyService();
    final settingsService = SettingsService();
    final characterService = CharacterService();
    final chatService = ChatService();
    final nanoGptService = NanoGptService(apiKeyService: apiKeyService);

    await tester.pumpWidget(
      AnimaApp(
        apiKeyService: apiKeyService,
        settingsService: settingsService,
        characterService: characterService,
        chatService: chatService,
        nanoGptService: nanoGptService,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byTooltip('Characters'), findsOneWidget);
    expect(find.byTooltip('More'), findsOneWidget);
    expect(find.byTooltip('New chat'), findsOneWidget);
    expect(find.byTooltip('Saved chats'), findsOneWidget);
  });
}
