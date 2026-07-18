import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'services/api_key_service.dart';
import 'services/appearance_controller.dart';
import 'services/character_category_service.dart';
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
  final characterCategoryService = CharacterCategoryService();
  final personaService = PersonaService(settingsService: settingsService);
  final chatService = ChatService();
  final nanoGptService = NanoGptService(apiKeyService: apiKeyService);
  final worldInfoService = WorldInfoService();
  final worldWorkshopService = WorldWorkshopService();
  final appearanceController = AppearanceController(
    settingsService: settingsService,
  );

  runApp(
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
}

class AnimaApp extends StatefulWidget {
  const AnimaApp({
    super.key,
    required this.apiKeyService,
    required this.settingsService,
    required this.characterService,
    required this.characterCategoryService,
    required this.personaService,
    required this.chatService,
    required this.nanoGptService,
    required this.worldInfoService,
    required this.worldWorkshopService,
    required this.appearanceController,
  });

  final ApiKeyService apiKeyService;
  final SettingsService settingsService;
  final CharacterService characterService;
  final CharacterCategoryService characterCategoryService;
  final PersonaService personaService;
  final ChatService chatService;
  final NanoGptService nanoGptService;
  final WorldInfoService worldInfoService;
  final WorldWorkshopService worldWorkshopService;
  final AppearanceController appearanceController;

  @override
  State<AnimaApp> createState() => _AnimaAppState();
}

class _AnimaAppState extends State<AnimaApp> {
  @override
  void initState() {
    super.initState();
    widget.appearanceController.addListener(_onAppearanceChanged);
    widget.appearanceController.load();
  }

  @override
  void dispose() {
    widget.appearanceController.removeListener(_onAppearanceChanged);
    super.dispose();
  }

  void _onAppearanceChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.appearanceController.style;
    final theme = AnimaTheme.fromSettings(style);
    final mode = style.palette.brightness == Brightness.light
        ? ThemeMode.light
        : ThemeMode.dark;

    return MaterialApp(
      title: 'Anima',
      debugShowCheckedModeBanner: false,
      theme: theme,
      darkTheme: theme,
      themeMode: mode,
      builder: (context, child) {
        return GlassBackdrop(
          settings: style,
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: HomeScreen(
        apiKeyService: widget.apiKeyService,
        settingsService: widget.settingsService,
        characterService: widget.characterService,
        characterCategoryService: widget.characterCategoryService,
        personaService: widget.personaService,
        chatService: widget.chatService,
        nanoGptService: widget.nanoGptService,
        worldInfoService: widget.worldInfoService,
        worldWorkshopService: widget.worldWorkshopService,
        appearanceController: widget.appearanceController,
      ),
    );
  }
}
