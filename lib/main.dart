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
import 'models/ui_style_settings.dart';
import 'theme/anima_theme.dart';
import 'theme/parchment_backdrop.dart';

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

class AnimaApp extends StatefulWidget {
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
  State<AnimaApp> createState() => _AnimaAppState();
}

class _AnimaAppState extends State<AnimaApp> {
  ThemeMode _themeMode = ThemeMode.system;
  UiStyleSettings _uiStyle = const UiStyleSettings();

  @override
  void initState() {
    super.initState();
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final name = await widget.settingsService.getThemeModeName();
    final style = await widget.settingsService.getUiStyle();
    if (!mounted) return;
    setState(() {
      _themeMode = _parseThemeMode(name);
      _uiStyle = style;
    });
  }

  ThemeMode _parseThemeMode(String name) {
    switch (name) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  Future<void> refreshTheme() => _loadTheme();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Anima',
      debugShowCheckedModeBanner: false,
      theme: AnimaTheme.light(_uiStyle),
      darkTheme: AnimaTheme.dark(_uiStyle),
      themeMode: _themeMode,
      builder: (context, child) {
        Widget content = ParchmentBackdrop(
          child: child ?? const SizedBox.shrink(),
        );
        if (_uiStyle.reduceMotion) {
          content = MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: content,
          );
        }
        return content;
      },
      home: HomeScreen(
        apiKeyService: widget.apiKeyService,
        settingsService: widget.settingsService,
        characterService: widget.characterService,
        personaService: widget.personaService,
        chatService: widget.chatService,
        nanoGptService: widget.nanoGptService,
        worldInfoService: widget.worldInfoService,
        worldWorkshopService: widget.worldWorkshopService,
        onThemeChanged: refreshTheme,
      ),
    );
  }
}
