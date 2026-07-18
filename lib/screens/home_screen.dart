import 'package:flutter/material.dart';

import '../models/character.dart';
import '../models/chat_session.dart';
import '../services/api_key_service.dart';
import '../services/character_category_service.dart';
import '../services/character_service.dart';
import '../services/chat_service.dart';
import '../services/composer_draft_service.dart';
import '../services/nanogpt_service.dart';
import '../services/roadway_cache_service.dart';
import '../services/persona_service.dart';
import '../services/settings_service.dart';
import '../services/world_info_service.dart';
import '../services/world_workshop_service.dart';
import '../widgets/anima_avatar.dart';
import '../widgets/greeting_picker.dart';
import 'characters_screen.dart';
import 'chat_screen.dart';
import 'group_chat_setup_screen.dart';
import 'settings_screen.dart';

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

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<ChatSession> _chats = [];
  List<Character> _characters = [];
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
    if (!mounted) return;
    setState(() {
      _chats = chats;
      _characters = characters;
      _loading = false;
    });
  }

  Map<String, Character> get _characterById {
    return {for (final c in _characters) c.id: c};
  }

  String _chatSubtitle(ChatSession chat) {
    final count = chat.messages.length;
    final date = _shortDate(chat.updatedAt);
    final note = chat.authorsNote.trim().isEmpty ? '' : ' · Note';
    return '$count message${count == 1 ? '' : 's'} · $date$note';
  }

  String _chatLabel(ChatSession chat) {
    if (chat.isGroup) {
      final names = <String>[];
      for (final id in chat.effectiveParticipantIds) {
        final name = _characterById[id]?.name;
        if (name != null && name.trim().isNotEmpty) names.add(name.trim());
      }
      if (names.isEmpty) return 'Group chat';
      return 'Group · ${names.join(', ')}';
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
          nanoGptService: widget.nanoGptService,
          worldInfoService: widget.worldInfoService,
          worldWorkshopService: widget.worldWorkshopService,
        ),
      ),
    );
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
          initialSession: session,
        ),
      ),
    );
    await _load();
  }

  Future<void> _startNewChat() async {
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
              subtitle: const Text('One character'),
              onTap: () => Navigator.pop(context, 'solo'),
            ),
            ListTile(
              leading: const Icon(Icons.groups_outlined),
              title: const Text('Group chat'),
              subtitle: const Text(
                'Several characters — set reply order, auto-reply, lore, note',
              ),
              onTap: () => Navigator.pop(context, 'group'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    if (choice == 'group') {
      await _startGroupChat();
    } else {
      await _startSoloChat();
    }
  }

  Future<void> _startSoloChat() async {
    final character = await Navigator.of(context).push<Character>(
      MaterialPageRoute(
        builder: (_) => CharactersScreen(
          characterService: widget.characterService,
          categoryService: widget.characterCategoryService,
          settingsService: widget.settingsService,
          nanoGptService: widget.nanoGptService,
          pickMode: true,
        ),
      ),
    );
    if (character == null || !mounted) return;

    final persona = await widget.personaService.getActivePersona();
    if (!mounted) return;
    final greetingIndex = await pickGreetingIndex(
      context,
      character: character,
      userName: persona.name,
    );
    if (greetingIndex == null || !mounted) return;

    final session = await widget.chatService.startNewChat(
      character,
      userName: persona.name,
      personaId: persona.id,
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
        ),
      ),
    );
    if (session == null || !mounted) return;
    await _openChat(session);
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
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Chat deleted.')),
    );
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
                  child: ListView.separated(
                    padding: const EdgeInsets.only(bottom: 88),
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
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onPrimaryContainer,
                                ),
                              )
                            : AnimaAvatar(
                                fileName: solo?.avatarFileName,
                                label: solo?.name ?? chat.title,
                                radius: 22,
                              ),
                        title: Text(
                          chat.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _chatLabel(chat),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              preview == null
                                  ? _chatSubtitle(chat)
                                  : '$preview\n${_chatSubtitle(chat)}',
                              maxLines: preview == null ? 1 : 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                        isThreeLine: preview != null,
                        onTap: () => _openChat(chat),
                        onLongPress: () => _deleteChat(chat),
                      );
                    },
                  ),
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _startNewChat,
        icon: const Icon(Icons.add_comment_outlined),
        label: const Text('New chat'),
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
