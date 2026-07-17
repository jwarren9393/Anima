import 'package:flutter/material.dart';

import 'screens/chat_screen.dart';
import 'services/api_key_service.dart';
import 'services/character_service.dart';
import 'services/chat_service.dart';
import 'services/nanogpt_service.dart';
import 'services/settings_service.dart';
import 'theme/anima_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  final apiKeyService = ApiKeyService();
  final settingsService = SettingsService();
  final characterService = CharacterService();
  final chatService = ChatService();
  final nanoGptService = NanoGptService(apiKeyService: apiKeyService);

  runApp(
    AnimaApp(
      apiKeyService: apiKeyService,
      settingsService: settingsService,
      characterService: characterService,
      chatService: chatService,
      nanoGptService: nanoGptService,
    ),
  );
}

class AnimaApp extends StatefulWidget {
  const AnimaApp({
    super.key,
    required this.apiKeyService,
    required this.settingsService,
    required this.characterService,
    required this.chatService,
    required this.nanoGptService,
  });

  final ApiKeyService apiKeyService;
  final SettingsService settingsService;
  final CharacterService characterService;
  final ChatService chatService;
  final NanoGptService nanoGptService;

  @override
  State<AnimaApp> createState() => _AnimaAppState();
}

class _AnimaAppState extends State<AnimaApp> {
  ThemeMode _themeMode = ThemeMode.system;

  @override
  void initState() {
    super.initState();
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final name = await widget.settingsService.getThemeModeName();
    if (!mounted) return;
    setState(() => _themeMode = _parseThemeMode(name));
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
      theme: AnimaTheme.light(),
      darkTheme: AnimaTheme.dark(),
      themeMode: _themeMode,
      home: ChatScreen(
        apiKeyService: widget.apiKeyService,
        settingsService: widget.settingsService,
        characterService: widget.characterService,
        chatService: widget.chatService,
        nanoGptService: widget.nanoGptService,
        onThemeChanged: refreshTheme,
      ),
    );
  }
}
