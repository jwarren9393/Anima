import 'package:flutter_test/flutter_test.dart';

import 'package:anima/main.dart';
import 'package:anima/services/api_key_service.dart';
import 'package:anima/services/appearance_controller.dart';
import 'package:anima/services/character_category_service.dart';
import 'package:anima/services/character_service.dart';
import 'package:anima/services/chat_service.dart';
import 'package:anima/services/nanogpt_service.dart';
import 'package:anima/services/persona_service.dart';
import 'package:anima/services/settings_service.dart';
import 'package:anima/services/world_info_service.dart';
import 'package:anima/services/world_workshop_service.dart';
import 'package:anima/theme/anima_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  AnimaTheme.useSystemFonts = true;

  testWidgets('Anima home screen loads with history and settings', (
    WidgetTester tester,
  ) async {
    final apiKeyService = ApiKeyService();
    final settingsService = SettingsService();
    final characterService = CharacterService();
    final characterCategoryService = CharacterCategoryService();
    final personaService = PersonaService(settingsService: settingsService);
    final chatService = ChatService();
    final nanoGptService = NanoGptService(apiKeyService: apiKeyService);
    final worldInfoService = WorldInfoService();
    final worldWorkshopService = WorldWorkshopService();
    final appearanceController = AppearanceController(
      settingsService: settingsService,
    );

    await tester.pumpWidget(
      AnimaApp(
        apiKeyService: apiKeyService,
        settingsService: settingsService,
        characterService: characterService,
        characterCategoryService: characterCategoryService,
        personaService: personaService,
        chatService: chatService,
        nanoGptService: nanoGptService,
        worldInfoService: worldInfoService,
        worldWorkshopService: worldWorkshopService,
        appearanceController: appearanceController,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Anima'), findsOneWidget);
    expect(find.byTooltip('Settings'), findsOneWidget);
    expect(find.text('New chat'), findsOneWidget);
  });
}
