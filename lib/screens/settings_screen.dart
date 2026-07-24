import 'package:flutter/material.dart';

import '../services/api_key_service.dart';
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
import 'lore_settings_screen.dart';
import 'personas_screen.dart';
import 'sampling_settings_screen.dart';
import 'world_workshop_list_screen.dart';

/// Top-level settings menu — each area opens its own screen.
class SettingsScreen extends StatelessWidget {
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

  Future<void> _openAppearance(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AppearanceSettingsScreen(
          settingsService: settingsService,
          appearanceController: appearanceController,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          _SettingsTile(
            icon: Icons.key,
            title: 'API & connection',
            subtitle: 'API key, model, subscription endpoint',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ApiSettingsScreen(
                  apiKeyService: apiKeyService,
                  settingsService: settingsService,
                  nanoGptService: nanoGptService,
                ),
              ),
            ),
          ),
          _SettingsTile(
            icon: Icons.face,
            title: 'Personas',
            subtitle: 'Who you are ({{user}}) — create and switch',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => PersonasScreen(
                  personaService: personaService,
                  settingsService: settingsService,
                  nanoGptService: nanoGptService,
                ),
              ),
            ),
          ),
          _SettingsTile(
            icon: Icons.people_outline,
            title: 'Characters',
            subtitle: 'Create, import, and edit character cards',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => CharactersScreen(
                  characterService: characterService,
                  categoryService: characterCategoryService,
                  settingsService: settingsService,
                  nanoGptService: nanoGptService,
                ),
              ),
            ),
          ),
          _SettingsTile(
            icon: Icons.menu_book,
            title: 'World Info & lore',
            subtitle: 'Global lorebooks, scan depth, character books',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => LoreSettingsScreen(
                  settingsService: settingsService,
                  characterService: characterService,
                  characterCategoryService: characterCategoryService,
                  worldInfoService: worldInfoService,
                  nanoGptService: nanoGptService,
                ),
              ),
            ),
          ),
          _SettingsTile(
            icon: Icons.travel_explore,
            title: 'Creation Center',
            subtitle: 'Build lorebooks/characters; import chat or lorebook',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => WorldWorkshopListScreen(
                  workshopService: worldWorkshopService,
                  worldInfoService: worldInfoService,
                  characterService: characterService,
                  personaService: personaService,
                  chatService: chatService,
                  settingsService: settingsService,
                  nanoGptService: nanoGptService,
                ),
              ),
            ),
          ),
          _SettingsTile(
            icon: Icons.tune,
            title: 'Generation parameters',
            subtitle: 'Presets, context size, summarization, sampling help',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    SamplingSettingsScreen(settingsService: settingsService),
              ),
            ),
          ),
          _SettingsTile(
            icon: Icons.auto_awesome,
            title: 'AI collaborator',
            subtitle: 'Wand + Format + Roadway notes',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => CollaboratorSettingsScreen(
                  settingsService: settingsService,
                ),
              ),
            ),
          ),
          _SettingsTile(
            icon: Icons.badge_outlined,
            title: 'Character builds',
            subtitle: 'Model, tokens, and prompt for full card generation',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => CharacterBuildSettingsScreen(
                  settingsService: settingsService,
                ),
              ),
            ),
          ),
          _SettingsTile(
            icon: Icons.palette,
            title: 'Appearance',
            subtitle: 'Theme presets, colors, fonts, chat avatars',
            onTap: () => _openAppearance(context),
          ),
          _SettingsTile(
            icon: Icons.backup,
            title: 'Backup & restore',
            subtitle: 'Export or replace chats, characters, settings…',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => BackupRestoreScreen(
                  settingsService: settingsService,
                  personaService: personaService,
                  appearanceController: appearanceController,
                ),
              ),
            ),
          ),
          const Divider(height: 32),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'Get a NanoGPT key at nano-gpt.com. Secrets stay on this device only.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
