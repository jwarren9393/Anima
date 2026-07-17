import 'package:flutter/material.dart';

import 'screens/chat_screen.dart';
import 'services/api_key_service.dart';
import 'services/character_service.dart';
import 'services/nanogpt_service.dart';
import 'services/settings_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  final apiKeyService = ApiKeyService();
  final settingsService = SettingsService();
  final characterService = CharacterService();
  final nanoGptService = NanoGptService(apiKeyService: apiKeyService);

  runApp(
    AnimaApp(
      apiKeyService: apiKeyService,
      settingsService: settingsService,
      characterService: characterService,
      nanoGptService: nanoGptService,
    ),
  );
}

class AnimaApp extends StatelessWidget {
  const AnimaApp({
    super.key,
    required this.apiKeyService,
    required this.settingsService,
    required this.characterService,
    required this.nanoGptService,
  });

  final ApiKeyService apiKeyService;
  final SettingsService settingsService;
  final CharacterService characterService;
  final NanoGptService nanoGptService;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Anima',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: .fromSeed(
          seedColor: const Color(0xFF2F6F6A),
          brightness: .light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: .fromSeed(
          seedColor: const Color(0xFF2F6F6A),
          brightness: .dark,
        ),
        useMaterial3: true,
      ),
      themeMode: .system,
      home: ChatScreen(
        apiKeyService: apiKeyService,
        settingsService: settingsService,
        characterService: characterService,
        nanoGptService: nanoGptService,
      ),
    );
  }
}
