import 'package:flutter/material.dart';

import '../models/chat_message.dart';
import '../models/global_lorebook.dart';
import '../models/world_workshop.dart';
import '../services/nanogpt_service.dart';
import '../services/settings_service.dart';
import '../services/world_info_service.dart';
import '../services/world_workshop_builder.dart';
import '../services/world_workshop_service.dart';
import '../widgets/keyboard_inset.dart';

/// Plain chat with the World Info collaborator; Create lorebook exports to global WI.
class WorldWorkshopChatScreen extends StatefulWidget {
  const WorldWorkshopChatScreen({
    super.key,
    required this.workshop,
    required this.workshopService,
    required this.worldInfoService,
    required this.settingsService,
    required this.nanoGptService,
  });

  final WorldWorkshop workshop;
  final WorldWorkshopService workshopService;
  final WorldInfoService worldInfoService;
  final SettingsService settingsService;
  final NanoGptService nanoGptService;

  @override
  State<WorldWorkshopChatScreen> createState() =>
      _WorldWorkshopChatScreenState();
}

class _WorldWorkshopChatScreenState extends State<WorldWorkshopChatScreen>
    with WidgetsBindingObserver {
  static const _builder = WorldWorkshopBuilder();

  final _input = TextEditingController();
  final _scroll = ScrollController();
  late WorldWorkshop _workshop;
  bool _sending = false;
  bool _exporting = false;
  double _keyboardInset = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _workshop = widget.workshop;
  }

  @override
  void didChangeMetrics() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final inset = MediaQuery.viewInsetsOf(context).bottom;
      if (inset > _keyboardInset + 8) {
        _scrollToEnd();
      }
      _keyboardInset = inset;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _persist(WorldWorkshop workshop) async {
    final saved = await widget.workshopService.upsert(workshop);
    if (!mounted) return;
    setState(() => _workshop = saved);
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending || _exporting) return;

    final userMessage = ChatMessage(
      id: ChatMessage.newId(),
      role: ChatRole.user,
      text: text,
    );
    final messages = [..._workshop.messages, userMessage];
    var title = _workshop.title;
    if (title == 'New workshop' || title.trim().isEmpty) {
      title = _builder.suggestTitle(messages);
    }

    _input.clear();
    setState(() {
      _sending = true;
      _workshop = _workshop.copyWith(messages: messages, title: title);
    });
    await _persist(_workshop);
    _scrollToEnd();

    final assistantId = ChatMessage.newId();
    final placeholder = ChatMessage(
      id: assistantId,
      role: ChatRole.assistant,
      text: '',
    );
    setState(() {
      _workshop = _workshop.copyWith(
        messages: [..._workshop.messages, placeholder],
      );
    });

    try {
      final collaborator =
          await widget.settingsService.getCollaboratorSettings();
      final model = await widget.settingsService.getModel();
      final sampling = await widget.settingsService.getSampling();
      final baseUrl = await widget.settingsService.getApiBaseUrl();

      final apiMessages = <Map<String, String>>[
        {
          'role': 'system',
          'content': _builder.chatSystemPrompt(
            guidanceNote: collaborator.guidanceNote,
          ),
        },
        for (final message in messages) message.toApiMap(),
      ];

      final buffer = StringBuffer();
      await for (final chunk in widget.nanoGptService.streamCompletion(
        model: model,
        messages: apiMessages,
        baseUrl: baseUrl,
        sampling: sampling,
      )) {
        if (!mounted) return;
        buffer.write(chunk);
        final updated = List<ChatMessage>.from(_workshop.messages);
        final index = updated.indexWhere((m) => m.id == assistantId);
        if (index < 0) continue;
        updated[index] = updated[index].withEditedText(buffer.toString());
        setState(() {
          _workshop = _workshop.copyWith(messages: updated);
        });
        _scrollToEnd();
      }

      await _persist(_workshop);
    } on NanoGptCancelledException {
      final updated = List<ChatMessage>.from(_workshop.messages);
      final index = updated.indexWhere((m) => m.id == assistantId);
      if (index >= 0) {
        final text = updated[index].text.trim();
        if (text.isEmpty) {
          updated.removeAt(index);
        }
        await _persist(_workshop.copyWith(messages: updated));
      }
    } on NanoGptException catch (error) {
      if (!mounted) return;
      _removeEmptyAssistant(assistantId);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } catch (error) {
      if (!mounted) return;
      _removeEmptyAssistant(assistantId);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Something went wrong: $error')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _removeEmptyAssistant(String assistantId) async {
    final updated = List<ChatMessage>.from(_workshop.messages);
    final index = updated.indexWhere((m) => m.id == assistantId);
    if (index < 0) return;
    if (updated[index].text.trim().isEmpty) {
      updated.removeAt(index);
      await _persist(_workshop.copyWith(messages: updated));
    }
  }

  void _stop() {
    widget.nanoGptService.cancelActiveStream();
  }

  Future<void> _createLorebook() async {
    if (_sending || _exporting) return;
    if (_workshop.messages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Chat a bit first, then create the lorebook.'),
        ),
      );
      return;
    }

    setState(() => _exporting = true);
    try {
      final collaborator =
          await widget.settingsService.getCollaboratorSettings();
      final model = await widget.settingsService.getModel();
      final sampling = await widget.settingsService.getSampling();
      final baseUrl = await widget.settingsService.getApiBaseUrl();

      final raw = await widget.nanoGptService.complete(
        model: model,
        messages: _builder.buildExportMessages(
          conversation: _workshop.messages,
          guidanceNote: collaborator.guidanceNote,
        ),
        baseUrl: baseUrl,
        sampling: sampling,
      );

      final book = _builder.parseLorebookJson(raw);
      final existingId = _workshop.exportedLorebookId;
      final global = GlobalLorebook(
        id: (existingId != null && existingId.isNotEmpty)
            ? existingId
            : GlobalLorebook.newId(),
        enabled: true,
        book: book,
      );
      await widget.worldInfoService.upsert(global);

      final title = book.name.trim().isEmpty ? _workshop.title : book.name.trim();
      await _persist(
        _workshop.copyWith(
          title: title,
          exportedLorebookId: global.id,
        ),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Saved “${global.displayName}” (${book.entries.length} entries) '
            'to World Info.',
          ),
        ),
      );
    } on FormatException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } on NanoGptException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not create lorebook: $error')),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final busy = _sending || _exporting;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: Text(_workshop.title),
        actions: [
          TextButton(
            onPressed: busy ? null : _createLorebook,
            child: _exporting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    _workshop.exportedLorebookId == null
                        ? 'Create lorebook'
                        : 'Update lorebook',
                  ),
          ),
        ],
      ),
      body: KeyboardInset(
        child: Column(
        children: [
          Material(
            color: theme.colorScheme.surfaceContainerHighest.withValues(
              alpha: 0.5,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Text(
                'Talk about your world. When you’re ready, tap '
                '${_workshop.exportedLorebookId == null ? 'Create' : 'Update'} '
                'lorebook to save keyword entries into World Info.',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ),
          Expanded(
            child: _workshop.messages.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Example: “I want a rainy coastal city with rival '
                        'guilds and a buried god under the harbor…”',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(16),
                    itemCount: _workshop.messages.length,
                    itemBuilder: (context, index) {
                      final message = _workshop.messages[index];
                      final isUser = message.isUser;
                      return Align(
                        alignment: isUser
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.sizeOf(context).width * 0.85,
                          ),
                          decoration: BoxDecoration(
                            color: isUser
                                ? theme.colorScheme.primaryContainer
                                : theme.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Text(
                            message.text.isEmpty && !isUser && _sending
                                ? '…'
                                : message.text,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                      );
                    },
                  ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      minLines: 1,
                      maxLines: 5,
                      textCapitalization: TextCapitalization.sentences,
                      enabled: !_exporting,
                      decoration: const InputDecoration(
                        hintText: 'Describe your world…',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onSubmitted: (_) {
                        if (_sending) {
                          _stop();
                        } else {
                          _send();
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _exporting
                        ? null
                        : (_sending ? _stop : _send),
                    icon: Icon(_sending ? Icons.stop : Icons.send),
                    tooltip: _sending ? 'Stop' : 'Send',
                  ),
                ],
              ),
            ),
          ),
        ],
        ),
      ),
    );
  }
}
