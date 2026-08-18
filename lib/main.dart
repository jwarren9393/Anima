import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'screens/data_folder_setup_screen.dart';
import 'screens/home_screen.dart';
import 'services/api_key_service.dart';
import 'services/app_data_root.dart';
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
import 'utils/windows_paste_handler.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb && Platform.isWindows) {
    WindowsPasteHandler.install();
  }

  runApp(const AnimaBootstrap());
}

/// Chooses the visible data folder, then starts the real app.
class AnimaBootstrap extends StatefulWidget {
  const AnimaBootstrap({super.key});

  @override
  State<AnimaBootstrap> createState() => _AnimaBootstrapState();
}

class _AnimaBootstrapState extends State<AnimaBootstrap> {
  late final AppDataRoot _dataRoot;
  Widget? _app;
  bool _ready = false;
  bool _needsSetup = true;

  @override
  void initState() {
    super.initState();
    _dataRoot = AppDataRoot.platform();
    AppDataRoot.instance = _dataRoot;
    _boot();
  }

  Future<void> _boot() async {
    final configured = await _dataRoot.load();
    if (!mounted) return;
    setState(() {
      if (configured) {
        _app = _createApp();
        _needsSetup = false;
      } else {
        _needsSetup = true;
      }
      _ready = true;
    });
  }

  void _onFolderReady() {
    setState(() {
      _app = _createApp();
      _needsSetup = false;
    });
  }

  Widget _createApp() {
    final apiKeyService = ApiKeyService();
    final settingsService = SettingsService(
      documentsDirectory: _dataRoot.directory,
    );
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

    return AnimaApp(
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = AnimaTheme.dark();
    if (!_ready) {
      return MaterialApp(
        title: 'Anima',
        debugShowCheckedModeBanner: false,
        theme: theme,
        home: const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    if (_needsSetup) {
      return MaterialApp(
        title: 'Anima',
        debugShowCheckedModeBanner: false,
        theme: theme,
        home: DataFolderSetupScreen(
          dataRoot: _dataRoot,
          onReady: _onFolderReady,
        ),
      );
    }
    return _app ?? const SizedBox.shrink();
  }
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
