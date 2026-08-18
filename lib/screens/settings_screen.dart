import 'package:flutter/material.dart';

import '../services/api_key_service.dart';
import '../services/app_data_root.dart';
import '../services/appearance_controller.dart';
import '../services/character_category_service.dart';
import '../services/character_service.dart';
import '../services/chat_service.dart';
import '../services/nanogpt_service.dart';
import '../services/persona_service.dart';
import '../services/settings_service.dart';
import '../services/world_info_service.dart';
import '../services/world_workshop_service.dart';
import 'api_settings_screen.dart';
import 'appearance_settings_screen.dart';
import 'backup_restore_screen.dart';
import 'characters_screen.dart';
import 'collaborator_settings_screen.dart';
import 'character_build_settings_screen.dart';
import 'data_folder_settings_screen.dart';
import 'global_chat_prompts_screen.dart';
import 'lore_settings_screen.dart';
import 'personas_screen.dart';
import 'sampling_settings_screen.dart';
import 'world_workshop_list_screen.dart';

/// Top-level settings menu — each area opens its own screen.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
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
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _modelLabel = '';
  bool _hasKey = false;
  bool _loadingStatus = true;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    final model = await widget.settingsService.getModel();
    final key = await widget.apiKeyService.getApiKey();
    if (!mounted) return;
    setState(() {
      _modelLabel = model;
      _hasKey = key != null && key.trim().isNotEmpty;
      _loadingStatus = false;
    });
  }

  Future<void> _openApiSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ApiSettingsScreen(
          apiKeyService: widget.apiKeyService,
          settingsService: widget.settingsService,
          nanoGptService: widget.nanoGptService,
        ),
      ),
    );
    await _loadStatus();
  }

  Future<void> _openAppearance() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AppearanceSettingsScreen(
          settingsService: widget.settingsService,
          appearanceController: widget.appearanceController,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final statusLine = _loadingStatus
        ? 'Loading…'
        : _hasKey
        ? 'Model: $_modelLabel'
        : 'No API key — tap to add';

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Material(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: _openApiSettings,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _hasKey ? Icons.link : Icons.key_off,
                        color: _hasKey ? scheme.primary : scheme.error,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'API & connection',
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            Text(
                              statusLine,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const _SettingsSectionHeader('World'),
          _SettingsTile(
            icon: Icons.face,
            title: 'Personas',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => PersonasScreen(
                  personaService: widget.personaService,
                  settingsService: widget.settingsService,
                  nanoGptService: widget.nanoGptService,
                ),
              ),
            ),
          ),
          _SettingsTile(
            icon: Icons.people_outline,
            title: 'Characters',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => CharactersScreen(
                  characterService: widget.characterService,
                  categoryService: widget.characterCategoryService,
                  settingsService: widget.settingsService,
                  nanoGptService: widget.nanoGptService,
                ),
              ),
            ),
          ),
          _SettingsTile(
            icon: Icons.menu_book,
            title: 'World Info & lore',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => LoreSettingsScreen(
                  settingsService: widget.settingsService,
                  characterService: widget.characterService,
                  characterCategoryService: widget.characterCategoryService,
                  worldInfoService: widget.worldInfoService,
                  nanoGptService: widget.nanoGptService,
                ),
              ),
            ),
          ),
          _SettingsTile(
            icon: Icons.travel_explore,
            title: 'Creation Center',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => WorldWorkshopListScreen(
                  workshopService: widget.worldWorkshopService,
                  worldInfoService: widget.worldInfoService,
                  characterService: widget.characterService,
                  characterCategoryService: widget.characterCategoryService,
                  personaService: widget.personaService,
                  chatService: widget.chatService,
                  apiKeyService: widget.apiKeyService,
                  settingsService: widget.settingsService,
                  nanoGptService: widget.nanoGptService,
                  appearanceController: widget.appearanceController,
                ),
              ),
            ),
          ),
          const _SettingsSectionHeader('AI'),
          _SettingsTile(
            icon: Icons.tune,
            title: 'Generation parameters',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => SamplingSettingsScreen(
                  settingsService: widget.settingsService,
                ),
              ),
            ),
          ),
          _SettingsTile(
            icon: Icons.article_outlined,
            title: 'Global chat prompts',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => GlobalChatPromptsScreen(
                  settingsService: widget.settingsService,
                ),
              ),
            ),
          ),
          _SettingsTile(
            icon: Icons.auto_awesome,
            title: 'AI collaborator',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => CollaboratorSettingsScreen(
                  settingsService: widget.settingsService,
                ),
              ),
            ),
          ),
          _SettingsTile(
            icon: Icons.badge_outlined,
            title: 'Character builds',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => CharacterBuildSettingsScreen(
                  settingsService: widget.settingsService,
                ),
              ),
            ),
          ),
          const _SettingsSectionHeader('App'),
          _SettingsTile(
            icon: Icons.folder_open,
            title: 'Data folder',
            onTap: () {
              final root = AppDataRoot.instance;
              if (root == null) return;
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => DataFolderSettingsScreen(dataRoot: root),
                ),
              );
            },
          ),
          _SettingsTile(
            icon: Icons.palette,
            title: 'Appearance',
            onTap: _openAppearance,
          ),
          _SettingsTile(
            icon: Icons.backup,
            title: 'Backup, restore & sync',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => BackupRestoreScreen(
                  settingsService: widget.settingsService,
                  personaService: widget.personaService,
                  appearanceController: widget.appearanceController,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Text(
              'NanoGPT key is stored in your Anima folder (api_key.txt). '
              'Copy that folder to move the whole library.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsSectionHeader extends StatelessWidget {
  const _SettingsSectionHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
