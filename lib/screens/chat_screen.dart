import 'package:flutter/material.dart';

import '../models/character.dart';
import '../models/chat_message.dart';
import '../models/chat_session.dart';
import '../services/api_key_service.dart';
import '../services/character_service.dart';
import '../services/chat_service.dart';
import '../services/nanogpt_service.dart';
import '../services/prompt_builder.dart';
import '../services/settings_service.dart';
import 'characters_screen.dart';
import 'settings_screen.dart';

/// Main chat screen with saved history, streaming, and SillyTavern-like controls.
class ChatScreen extends StatefulWidget {
  const ChatScreen({
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
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  final _promptBuilder = const PromptBuilder();

  bool _hasApiKey = false;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  Character? _character;
  ChatSession? _session;

  List<ChatMessage> get _messages => _session?.messages ?? const [];

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final hasKey = await widget.apiKeyService.hasApiKey();
    final character = await _resolveSelectedCharacter();
    final userName = await widget.settingsService.getUserName();
    final session = await widget.chatService.loadOrCreateActiveChat(
      character,
      userName: userName,
    );
    if (!mounted) return;
    setState(() {
      _hasApiKey = hasKey;
      _character = character;
      _session = session;
      _loading = false;
    });
    _scrollToBottom(jump: true);
  }

  Future<Character> _resolveSelectedCharacter() async {
    final characters = await widget.characterService.loadCharacters();
    final selectedId = await widget.settingsService.getSelectedCharacterId();
    Character chosen = characters.first;
    for (final character in characters) {
      if (character.id == selectedId) {
        chosen = character;
        break;
      }
    }
    await widget.settingsService.saveSelectedCharacterId(chosen.id);
    return chosen;
  }

  Future<void> _persist() async {
    final session = _session;
    if (session == null) return;
    await widget.chatService.saveChat(session);
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsScreen(
          apiKeyService: widget.apiKeyService,
          settingsService: widget.settingsService,
        ),
      ),
    );
    final hasKey = await widget.apiKeyService.hasApiKey();
    if (!mounted) return;
    setState(() => _hasApiKey = hasKey);
  }

  Future<void> _openCharacters() async {
    final previousId = _character?.id;
    final selected = await Navigator.of(context).push<Character>(
      MaterialPageRoute(
        builder: (_) => CharactersScreen(
          characterService: widget.characterService,
          settingsService: widget.settingsService,
        ),
      ),
    );

    final character = selected ?? await _resolveSelectedCharacter();
    if (!mounted) return;

    if (previousId == character.id) {
      // Character may have been edited (greeting / prompt). Refresh object only.
      setState(() => _character = character);
      return;
    }

    final session = await widget.chatService.loadOrCreateActiveChat(
      character,
      userName: await widget.settingsService.getUserName(),
    );
    if (!mounted) return;
    setState(() {
      _character = character;
      _session = session;
      _error = null;
    });
    _scrollToBottom(jump: true);
  }

  Future<void> _newChat() async {
    final character = _character;
    if (character == null || _busy) return;
    final session = await widget.chatService.startNewChat(
      character,
      userName: await widget.settingsService.getUserName(),
    );
    if (!mounted) return;
    setState(() {
      _session = session;
      _error = null;
    });
    _scrollToBottom(jump: true);
  }

  Future<void> _pickChat() async {
    final character = _character;
    if (character == null || _busy) return;
    final chats = await widget.chatService.listChats(character.id);
    if (!mounted) return;

    final chosen = await showModalBottomSheet<ChatSession>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        if (chats.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Text('No saved chats yet.'),
          );
        }
        return ListView.separated(
          shrinkWrap: true,
          itemCount: chats.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final chat = chats[index];
            final selected = chat.id == _session?.id;
            return ListTile(
              selected: selected,
              title: Text(chat.title),
              subtitle: Text(
                '${chat.messages.length} messages · ${_shortDate(chat.updatedAt)}',
              ),
              trailing: selected ? const Icon(Icons.check) : null,
              onTap: () => Navigator.pop(context, chat),
            );
          },
        );
      },
    );

    if (chosen == null || !mounted) return;
    await widget.chatService.setActiveChatId(character.id, chosen.id);
    setState(() {
      _session = chosen;
      _error = null;
    });
    _scrollToBottom(jump: true);
  }

  String _shortDate(DateTime value) {
    final local = value.toLocal();
    return '${local.month}/${local.day} ${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _send() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _busy || _session == null || _character == null) return;

    if (!_hasApiKey) {
      setState(() {
        _error = 'Add your NanoGPT API key in Settings before you can chat.';
      });
      return;
    }

    FocusScope.of(context).unfocus();
    _inputController.clear();

    final userMessage = ChatMessage(
      id: ChatMessage.newId(),
      role: ChatRole.user,
      text: text,
    );
    final assistantPlaceholder = ChatMessage(
      id: ChatMessage.newId(),
      role: ChatRole.assistant,
      text: '',
      swipes: const [''],
      swipeIndex: 0,
    );

    setState(() {
      _error = null;
      _busy = true;
      _session!.messages.add(userMessage);
      _session!.messages.add(assistantPlaceholder);
    });
    _scrollToBottom();
    await _persist();
    await _streamIntoLastAssistant(excludeLastAssistant: true);
  }

  Future<void> _regenerateOrSwipe({required bool asNewSwipe}) async {
    if (_busy || _session == null || _character == null || _messages.isEmpty) {
      return;
    }
    if (!_hasApiKey) {
      setState(() {
        _error = 'Add your NanoGPT API key in Settings before you can chat.';
      });
      return;
    }

    final last = _messages.last;
    if (last.isUser) {
      setState(() {
        _error = 'Send a message first so there is an AI reply to regenerate.';
      });
      return;
    }

    setState(() {
      _error = null;
      _busy = true;
      if (asNewSwipe) {
        // Keep current text; new generation becomes another swipe.
        final updated = last.withNewSwipe('');
        _session!.messages[_messages.length - 1] = ChatMessage(
          id: updated.id,
          role: updated.role,
          text: '',
          swipes: [...last.swipes, ''],
          swipeIndex: last.swipes.length,
        );
      } else {
        // Regenerate replaces the visible swipe text.
        final swipes = List<String>.from(last.swipes);
        if (swipes.isEmpty) swipes.add('');
        final index = last.swipeIndex.clamp(0, swipes.length - 1);
        swipes[index] = '';
        _session!.messages[_messages.length - 1] = ChatMessage(
          id: last.id,
          role: last.role,
          text: '',
          swipes: swipes,
          swipeIndex: index,
        );
      }
    });
    _scrollToBottom();

    await _streamIntoLastAssistant(
      excludeLastAssistant: true,
      allowGreetingNudge: true,
    );
  }

  Future<List<Map<String, String>>> _buildApiMessages({
    required bool excludeLastAssistant,
    bool allowGreetingNudge = false,
  }) async {
    final character = _character!;
    final userName = await widget.settingsService.getUserName();
    final persona = await widget.settingsService.getUserPersona();
    final system = _promptBuilder.buildSystemPrompt(
      character: character,
      userName: userName,
      userPersona: persona,
    );
    final postHistory = _promptBuilder.buildPostHistory(
      character: character,
      userName: userName,
    );

    final msgs = <Map<String, String>>[
      {'role': 'system', 'content': system},
    ];

    final end = excludeLastAssistant ? _messages.length - 1 : _messages.length;
    for (var i = 0; i < end; i++) {
      final message = _messages[i];
      if (message.text.trim().isEmpty) continue;
      msgs.add(message.toApiMap());
    }

    if (allowGreetingNudge && msgs.length <= 1) {
      msgs.add({
        'role': 'user',
        'content':
            '(Write an alternate opening greeting in character. Stay in first person as the character.)',
      });
    }

    if (postHistory.isNotEmpty) {
      msgs.add({'role': 'system', 'content': postHistory});
    }
    return msgs;
  }

  Future<void> _streamIntoLastAssistant({
    required bool excludeLastAssistant,
    bool allowGreetingNudge = false,
  }) async {
    try {
      final model = await widget.settingsService.getModel();
      final messages = await _buildApiMessages(
        excludeLastAssistant: excludeLastAssistant,
        allowGreetingNudge: allowGreetingNudge,
      );
      final buffer = StringBuffer();
      await for (final chunk in widget.nanoGptService.streamCompletion(
        model: model,
        messages: messages,
      )) {
        if (!mounted) return;
        buffer.write(chunk);
        final text = buffer.toString();
        setState(() {
          final last = _messages.last;
          final swipes = List<String>.from(last.swipes);
          final index =
              last.swipeIndex.clamp(0, (swipes.length - 1).clamp(0, 9999));
          if (swipes.isEmpty) {
            swipes.add(text);
          } else {
            swipes[index] = text;
          }
          _session!.messages[_messages.length - 1] = ChatMessage(
            id: last.id,
            role: ChatRole.assistant,
            text: text,
            swipes: swipes,
            swipeIndex: index,
          );
        });
        _scrollToBottom();
      }

      if (!mounted) return;
      final finalText = _messages.last.text.trim();
      if (finalText.isEmpty) {
        throw NanoGptException('NanoGPT returned an empty reply. Try again.');
      }
      setState(() => _busy = false);
      await _persist();
    } on NanoGptException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error.message;
        if (_messages.isNotEmpty &&
            !_messages.last.isUser &&
            _messages.last.text.trim().isEmpty) {
          final last = _messages.last;
          if (last.swipes.length > 1 &&
              last.swipeIndex == last.swipes.length - 1) {
            final previous = List<String>.from(last.swipes)..removeLast();
            _session!.messages[_messages.length - 1] = ChatMessage(
              id: last.id,
              role: last.role,
              text: previous.last,
              swipes: previous,
              swipeIndex: previous.length - 1,
            );
          } else {
            _session!.messages.removeLast();
          }
        }
      });
      await _persist();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Something unexpected went wrong: $error';
      });
      await _persist();
    }
  }

  Future<void> _editMessage(int index) async {
    if (_busy || _session == null) return;
    final message = _messages[index];
    final controller = TextEditingController(text: message.text);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(message.isUser ? 'Edit your message' : 'Edit reply'),
        content: TextField(
          controller: controller,
          minLines: 3,
          maxLines: 10,
          autofocus: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null || !mounted) return;
    final trimmed = result.trim();
    if (trimmed.isEmpty) return;
    setState(() {
      _session!.messages[index] = message.withEditedText(trimmed);
    });
    await _persist();
  }

  Future<void> _deleteMessage(int index) async {
    if (_busy || _session == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete message?'),
        content: const Text('Remove this message from the saved chat?'),
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
    setState(() => _session!.messages.removeAt(index));
    await _persist();
  }

  void _shiftSwipe(int delta) {
    if (_busy || _session == null || _messages.isEmpty) return;
    final last = _messages.last;
    if (last.isUser || last.swipes.length < 2) return;
    final next = last.withSwipeIndex(last.swipeIndex + delta);
    setState(() => _session!.messages[_messages.length - 1] = next);
    _persist();
  }

  void _scrollToBottom({bool jump = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final target = _scrollController.position.maxScrollExtent;
      if (jump) {
        _scrollController.jumpTo(target);
      } else {
        _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final characterName = _character?.name ?? 'Anima';
    final showSwipeBar = !_busy &&
        _messages.isNotEmpty &&
        !_messages.last.isUser &&
        _messages.last.swipes.length > 1;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: .start,
          children: [
            Text(characterName),
            if (_session != null)
              Text(
                _session!.title,
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Saved chats',
            icon: const Icon(Icons.history),
            onPressed: _loading || _busy ? null : _pickChat,
          ),
          IconButton(
            tooltip: 'New chat',
            icon: const Icon(Icons.add_comment_outlined),
            onPressed: _loading || _busy ? null : _newChat,
          ),
          IconButton(
            tooltip: 'Characters',
            icon: const Icon(Icons.people_outline),
            onPressed: _loading || _busy ? null : _openCharacters,
          ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings),
            onPressed: _openSettings,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_loading)
            const LinearProgressIndicator(minHeight: 2)
          else if (!_hasApiKey)
            Material(
              color: colorScheme.errorContainer,
              child: ListTile(
                leading: Icon(Icons.key_off, color: colorScheme.onErrorContainer),
                title: Text(
                  'No API key yet',
                  style: TextStyle(color: colorScheme.onErrorContainer),
                ),
                subtitle: Text(
                  'Open Settings to paste your NanoGPT key, then you can chat.',
                  style: TextStyle(color: colorScheme.onErrorContainer),
                ),
                trailing: TextButton(
                  onPressed: _openSettings,
                  child: const Text('Settings'),
                ),
              ),
            ),
          Expanded(
            child: _messages.isEmpty && !_busy
                ? _EmptyChat(
                    hasApiKey: _hasApiKey,
                    characterName: characterName,
                    onOpenSettings: _openSettings,
                    onOpenCharacters: _openCharacters,
                    onNewChat: _newChat,
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final message = _messages[index];
                      final isLast = index == _messages.length - 1;
                      return _MessageBubble(
                        message: message,
                        showThinking: _busy && isLast && !message.isUser && message.text.isEmpty,
                        onLongPress: _busy
                            ? null
                            : () => _showMessageMenu(index),
                      );
                    },
                  ),
          ),
          if (showSwipeBar)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
              child: Row(
                mainAxisAlignment: .center,
                children: [
                  IconButton(
                    tooltip: 'Previous swipe',
                    onPressed: _messages.last.swipeIndex > 0
                        ? () => _shiftSwipe(-1)
                        : null,
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Text(
                    'Swipe ${_messages.last.swipeIndex + 1}/${_messages.last.swipes.length}',
                  ),
                  IconButton(
                    tooltip: 'Next swipe',
                    onPressed: _messages.last.swipeIndex <
                            _messages.last.swipes.length - 1
                        ? () => _shiftSwipe(1)
                        : null,
                    icon: const Icon(Icons.chevron_right),
                  ),
                  IconButton(
                    tooltip: 'Generate another swipe',
                    onPressed: () => _regenerateOrSwipe(asNewSwipe: true),
                    icon: const Icon(Icons.auto_awesome),
                  ),
                  IconButton(
                    tooltip: 'Regenerate',
                    onPressed: () => _regenerateOrSwipe(asNewSwipe: false),
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
            )
          else if (!_busy &&
              _messages.isNotEmpty &&
              !_messages.last.isUser)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
              child: Row(
                mainAxisAlignment: .center,
                children: [
                  TextButton.icon(
                    onPressed: () => _regenerateOrSwipe(asNewSwipe: true),
                    icon: const Icon(Icons.auto_awesome),
                    label: const Text('Swipe'),
                  ),
                  TextButton.icon(
                    onPressed: () => _regenerateOrSwipe(asNewSwipe: false),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Regenerate'),
                  ),
                ],
              ),
            ),
          if (_error != null)
            Material(
              color: colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
                child: Row(
                  crossAxisAlignment: .start,
                  children: [
                    Icon(Icons.error_outline, color: colorScheme.onErrorContainer),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _error!,
                        style: TextStyle(color: colorScheme.onErrorContainer),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Dismiss',
                      onPressed: () => setState(() => _error = null),
                      icon: Icon(
                        Icons.close,
                        color: colorScheme.onErrorContainer,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                crossAxisAlignment: .end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _inputController,
                      enabled: !_busy,
                      minLines: 1,
                      maxLines: 5,
                      textInputAction: .newline,
                      decoration: InputDecoration(
                        hintText: 'Message $characterName…',
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      onSubmitted: (_) {
                        if (!_busy) _send();
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _busy ? null : _send,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.all(14),
                      minimumSize: const Size(48, 48),
                    ),
                    child: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showMessageMenu(int index) async {
    final message = _messages[index];
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: .min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit'),
              onTap: () => Navigator.pop(context, 'edit'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Delete'),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
            if (!message.isUser && index == _messages.length - 1) ...[
              ListTile(
                leading: const Icon(Icons.refresh),
                title: const Text('Regenerate'),
                onTap: () => Navigator.pop(context, 'regen'),
              ),
              ListTile(
                leading: const Icon(Icons.auto_awesome),
                title: const Text('New swipe'),
                onTap: () => Navigator.pop(context, 'swipe'),
              ),
            ],
          ],
        ),
      ),
    );

    if (action == 'edit') await _editMessage(index);
    if (action == 'delete') await _deleteMessage(index);
    if (action == 'regen') await _regenerateOrSwipe(asNewSwipe: false);
    if (action == 'swipe') await _regenerateOrSwipe(asNewSwipe: true);
  }
}

class _EmptyChat extends StatelessWidget {
  const _EmptyChat({
    required this.hasApiKey,
    required this.characterName,
    required this.onOpenSettings,
    required this.onOpenCharacters,
    required this.onNewChat,
  });

  final bool hasApiKey;
  final String characterName;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenCharacters;
  final VoidCallback onNewChat;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: .center,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 64,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'Chat with $characterName',
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: .center,
            ),
            const SizedBox(height: 8),
            Text(
              hasApiKey
                  ? 'This chat is saved on your phone. Add a first message on the character, or type below to begin.'
                  : 'First save your NanoGPT API key in Settings, then send a message.',
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: .center,
            ),
            const SizedBox(height: 20),
            if (!hasApiKey)
              FilledButton.icon(
                onPressed: onOpenSettings,
                icon: const Icon(Icons.key),
                label: const Text('Open Settings'),
              )
            else ...[
              OutlinedButton.icon(
                onPressed: onOpenCharacters,
                icon: const Icon(Icons.people_outline),
                label: const Text('Manage characters'),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: onNewChat,
                icon: const Icon(Icons.add_comment_outlined),
                label: const Text('Start new chat'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.showThinking,
    this.onLongPress,
  });

  final ChatMessage message;
  final bool showThinking;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isUser = message.isUser;
    final alignment = isUser ? Alignment.centerRight : Alignment.centerLeft;
    final background =
        isUser ? colorScheme.primaryContainer : colorScheme.surfaceContainerHighest;
    final foreground =
        isUser ? colorScheme.onPrimaryContainer : colorScheme.onSurface;

    return Align(
      alignment: alignment,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.82,
        ),
        child: InkWell(
          onLongPress: onLongPress,
          borderRadius: .circular(16),
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: background,
              borderRadius: .circular(16),
            ),
            child: showThinking
                ? Row(
                    mainAxisSize: .min,
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Thinking…',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  )
                : SelectableText(
                    message.text,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: foreground,
                        ),
                  ),
          ),
        ),
      ),
    );
  }
}
