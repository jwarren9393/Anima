import 'package:flutter/material.dart';

import '../models/character.dart';
import '../models/chat_session.dart';
import '../models/new_chat_pick.dart';
import '../services/api_key_service.dart';
import '../services/authors_note_composer.dart';
import '../services/appearance_controller.dart';
import '../services/character_category_service.dart';
import '../services/character_service.dart';
import '../services/chat_service.dart';
import '../services/composer_draft_service.dart';
import '../services/nanogpt_service.dart';
import '../services/roadway_cache_service.dart';
import '../services/persona_service.dart';
import '../services/settings_service.dart';
import '../services/world_info_service.dart';
import '../models/world_workshop.dart';
import '../services/world_workshop_service.dart';
import '../widgets/anima_avatar.dart';
import '../widgets/greeting_picker.dart';
import 'characters_screen.dart';
import 'chat_screen.dart';
import 'group_chat_setup_screen.dart';
import 'settings_screen.dart';
import 'world_workshop_chat_screen.dart';
import 'world_workshop_list_screen.dart';

/// Default landing screen — chat history and shortcuts to start chatting.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
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
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<ChatSession> _chats = [];
  List<Character> _characters = [];
  List<WorldWorkshop> _workshops = [];
  String? _lastWorkshopId;
  bool _loading = true;
  final _draftService = ComposerDraftService();
  final _roadwayCache = RoadwayCacheService();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final chats = await widget.chatService.listAllChats();
    final characters = await widget.characterService.loadCharacters();
    final workshops = await widget.worldWorkshopService.loadWorkshops();
    final lastId = await widget.worldWorkshopService.getLastOpenedId();
    if (!mounted) return;
    setState(() {
      _chats = chats;
      _characters = characters;
      _workshops = workshops;
      _lastWorkshopId = lastId;
      _loading = false;
    });
  }

  Map<String, Character> get _characterById {
    return {for (final c in _characters) c.id: c};
  }

  String _chatSubtitle(ChatSession chat) {
    final count = chat.messages.length;
    final date = _shortDate(chat.updatedAt);
    final note = AuthorsNoteComposer.hasEffectiveNote(
      manualAuthorsNote: chat.authorsNote,
      activeSceneMoodIds: chat.activeSceneMoodIds,
    )
        ? ' · Note'
        : '';
    return '$count message${count == 1 ? '' : 's'} · $date$note';
  }

  String _chatListTitle(ChatSession chat) {
    if (chat.isGroup) {
      return ChatService.displayTitle(chat);
    }
    final solo = _characterById[chat.characterId]?.name;
    if (solo != null && solo.trim().isNotEmpty) return solo.trim();
    return chat.title;
  }

  String? _lastMessagePreview(ChatSession chat) {
    for (var i = chat.messages.length - 1; i >= 0; i--) {
      final text = chat.messages[i].text.trim();
      if (text.isEmpty) continue;
      if (text.length <= 80) return text;
      return '${text.substring(0, 80)}…';
    }
    return null;
  }

  String _shortDate(DateTime value) {
    final local = value.toLocal();
    return '${local.month}/${local.day} ${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SettingsScreen(
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
      ),
    );
    // Reload after Settings closes (e.g. full backup restore).
    if (mounted) await _load();
  }

  Future<void> _openChat(ChatSession session) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(
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
          initialSession: session,
        ),
      ),
    );
    await _load();
  }

  Future<void> _showNewSheet() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: const Text('Solo chat'),
              onTap: () => Navigator.pop(context, 'solo'),
            ),
            ListTile(
              leading: const Icon(Icons.groups_outlined),
              title: const Text('Group chat'),
              onTap: () => Navigator.pop(context, 'group'),
            ),
            ListTile(
              leading: const Icon(Icons.travel_explore),
              title: const Text('New workshop'),
              onTap: () => Navigator.pop(context, 'workshop'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    if (choice == 'group') {
      await _startGroupChat();
    } else if (choice == 'workshop') {
      await _openCreationCenter(createNew: true);
    } else {
      await _startSoloChat();
    }
  }

  Future<void> _startNewChat() async => _showNewSheet();

  Future<void> _startSoloChat() async {
    final pick = await Navigator.of(context).push<NewChatPick>(
      MaterialPageRoute(
        builder: (_) => CharactersScreen(
          characterService: widget.characterService,
          categoryService: widget.characterCategoryService,
          settingsService: widget.settingsService,
          nanoGptService: widget.nanoGptService,
          personaService: widget.personaService,
          pickMode: true,
          pickPersona: true,
        ),
      ),
    );
    if (pick == null || !mounted) return;

    final greetingIndex = await pickGreetingIndex(
      context,
      character: pick.character,
      userName: pick.persona.name,
    );
    if (greetingIndex == null || !mounted) return;

    final session = await widget.chatService.startNewChat(
      pick.character,
      userName: pick.persona.name,
      personaId: pick.persona.sessionId,
      greetingIndex: greetingIndex,
    );
    if (!mounted) return;
    await _openChat(session);
  }

  Future<void> _startGroupChat() async {
    final session = await Navigator.of(context).push<ChatSession>(
      MaterialPageRoute(
        builder: (_) => GroupChatSetupScreen(
          characterService: widget.characterService,
          categoryService: widget.characterCategoryService,
          chatService: widget.chatService,
          personaService: widget.personaService,
          worldInfoService: widget.worldInfoService,
          settingsService: widget.settingsService,
          nanoGptService: widget.nanoGptService,
        ),
      ),
    );
    if (session == null || !mounted) return;
    await _openChat(session);
  }

  Future<void> _openCreationCenter({bool createNew = false}) async {
    if (createNew) {
      final workshop =
          await widget.worldWorkshopService.upsert(WorldWorkshop.empty());
      if (!mounted) return;
      await _openWorkshop(workshop);
      return;
    }
    await Navigator.of(context).push(
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
    );
    await _load();
  }

  Future<void> _openWorkshop(WorldWorkshop workshop) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WorldWorkshopChatScreen(
          workshop: workshop,
          workshopService: widget.worldWorkshopService,
          worldInfoService: widget.worldInfoService,
          characterService: widget.characterService,
          characterCategoryService: widget.characterCategoryService,
          personaService: widget.personaService,
          chatService: widget.chatService,
          apiKeyService: widget.apiKeyService,
          settingsService: widget.settingsService,
          nanoGptService: widget.nanoGptService,
          worldWorkshopService: widget.worldWorkshopService,
          appearanceController: widget.appearanceController,
        ),
      ),
    );
    await _load();
  }

  Widget _workshopsSection() {
    if (_workshops.isEmpty) return const SizedBox.shrink();
    WorldWorkshop? continueWorkshop;
    if (_lastWorkshopId != null) {
      for (final w in _workshops) {
        if (w.id == _lastWorkshopId) continueWorkshop = w;
      }
    }
    continueWorkshop ??= _workshops.first;
    final continueW = continueWorkshop;
    final tiles = <WorldWorkshop>[continueW];
    for (final w in _workshops.take(3)) {
      if (w.id != continueW.id) tiles.add(w);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Text(
                'Creation Center',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const Spacer(),
              TextButton(
                onPressed: _openCreationCenter,
                child: const Text('All worlds'),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 88,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: tiles.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final w = tiles[index];
              final isContinue = w.id == continueW.id;
              final bits = <String>[];
              if (isContinue) bits.add('continue');
              if (w.exportedLorebookId != null) bits.add('lore');
              if (w.linkedCharacterIds.isNotEmpty) {
                bits.add('${w.linkedCharacterIds.length} cast');
              }
              return Material(
                color: Theme.of(context).colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _openWorkshop(w),
                  child: Container(
                    width: 140,
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (isContinue)
                          Text(
                            'Continue',
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        Text(
                          w.title,
                          maxLines: isContinue ? 1 : 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const Spacer(),
                        Text(
                          bits.isEmpty
                              ? '${w.messages.length} msgs'
                              : bits.join(' · '),
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Future<void> _deleteChat(ChatSession chat) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete chat?'),
        content: Text(
          'Remove “${chat.title}” from this device? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await widget.chatService.deleteChat(chat.characterId, chat.id);
    await _draftService.clearDraft(chat.id);
    await _roadwayCache.clearOptions(chat.id);
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Chat deleted.')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Anima'),
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: _openSettings,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _chats.isEmpty
          ? _EmptyHome(onStartChat: _startNewChat)
          : RefreshIndicator(
              onRefresh: _load,
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(child: _workshopsSection()),
                  SliverList.separated(
                    itemCount: _chats.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final chat = _chats[index];
                      final preview = _lastMessagePreview(chat);
                      final solo = chat.isGroup
                          ? null
                          : _characterById[chat.characterId];
                      return ListTile(
                        leading: chat.isGroup
                            ? CircleAvatar(
                                child: Icon(
                                  Icons.groups,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onPrimaryContainer,
                                ),
                              )
                            : AnimaAvatar(
                                fileName: solo?.avatarFileName,
                                label: solo?.name ?? chat.title,
                                radius: 22,
                              ),
                        title: Text(
                          _chatListTitle(chat),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          preview == null
                              ? _chatSubtitle(chat)
                              : '$preview · ${_shortDate(chat.updatedAt)}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => _openChat(chat),
                        onLongPress: () => _deleteChat(chat),
                      );
                    },
                  ),
                  const SliverPadding(padding: EdgeInsets.only(bottom: 88)),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showNewSheet,
        icon: const Icon(Icons.add),
        label: const Text('New'),
      ),
    );
  }
}

class _EmptyHome extends StatelessWidget {
  const _EmptyHome({required this.onStartChat});

  final VoidCallback onStartChat;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 64,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'No chats yet',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Open a new page in your journal — pick a character, '
              'or gather a company for a group tale.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onStartChat,
              icon: const Icon(Icons.people_outline),
              label: const Text('Start a chat'),
            ),
          ],
        ),
      ),
    );
  }
}
