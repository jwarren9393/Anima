import 'package:flutter/material.dart';

import '../models/character.dart';
import '../models/chat_message.dart';
import '../services/api_key_service.dart';
import '../services/character_service.dart';
import '../services/nanogpt_service.dart';
import '../services/settings_service.dart';
import 'characters_screen.dart';
import 'settings_screen.dart';

/// Main chat screen: type a message, send it to NanoGPT, see the reply.
class ChatScreen extends StatefulWidget {
  const ChatScreen({
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
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  final _messages = <ChatMessage>[];

  bool _hasApiKey = false;
  bool _loading = true;
  bool _sending = false;
  String? _error;
  Character? _character;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final hasKey = await widget.apiKeyService.hasApiKey();
    final character = await _resolveSelectedCharacter();
    if (!mounted) return;
    setState(() {
      _hasApiKey = hasKey;
      _character = character;
      _loading = false;
    });
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

    // Switching characters starts a fresh in-memory chat (saved history is Phase 4).
    final switched = previousId != null && previousId != character.id;
    setState(() {
      _character = character;
      if (switched) {
        _messages.clear();
        _error = null;
      }
    });
  }

  Future<void> _send() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _sending) return;

    if (!_hasApiKey) {
      setState(() {
        _error =
            'Add your NanoGPT API key in Settings before you can chat.';
      });
      return;
    }

    final character = _character;
    if (character == null) {
      setState(() {
        _error = 'Pick a character first (people icon in the top bar).';
      });
      return;
    }

    FocusScope.of(context).unfocus();
    _inputController.clear();

    final priorForApi =
        _messages.map((message) => message.toApiMap()).toList(growable: false);

    setState(() {
      _error = null;
      _sending = true;
      _messages.add(ChatMessage(role: ChatRole.user, text: text));
    });
    _scrollToBottom();

    try {
      final model = await widget.settingsService.getModel();
      final reply = await widget.nanoGptService.sendChatMessage(
        userMessage: text,
        model: model,
        systemPrompt: character.systemPrompt,
        priorMessages: priorForApi,
      );
      if (!mounted) return;
      setState(() {
        _messages.add(ChatMessage(role: ChatRole.assistant, text: reply));
        _sending = false;
      });
      _scrollToBottom();
    } on NanoGptException catch (error) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = error.message;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = 'Something unexpected went wrong: $error';
      });
    }
  }

  void _clearChat() {
    setState(() {
      _messages.clear();
      _error = null;
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
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

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: .start,
          children: [
            const Text('Anima'),
            if (_character != null)
              Text(
                'Chatting with $characterName',
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Characters',
            icon: const Icon(Icons.people_outline),
            onPressed: _loading || _sending ? null : _openCharacters,
          ),
          if (_messages.isNotEmpty)
            IconButton(
              tooltip: 'Clear chat',
              icon: const Icon(Icons.delete_outline),
              onPressed: _sending ? null : _clearChat,
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
            child: _messages.isEmpty && !_sending
                ? _EmptyChat(
                    hasApiKey: _hasApiKey,
                    characterName: characterName,
                    onOpenSettings: _openSettings,
                    onOpenCharacters: _openCharacters,
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                    itemCount: _messages.length + (_sending ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (_sending && index == _messages.length) {
                        return const _TypingBubble();
                      }
                      return _MessageBubble(message: _messages[index]);
                    },
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
                      enabled: !_sending,
                      minLines: 1,
                      maxLines: 5,
                      textInputAction: .newline,
                      decoration: InputDecoration(
                        hintText: 'Message $characterName…',
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      onSubmitted: (_) {
                        if (!_sending) _send();
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _sending ? null : _send,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.all(14),
                      minimumSize: const Size(48, 48),
                    ),
                    child: _sending
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
}

class _EmptyChat extends StatelessWidget {
  const _EmptyChat({
    required this.hasApiKey,
    required this.characterName,
    required this.onOpenSettings,
    required this.onOpenCharacters,
  });

  final bool hasApiKey;
  final String characterName;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenCharacters;

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
                  ? 'Type a message below. Use the people icon to switch characters.'
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
            else
              OutlinedButton.icon(
                onPressed: onOpenCharacters,
                icon: const Icon(Icons.people_outline),
                label: const Text('Manage characters'),
              ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final ChatMessage message;

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
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: background,
            borderRadius: .circular(16),
          ),
          child: SelectableText(
            message.text,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: foreground,
                ),
          ),
        ),
      ),
    );
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: .centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: .circular(16),
        ),
        child: Row(
          mainAxisSize: .min,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'Thinking…',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
