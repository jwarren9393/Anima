import 'package:flutter_test/flutter_test.dart';

import 'package:anima/main.dart';
import 'package:anima/services/api_key_service.dart';
import 'package:anima/services/character_service.dart';
import 'package:anima/services/nanogpt_service.dart';
import 'package:anima/services/settings_service.dart';

void main() {
  testWidgets('Anima chat screen shows character empty state', (
    WidgetTester tester,
  ) async {
    final apiKeyService = ApiKeyService();
    final settingsService = SettingsService();
    final characterService = CharacterService();
    final nanoGptService = NanoGptService(apiKeyService: apiKeyService);

    await tester.pumpWidget(
      AnimaApp(
        apiKeyService: apiKeyService,
        settingsService: settingsService,
        characterService: characterService,
        nanoGptService: nanoGptService,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byTooltip('Characters'), findsOneWidget);
    expect(find.byTooltip('Settings'), findsOneWidget);
    expect(find.textContaining('Chat with'), findsOneWidget);
  });
}
