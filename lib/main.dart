import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'services/api_key_service.dart';
import 'services/character_service.dart';
import 'services/chat_service.dart';
import 'services/nanogpt_service.dart';
import 'services/persona_service.dart';
import 'services/settings_service.dart';
import 'services/world_info_service.dart';
import 'services/world_workshop_service.dart';
import 'theme/anima_theme.dart';
import 'theme/glass_backdrop.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  final apiKeyService = ApiKeyService();
  final settingsService = SettingsService();
  final characterService = CharacterService();
  final personaService = PersonaService(settingsService: settingsService);
  final chatService = ChatService();
  final nanoGptService = NanoGptService(apiKeyService: apiKeyService);
  final worldInfoService = WorldInfoService();
  final worldWorkshopService = WorldWorkshopService();

  runApp(
    AnimaApp(
      apiKeyService: apiKeyService,
      settingsService: settingsService,
      characterService: characterService,
      personaService: personaService,
      chatService: chatService,
      nanoGptService: nanoGptService,
      worldInfoService: worldInfoService,
      worldWorkshopService: worldWorkshopService,
    ),
  );
}

class AnimaApp extends StatelessWidget {
  const AnimaApp({
    super.key,
    required this.apiKeyService,
    required this.settingsService,
    required this.characterService,
    required this.personaService,
    required this.chatService,
    required this.nanoGptService,
    required this.worldInfoService,
    required this.worldWorkshopService,
  });

  final ApiKeyService apiKeyService;
  final SettingsService settingsService;
  final CharacterService characterService;
  final PersonaService personaService;
  final ChatService chatService;
  final NanoGptService nanoGptService;
  final WorldInfoService worldInfoService;
  final WorldWorkshopService worldWorkshopService;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Anima',
      debugShowCheckedModeBanner: false,
      theme: AnimaTheme.dark(),
      darkTheme: AnimaTheme.dark(),
      themeMode: ThemeMode.dark,
      builder: (context, child) {
        return GlassBackdrop(
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: HomeScreen(
        apiKeyService: apiKeyService,
        settingsService: settingsService,
        characterService: characterService,
        personaService: personaService,
        chatService: chatService,
        nanoGptService: nanoGptService,
        worldInfoService: worldInfoService,
        worldWorkshopService: worldWorkshopService,
      ),
    );
  }
}
