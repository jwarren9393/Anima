import 'dart:async' show unawaited;
import 'dart:convert';

import 'package:flutter/material.dart';

import '../models/character.dart';
import '../models/chat_message.dart';
import '../models/chat_session.dart';
import '../models/global_lorebook.dart';
import '../models/lorebook.dart';
import '../models/persona.dart';
import '../models/world_workshop.dart';
import '../services/api_key_service.dart';
import '../services/appearance_controller.dart';
import '../services/character_category_service.dart';
import '../services/character_service.dart';
import '../services/chat_context_service.dart';
import '../services/chat_service.dart';
import '../services/nanogpt_service.dart';
import '../services/persona_service.dart';
import '../services/settings_service.dart';
import '../services/world_info_service.dart';
import '../services/world_workshop_builder.dart';
import '../services/opening_scene_service.dart';
import '../services/world_workshop_service.dart';
import '../utils/scroll_to_end.dart';
import '../widgets/chat_composer_field.dart';
import '../widgets/greeting_picker.dart';
import '../widgets/keyboard_inset.dart';
import '../widgets/narrator_bubble.dart';
import '../widgets/opening_scene_picker.dart';
import 'character_edit_screen.dart';
import 'characters_screen.dart';
import 'chat_screen.dart';
import 'group_chat_setup_screen.dart';
import 'persona_edit_screen.dart';

/// Plain chat with the World Info collaborator; export lorebook / characters.
class WorldWorkshopChatScreen extends StatefulWidget {
  const WorldWorkshopChatScreen({
    super.key,
    required this.workshop,
    required this.workshopService,
    required this.worldInfoService,
    required this.characterService,
    required this.characterCategoryService,
    required this.personaService,
    required this.chatService,
    required this.apiKeyService,
    required this.settingsService,
    required this.nanoGptService,
    required this.worldWorkshopService,
    required this.openingSceneService,
    required this.appearanceController,
  });

  final WorldWorkshop workshop;
  final WorldWorkshopService workshopService;
  final WorldInfoService worldInfoService;
  final CharacterService characterService;
  final CharacterCategoryService characterCategoryService;
  final PersonaService personaService;
  final ChatService chatService;
  final ApiKeyService apiKeyService;
  final SettingsService settingsService;
  final NanoGptService nanoGptService;
  final WorldWorkshopService worldWorkshopService;
  final OpeningSceneService openingSceneService;
  final AppearanceController appearanceController;

  @override
  State<WorldWorkshopChatScreen> createState() =>
      _WorldWorkshopChatScreenState();
}

class _WorldWorkshopChatScreenState extends State<WorldWorkshopChatScreen>
    with WidgetsBindingObserver {
  final _builder = WorldWorkshopBuilder();
  final _contextService = const ChatContextService();

  final _input = TextEditingController();
  final _openingSceneController = TextEditingController();
  final _composerFocus = FocusNode();
  final _scroll = ScrollController();
  late WorldWorkshop _workshop;
  GlobalLorebook? _linkedLorebook;
  bool _loadingLinkedLorebook = false;
  int? _modelContextLength;
  String _modelId = '';
  bool _sending = false;
  bool _exporting = false;
  String? _exportStatus;
  bool _enterToSend = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _workshop = widget.workshop;
    _openingSceneController.text = _workshop.openingScene;
    _loadLinkedLorebook();
    _loadModelContext();
    if (_workshop.messages.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        scrollListToEnd(_scroll, jump: true);
      });
    }
  }

  Future<void> _loadLinkedLorebook() async {
    final id = _workshop.exportedLorebookId;
    if (id == null || id.isEmpty) return;
    setState(() => _loadingLinkedLorebook = true);
    final linked = await widget.worldInfoService.getById(id);
    if (!mounted) return;
    setState(() {
      _linkedLorebook = linked;
      _loadingLinkedLorebook = false;
    });
  }

  Future<void> _loadModelContext() async {
    try {
      final modelId = await widget.settingsService.getModel();
      final enterToSend = await widget.settingsService.getEnterToSendComposer();
      final baseUrl = await widget.settingsService.getApiBaseUrl();
      final models = await widget.nanoGptService.listModels(baseUrl: baseUrl);
      if (!mounted) return;
      int? contextLength;
      for (final model in models) {
        if (model.id == modelId) {
          contextLength = model.contextLength;
          break;
        }
      }
      setState(() {
        _modelId = modelId;
        _modelContextLength = contextLength;
        _enterToSend = enterToSend;
      });
    } catch (_) {
      // Context length is optional UI polish.
    }
  }

  bool get _hasSourceMaterial =>
      _workshop.messages.isNotEmpty ||
      _linkedLorebook != null ||
      (_workshop.importedSource?.hasContent ?? false);

  /// Linked lorebook text for chat / character prompts (optional).
  Lorebook? get _lorebookForPrompt =>
      _workshop.includeLinkedLorebookInPrompt ? _linkedLorebook?.book : null;

  ContextEstimate get _estimate {
    final loreJson =
        _workshop.includeLinkedLorebookInPrompt && _linkedLorebook != null
        ? const JsonEncoder().convert(_linkedLorebook!.book.toJson())
        : '';
    final imported = _workshop.importedSource?.promptText ?? '';
    return _contextService.estimateWorkshop(
      messages: _workshop.messages,
      linkedLorebookJson: loreJson,
      importedSourceText: imported,
      modelContextLength: _modelContextLength,
    );
  }

  Future<void> _showContextEstimate() async {
    final estimate = _estimate;
    final ratio = estimate.fillRatio;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Context estimate'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Rough estimate only (≈ 1 token per 4 characters). '
                'Useful for spotting when a long workshop may start dropping early details.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              Text('Messages: ${estimate.messageCount}'),
              Text(
                'Chat transcript: ~${ContextEstimate.formatTokenCount(estimate.fullTranscriptTokens)} tokens',
              ),
              if (estimate.memoryTokens > 0)
                Text(
                  'Imported chat source: ~${ContextEstimate.formatTokenCount(estimate.memoryTokens)} tokens',
                ),
              if (estimate.loreTokens > 0)
                Text(
                  'Linked lorebook: ~${ContextEstimate.formatTokenCount(estimate.loreTokens)} tokens',
                )
              else if (_linkedLorebook != null &&
                  !_workshop.includeLinkedLorebookInPrompt) ...[
                Text(
                  'Linked lorebook: ~${ContextEstimate.formatTokenCount(_contextService.estimateTokens(const JsonEncoder().convert(_linkedLorebook!.book.toJson())))} tokens (not sent — ⋮ to include)',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              Text(
                'Estimated send size: ~${ContextEstimate.formatTokenCount(estimate.estimatedSentTokens)} tokens',
              ),
              if (_modelId.isNotEmpty) Text('Current model: $_modelId'),
              if (estimate.modelContextLength != null)
                Text(
                  'Model context: ${ContextEstimate.formatTokenCount(estimate.modelContextLength!)} tokens'
                  '${ratio == null ? '' : ' (~${(ratio * 100).round()}% used)'}',
                )
              else
                const Text(
                  'Model context: unknown (refresh models in API settings after picking a catalog model).',
                ),
              if (estimate.notes.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(estimate.notes),
              ],
              if (ratio != null && ratio >= 0.85) ...[
                const SizedBox(height: 12),
                Text(
                  'Getting full — consider Update lorebook soon so early details stay in World Info.',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  void didChangeMetrics() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (MediaQuery.viewInsetsOf(context).bottom > 24) {
        _scrollToEnd();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _composerFocus.dispose();
    _input.dispose();
    _openingSceneController.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _saveOpeningSceneField() async {
    final text = _openingSceneController.text.trim();
    if (text == _workshop.openingScene) return;
    final next = _workshop.copyWith(openingScene: text);
    await _persist(next);
    await widget.openingSceneService.syncFromWorkshop(
      workshopId: next.id,
      workshopTitle: next.title,
      openingScene: text,
    );
  }

  Future<void> _persist(WorldWorkshop workshop) async {
    final saved = await widget.workshopService.upsert(workshop);
    if (!mounted) return;
    setState(() => _workshop = saved);
  }

  bool get _busy => _sending || _exporting || _loadingLinkedLorebook;

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _busy) return;

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

    await _streamAssistantReply(assistantIndex: _workshop.messages.length - 1);
  }

  Future<void> _streamAssistantReply({required int assistantIndex}) async {
    if (assistantIndex < 0 || assistantIndex >= _workshop.messages.length) {
      return;
    }
    final assistantId = _workshop.messages[assistantIndex].id;

    try {
      final collaborator = await widget.settingsService
          .getCollaboratorSettings();
      final model = await widget.settingsService.getModel();
      final sampling = WorldWorkshopBuilder.workshopChatSampling(
        await widget.settingsService.getSampling(),
        replyLength: _workshop.replyLength,
      );
      final baseUrl = await widget.settingsService.getApiBaseUrl();

      final history = _workshop.messages.sublist(0, assistantIndex);
      final apiMessages = <Map<String, String>>[
        {
          'role': 'system',
          'content': _builder.chatSystemPrompt(
            guidanceNote: collaborator.guidanceNote,
            sourceLorebook: _lorebookForPrompt,
            importedSource: _workshop.importedSource,
            replyLength: _workshop.replyLength,
          ),
        },
        for (final message in history) message.toApiMap(),
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
      }

      await _persist(_workshop);
    } on NanoGptCancelledException {
      await _handleCancelledAssistant(assistantIndex);
    } on NanoGptException catch (error) {
      if (!mounted) return;
      await _handleFailedAssistant(assistantIndex);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (error) {
      if (!mounted) return;
      await _handleFailedAssistant(assistantIndex);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Something went wrong: $error')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _handleCancelledAssistant(int assistantIndex) async {
    if (!mounted) return;
    final updated = List<ChatMessage>.from(_workshop.messages);
    if (assistantIndex < 0 || assistantIndex >= updated.length) return;
    final message = updated[assistantIndex];
    if (message.text.trim().isNotEmpty) {
      await _persist(_workshop);
      return;
    }
    if (message.swipes.length > 1) {
      final previous = List<String>.from(message.swipes)..removeLast();
      updated[assistantIndex] = ChatMessage(
        id: message.id,
        role: message.role,
        text: previous.last,
        swipes: previous,
        swipeIndex: previous.length - 1,
      );
    } else {
      updated.removeAt(assistantIndex);
    }
    setState(() {
      _workshop = _workshop.copyWith(messages: updated);
    });
    await _persist(_workshop);
  }

  Future<void> _handleFailedAssistant(int assistantIndex) async {
    if (!mounted) return;
    final updated = List<ChatMessage>.from(_workshop.messages);
    if (assistantIndex < 0 || assistantIndex >= updated.length) return;
    final message = updated[assistantIndex];
    if (message.text.trim().isEmpty) {
      if (message.swipes.length > 1) {
        final previous = List<String>.from(message.swipes)..removeLast();
        updated[assistantIndex] = ChatMessage(
          id: message.id,
          role: message.role,
          text: previous.last,
          swipes: previous,
          swipeIndex: previous.length - 1,
        );
      } else {
        updated.removeAt(assistantIndex);
      }
      setState(() {
        _workshop = _workshop.copyWith(messages: updated);
      });
      await _persist(_workshop);
    }
  }

  ChatMessage _prepareAssistantForRegeneration(
    ChatMessage message, {
    required bool asNewSwipe,
  }) {
    if (asNewSwipe) {
      return ChatMessage(
        id: message.id,
        role: message.role,
        text: '',
        swipes: [...message.swipes, ''],
        swipeIndex: message.swipes.length,
      );
    }
    final swipes = List<String>.from(message.swipes);
    if (swipes.isEmpty) swipes.add('');
    final swipeIndex = message.swipeIndex.clamp(0, swipes.length - 1);
    swipes[swipeIndex] = '';
    return ChatMessage(
      id: message.id,
      role: message.role,
      text: '',
      swipes: swipes,
      swipeIndex: swipeIndex,
    );
  }

  Future<bool> _confirmRegenerateTruncating(int index) async {
    if (index >= _workshop.messages.length - 1) return true;
    final later = _workshop.messages.length - index - 1;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Regenerate reply?'),
        content: Text(
          'This removes $later later message${later == 1 ? '' : 's'} '
          'and generates a new reply here.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Regenerate'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<bool> _confirmRegenerateAfterUser(int index) async {
    if (index >= _workshop.messages.length - 1) return true;
    final later = _workshop.messages.length - index - 1;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Regenerate reply?'),
        content: Text(
          'This removes $later later message${later == 1 ? '' : 's'} '
          'and generates a new AI reply from your message.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Regenerate'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  /// Keep the user message at [index], drop everything after, stream a new reply.
  Future<void> _regenerateAfterUserMessage(
    int index, {
    bool confirmTruncate = true,
  }) async {
    if (_busy) return;
    if (index < 0 || index >= _workshop.messages.length) return;
    final message = _workshop.messages[index];
    if (!message.isUser) return;
    if (confirmTruncate && !await _confirmRegenerateAfterUser(index)) return;

    final messages = _workshop.messages.sublist(0, index + 1);
    messages.add(
      ChatMessage(
        id: ChatMessage.newId(),
        role: ChatRole.assistant,
        text: '',
      ),
    );

    setState(() {
      _sending = true;
      _workshop = _workshop.copyWith(messages: messages);
    });
    await _persist(_workshop);
    await _streamAssistantReply(assistantIndex: messages.length - 1);
  }

  Future<void> _regenerateMessage(
    int index, {
    required bool asNewSwipe,
  }) async {
    if (_busy) return;
    if (index < 0 || index >= _workshop.messages.length) return;
    final message = _workshop.messages[index];
    if (message.isUser) return;
    if (!await _confirmRegenerateTruncating(index)) return;

    var messages = _workshop.messages;
    if (index < messages.length - 1) {
      messages = messages.sublist(0, index + 1);
    }
    final prepared = _prepareAssistantForRegeneration(
      messages[index],
      asNewSwipe: asNewSwipe,
    );
    messages = List<ChatMessage>.from(messages)..[index] = prepared;

    setState(() {
      _sending = true;
      _workshop = _workshop.copyWith(messages: messages);
    });

    await _streamAssistantReply(assistantIndex: index);
  }

  Future<void> _editMessage(int index) async {
    if (_busy) return;
    if (index < 0 || index >= _workshop.messages.length) return;
    final message = _workshop.messages[index];
    final controller = TextEditingController(text: message.text);
    final result = await showDialog<_WorkshopEditResult>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(message.isUser ? 'Edit your message' : 'Edit reply'),
        content: TextField(
          controller: controller,
          minLines: 3,
          maxLines: 12,
          autofocus: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(
              context,
              _WorkshopEditResult(text: controller.text, regenerate: false),
            ),
            child: const Text('Save'),
          ),
          if (message.isUser)
            FilledButton(
              onPressed: () => Navigator.pop(
                context,
                _WorkshopEditResult(text: controller.text, regenerate: true),
              ),
              child: const Text('Save & regenerate'),
            )
          else
            FilledButton(
              onPressed: () => Navigator.pop(
                context,
                _WorkshopEditResult(text: controller.text, regenerate: false),
              ),
              child: const Text('Save'),
            ),
        ],
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
    if (result == null || !mounted) return;
    final trimmed = result.text.trim();
    if (trimmed.isEmpty) return;
    final updated = List<ChatMessage>.from(_workshop.messages);
    updated[index] = message.withEditedText(trimmed);
    setState(() => _workshop = _workshop.copyWith(messages: updated));
    await _persist(_workshop);
    if (result.regenerate && message.isUser) {
      await _regenerateAfterUserMessage(index, confirmTruncate: false);
    }
  }

  Future<void> _deleteMessage(int index) async {
    if (_busy) return;
    if (index < 0 || index >= _workshop.messages.length) return;
    final updated = List<ChatMessage>.from(_workshop.messages)..removeAt(index);
    setState(() => _workshop = _workshop.copyWith(messages: updated));
    await _persist(_workshop);
  }

  Future<void> _rewindToMessage(int index) async {
    if (_busy) return;
    if (index < 0 || index >= _workshop.messages.length) return;
    if (index >= _workshop.messages.length - 1) return;
    final messages = _workshop.messages.sublist(0, index + 1);
    setState(() => _workshop = _workshop.copyWith(messages: messages));
    await _persist(_workshop);
  }

  void _shiftSwipe(int index, int delta) {
    if (_busy) return;
    if (index < 0 || index >= _workshop.messages.length) return;
    final message = _workshop.messages[index];
    if (message.isUser || message.swipes.length < 2) return;
    final next = message.withSwipeIndex(message.swipeIndex + delta);
    if (next.swipeIndex == message.swipeIndex) return;
    final updated = List<ChatMessage>.from(_workshop.messages);
    updated[index] = next;
    setState(() => _workshop = _workshop.copyWith(messages: updated));
    unawaited(_persist(_workshop));
  }

  Future<void> _showMessageMenu(int index) async {
    if (_busy || index < 0 || index >= _workshop.messages.length) return;
    final message = _workshop.messages[index];
    final canRewind = index < _workshop.messages.length - 1;
    final isLast = index == _workshop.messages.length - 1;
    final canSwipeNav = !message.isUser && message.swipes.length > 1;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit'),
              onTap: () => Navigator.pop(context, 'edit'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Delete'),
              subtitle: const Text('Remove only this message'),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
            ListTile(
              leading: const Icon(Icons.undo),
              title: const Text('Rewind to here'),
              subtitle: Text(
                canRewind
                    ? 'Delete every message after this one'
                    : 'Already the last message',
              ),
              enabled: canRewind,
              onTap: canRewind
                  ? () => Navigator.pop(context, 'rewind')
                  : null,
            ),
            if (message.isUser) ...[
              const Divider(),
              ListTile(
                leading: const Icon(Icons.play_arrow),
                title: const Text('Regenerate reply'),
                subtitle: Text(
                  isLast
                      ? 'Generate an AI reply to this message'
                      : 'Remove later messages, then generate a new reply',
                ),
                onTap: () => Navigator.pop(context, 'regen_reply'),
              ),
            ],
            if (!message.isUser) ...[
              const Divider(),
              ListTile(
                leading: const Icon(Icons.refresh),
                title: const Text('Regenerate'),
                subtitle: Text(
                  isLast
                      ? 'Generate this reply again'
                      : 'Removes later messages, then regenerates',
                ),
                onTap: () => Navigator.pop(context, 'regen'),
              ),
              ListTile(
                leading: const Icon(Icons.auto_awesome),
                title: const Text('New swipe'),
                subtitle: const Text('Keep this version and generate another'),
                onTap: () => Navigator.pop(context, 'swipe'),
              ),
            ],
            if (canSwipeNav) ...[
              ListTile(
                leading: const Icon(Icons.chevron_left),
                title: const Text('Previous swipe'),
                subtitle: Text(
                  'Swipe ${message.swipeIndex + 1}/${message.swipes.length}',
                ),
                enabled: message.swipeIndex > 0,
                onTap: message.swipeIndex > 0
                    ? () => Navigator.pop(context, 'swipe_prev')
                    : null,
              ),
              ListTile(
                leading: const Icon(Icons.chevron_right),
                title: const Text('Next swipe'),
                enabled: message.swipeIndex < message.swipes.length - 1,
                onTap: message.swipeIndex < message.swipes.length - 1
                    ? () => Navigator.pop(context, 'swipe_next')
                    : null,
              ),
            ],
          ],
        ),
      ),
    );

    if (action == 'edit') await _editMessage(index);
    if (action == 'delete') await _deleteMessage(index);
    if (action == 'rewind') await _rewindToMessage(index);
    if (action == 'regen_reply') await _regenerateAfterUserMessage(index);
    if (action == 'regen') {
      await _regenerateMessage(index, asNewSwipe: false);
    }
    if (action == 'swipe') {
      await _regenerateMessage(index, asNewSwipe: true);
    }
    if (action == 'swipe_prev') _shiftSwipe(index, -1);
    if (action == 'swipe_next') _shiftSwipe(index, 1);
  }

  Future<void> _toggleLinkedLorebookInPrompt() async {
    final next = !_workshop.includeLinkedLorebookInPrompt;
    setState(
      () => _workshop = _workshop.copyWith(
        includeLinkedLorebookInPrompt: next,
      ),
    );
    await _persist(_workshop);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          next
              ? 'Linked lorebook will be sent with chat and character exports.'
              : 'Linked lorebook hidden from prompts — using workshop chat only.',
        ),
      ),
    );
  }

  Future<void> _setReplyLength(WorkshopReplyLength length) async {
    if (_workshop.replyLength == length) return;
    setState(() => _workshop = _workshop.copyWith(replyLength: length));
    await _persist(_workshop);
  }

  Widget _replyLengthPicker(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<WorkshopReplyLength>(
            segments: [
              for (final mode in WorkshopReplyLength.values)
                ButtonSegment<WorkshopReplyLength>(
                  value: mode,
                  label: Text(mode.label),
                  tooltip: mode.subtitle,
                ),
            ],
            selected: {_workshop.replyLength},
            onSelectionChanged: _busy
                ? null
                : (selected) {
                    if (selected.isEmpty) return;
                    unawaited(_setReplyLength(selected.first));
                  },
            showSelectedIcon: false,
            style: ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _workshop.replyLength.subtitle,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  void _stop() {
    widget.nanoGptService.cancelActiveStream();
  }

  Future<void> _createLorebook() async {
    if (_sending || _exporting || _loadingLinkedLorebook) return;
    if (_workshop.exportedLorebookId != null && _linkedLorebook == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'The linked World Info lorebook is missing. Import or link it again.',
          ),
        ),
      );
      return;
    }
    if (!_hasSourceMaterial) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Chat a bit first (or import a roleplay chat), then create the lorebook.',
          ),
        ),
      );
      return;
    }

    setState(() {
      _exporting = true;
      _exportStatus = 'Creating lorebook…';
    });
    try {
      final collaborator = await widget.settingsService
          .getCollaboratorSettings();
      final model = await widget.settingsService.getModel();
      final sampling = WorldWorkshopBuilder.workshopExportSampling(
        await widget.settingsService.getSampling(),
      );
      final baseUrl = await widget.settingsService.getApiBaseUrl();

      final exportMessages = _builder.buildExportMessages(
        conversation: _workshop.messages,
        guidanceNote: collaborator.guidanceNote,
        sourceLorebook: _linkedLorebook?.book,
        importedSource: _workshop.importedSource,
      );

      var raw = await widget.nanoGptService.complete(
        model: model,
        messages: exportMessages,
        baseUrl: baseUrl,
        sampling: sampling,
      );

      Lorebook book;
      try {
        book = _builder.parseLorebookJson(raw);
      } on FormatException {
        raw = await widget.nanoGptService.complete(
          model: model,
          messages: [
            ...exportMessages,
            {'role': 'assistant', 'content': raw},
            {
              'role': 'user',
              'content': WorldWorkshopBuilder.lorebookExportRetryUserMessage,
            },
          ],
          baseUrl: baseUrl,
          sampling: sampling,
        );
        book = _builder.parseLorebookJson(raw);
      }
      final existingId = _workshop.exportedLorebookId;
      final global = GlobalLorebook(
        id: (existingId != null && existingId.isNotEmpty)
            ? existingId
            : GlobalLorebook.newId(),
        enabled: _linkedLorebook?.enabled ?? true,
        book: book,
      );
      await widget.worldInfoService.upsert(global);
      if (mounted) {
        setState(() => _linkedLorebook = global);
      }

      final title = book.name.trim().isEmpty
          ? _workshop.title
          : book.name.trim();
      await _persist(
        _workshop.copyWith(
          title: title,
          exportedLorebookId: global.id,
          includeLinkedLorebookInPrompt: false,
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } on NanoGptException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not create lorebook: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _exporting = false;
          _exportStatus = null;
        });
      }
    }
  }

  Future<void> _createOpeningScene() async {
    if (_sending || _exporting || _loadingLinkedLorebook) return;
    if (!_hasSourceMaterial) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Chat a bit first (or import a roleplay chat), then create the opening scene.',
          ),
        ),
      );
      return;
    }

    setState(() {
      _exporting = true;
      _exportStatus = 'Creating opening scene…';
    });
    try {
      final collaborator = await widget.settingsService
          .getCollaboratorSettings();
      final model = await widget.settingsService.getModel();
      final sampling = WorldWorkshopBuilder.workshopExportSampling(
        await widget.settingsService.getSampling(),
      );
      final baseUrl = await widget.settingsService.getApiBaseUrl();

      final raw = await widget.nanoGptService.complete(
        model: model,
        messages: _builder.buildOpeningSceneExportMessages(
          conversation: _workshop.messages,
          guidanceNote: collaborator.guidanceNote,
          sourceLorebook: _lorebookForPrompt,
          importedSource: _workshop.importedSource,
          existingOpeningScene: _workshop.openingScene,
        ),
        baseUrl: baseUrl,
        sampling: sampling,
      );

      final scene = _builder.parseOpeningSceneJson(raw);
      _openingSceneController.text = scene;
      final next = _workshop.copyWith(openingScene: scene);
      await _persist(next);
      await widget.openingSceneService.syncFromWorkshop(
        workshopId: next.id,
        workshopTitle: next.title,
        openingScene: scene,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Opening scene saved to this workshop.')),
      );
    } on FormatException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } on NanoGptException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not create opening scene: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _exporting = false;
          _exportStatus = null;
        });
      }
    }
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
          openingSceneService: widget.openingSceneService,
          appearanceController: widget.appearanceController,
          initialSession: session,
        ),
      ),
    );
  }

  Future<void> _startRoleplay() async {
    if (_sending || _exporting || _loadingLinkedLorebook) return;
    await _saveOpeningSceneField();
    if (!mounted) return;

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
              subtitle: const Text('One character with this opening scene'),
              onTap: () => Navigator.pop(context, 'solo'),
            ),
            ListTile(
              leading: const Icon(Icons.groups_outlined),
              title: const Text('Group chat'),
              subtitle: const Text('Several characters + opening scene'),
              onTap: () => Navigator.pop(context, 'group'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;

    if (choice == 'group') {
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
            openingSceneService: widget.openingSceneService,
            worldWorkshopService: widget.worldWorkshopService,
            initialOpeningScene: _workshop.openingScene,
          ),
        ),
      );
      if (session == null || !mounted) return;
      await _openChat(session);
      return;
    }

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

    await widget.openingSceneService.importMissingFromWorkshops(
      await widget.worldWorkshopService.loadWorkshops(),
    );
    if (!mounted) return;
    final savedScenes = await widget.openingSceneService.loadScenes();
    if (!mounted) return;

    final openingPick = await pickOpeningScene(
      context,
      initial: _workshop.openingScene,
      subtitle:
          'Prefilled from this workshop. Edit, skip, or use as-is for the new chat.',
      savedScenes: savedScenes,
      openingSceneService: widget.openingSceneService,
      workshopService: widget.worldWorkshopService,
    );
    if (openingPick == null || !mounted) return;

    final session = await widget.chatService.startNewChat(
      character,
      userName: persona.name,
      personaId: persona.id,
      greetingIndex: greetingIndex,
      openingScene: openingPick.text,
    );
    if (!mounted) return;
    await _openChat(session);
  }

  Future<void> _createCharacters() async {
    if (_sending || _exporting || _loadingLinkedLorebook) return;
    if (_workshop.exportedLorebookId != null && _linkedLorebook == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'The linked World Info lorebook is missing. Import or link it again.',
          ),
        ),
      );
      return;
    }
    if (!_hasSourceMaterial) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Chat a bit first, then create characters.'),
        ),
      );
      return;
    }

    setState(() {
      _exporting = true;
      _exportStatus = 'Finding characters…';
    });

    try {
      final collaborator = await widget.settingsService
          .getCollaboratorSettings();
      final model = await widget.settingsService.getModel();
      final sampling = WorldWorkshopBuilder.workshopExportSampling(
        await widget.settingsService.getSampling(),
      );
      final baseUrl = await widget.settingsService.getApiBaseUrl();
      final existingChars = await widget.characterService.loadCharacters();
      final existingNames = {
        for (final c in existingChars) c.name.trim().toLowerCase(),
      };

      var detectRaw = await widget.nanoGptService.complete(
        model: model,
        messages: _builder.buildCharacterDetectMessages(
          conversation: _workshop.messages,
          guidanceNote: collaborator.guidanceNote,
          sourceLorebook: _lorebookForPrompt,
          importedSource: _workshop.importedSource,
        ),
        baseUrl: baseUrl,
        sampling: sampling,
      );

      List<WorkshopCharacterCandidate> candidates;
      try {
        candidates = _builder.parseCharacterCandidatesJson(detectRaw);
      } on FormatException {
        detectRaw = await widget.nanoGptService.complete(
          model: model,
          messages: [
            ..._builder.buildCharacterDetectMessages(
              conversation: _workshop.messages,
              guidanceNote: collaborator.guidanceNote,
              sourceLorebook: _lorebookForPrompt,
              importedSource: _workshop.importedSource,
            ),
            {'role': 'assistant', 'content': detectRaw},
            {
              'role': 'user',
              'content':
                  WorldWorkshopBuilder.characterDetectExportRetryUserMessage,
            },
          ],
          baseUrl: baseUrl,
          sampling: sampling,
        );
        candidates = _builder.parseCharacterCandidatesJson(detectRaw);
      }
      if (!mounted) return;

      if (candidates.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No clear characters found yet. Chat more about people, then try again.',
            ),
          ),
        );
        return;
      }

      setState(() {
        _exporting = false;
        _exportStatus = null;
      });

      final selected = await _pickCandidates(
        candidates: candidates,
        existingNames: existingNames,
      );
      if (!mounted || selected == null || selected.isEmpty) return;

      setState(() {
        _exporting = true;
        _exportStatus = 'Generating characters…';
      });

      var savedCount = 0;
      var skippedCount = 0;
      final build = await widget.settingsService.resolveCharacterBuild();

      for (var i = 0; i < selected.length; i++) {
        if (!mounted) return;
        final candidate = selected[i];
        setState(() {
          _exportStatus =
              'Generating ${i + 1} of ${selected.length}: ${candidate.name}…';
        });

        try {
          final cardRaw = await widget.nanoGptService.complete(
            model: build.model,
            messages: _builder.buildCharacterExportMessages(
              conversation: _workshop.messages,
              characterName: candidate.name,
              characterSummary: candidate.summary,
              buildPromptNote: build.promptNote,
              sourceLorebook: _lorebookForPrompt,
              importedSource: _workshop.importedSource,
            ),
            baseUrl: baseUrl,
            sampling: WorldWorkshopBuilder.workshopExportSampling(build.sampling),
          );

          final draft = _builder.parseCharacterJson(
            cardRaw,
            preferredId: widget.characterService.newId(),
            fallbackName: candidate.name,
          );

          if (!mounted) return;
          setState(() {
            _exporting = false;
            _exportStatus = null;
          });

          final saved = await Navigator.of(context).push<Character>(
            MaterialPageRoute(
              builder: (_) => CharacterEditScreen(
                characterService: widget.characterService,
                settingsService: widget.settingsService,
                nanoGptService: widget.nanoGptService,
                existing: draft,
                generatedDraft: true,
              ),
            ),
          );

          if (saved != null) {
            savedCount++;
          } else {
            skippedCount++;
          }
        } on FormatException catch (error) {
          if (!mounted) return;
          skippedCount++;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${candidate.name}: ${error.message}'),
              backgroundColor: Theme.of(
                context,
              ).colorScheme.surfaceContainerHigh,
            ),
          );
        } on NanoGptException catch (error) {
          if (!mounted) return;
          skippedCount++;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${candidate.name}: ${error.message}'),
              backgroundColor: Theme.of(
                context,
              ).colorScheme.surfaceContainerHigh,
            ),
          );
        }

        if (!mounted) return;
        // Resume busy state between cards when more remain.
        if (i < selected.length - 1) {
          setState(() {
            _exporting = true;
            _exportStatus = 'Generating ${i + 2} of ${selected.length}…';
          });
        }
      }

      if (!mounted) return;
      final parts = <String>[];
      if (savedCount > 0) {
        parts.add('Saved $savedCount character${savedCount == 1 ? '' : 's'}');
      }
      if (skippedCount > 0) {
        parts.add('skipped $skippedCount');
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            parts.isEmpty ? 'No characters saved.' : parts.join(' · '),
          ),
        ),
      );
    } on FormatException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } on NanoGptException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not create characters: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _exporting = false;
          _exportStatus = null;
        });
      }
    }
  }

  Future<void> _updateExistingCharacter() async {
    if (_sending || _exporting || _loadingLinkedLorebook) return;
    if (_workshop.exportedLorebookId != null && _linkedLorebook == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'The linked World Info lorebook is missing. Import or link it again.',
          ),
        ),
      );
      return;
    }
    if (!_hasSourceMaterial) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Chat a bit first (or import a roleplay chat), then update a character.',
          ),
        ),
      );
      return;
    }

    setState(() {
      _exporting = true;
      _exportStatus = 'Loading characters…';
    });

    try {
      final existingChars = await widget.characterService.loadCharacters();
      if (!mounted) return;
      if (existingChars.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No saved characters yet. Create one first, then update it here.',
            ),
          ),
        );
        return;
      }

      final ordered = _builder.prioritizeCharactersForUpdate(
        characters: existingChars,
        importedSource: _workshop.importedSource,
      );

      setState(() {
        _exporting = false;
        _exportStatus = null;
      });

      final selected = await _pickExistingCharacter(ordered);
      if (!mounted || selected == null) return;

      setState(() {
        _exporting = true;
        _exportStatus = 'Updating ${selected.name}…';
      });

      final build = await widget.settingsService.resolveCharacterBuild();
      final baseUrl = await widget.settingsService.getApiBaseUrl();

      final cardRaw = await widget.nanoGptService.complete(
        model: build.model,
        messages: _builder.buildCharacterUpdateMessages(
          conversation: _workshop.messages,
          existing: selected,
          buildPromptNote: build.promptNote,
          sourceLorebook: _lorebookForPrompt,
          importedSource: _workshop.importedSource,
        ),
        baseUrl: baseUrl,
        sampling: WorldWorkshopBuilder.workshopExportSampling(build.sampling),
      );

      final draft = _builder.parseCharacterUpdateJson(
        cardRaw,
        original: selected,
      );

      if (!mounted) return;
      setState(() {
        _exporting = false;
        _exportStatus = null;
      });

      final saved = await Navigator.of(context).push<Character>(
        MaterialPageRoute(
          builder: (_) => CharacterEditScreen(
            characterService: widget.characterService,
            settingsService: widget.settingsService,
            nanoGptService: widget.nanoGptService,
            existing: draft,
            generatedDraft: true,
            updatingExisting: true,
          ),
        ),
      );

      if (!mounted) return;
      if (saved != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Updated “${saved.name}”.')),
        );
      }
    } on FormatException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } on NanoGptException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update character: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _exporting = false;
          _exportStatus = null;
        });
      }
    }
  }

  Future<Character?> _pickExistingCharacter(List<Character> characters) async {
    return showModalBottomSheet<Character>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        final theme = Theme.of(context);
        final maxHeight = MediaQuery.sizeOf(context).height * 0.7;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                  child: Text(
                    'Update existing character',
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: Text(
                    'Choose a saved card to revise from this workshop. '
                    'You’ll review the merge before it overwrites the original.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: characters.length,
                    itemBuilder: (context, index) {
                      final character = characters[index];
                      final fromImport = _builder.isImportedChatCharacter(
                        character,
                        _workshop.importedSource,
                      );
                      return ListTile(
                        leading: const Icon(Icons.person_outline),
                        title: Text(character.name),
                        subtitle: Text(
                          [
                            if (character.description.trim().isNotEmpty)
                              character.description.trim(),
                            if (fromImport) 'In imported chat',
                          ].join('\n'),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => Navigator.pop(context, character),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _createPersona() async {
    if (_sending || _exporting || _loadingLinkedLorebook) return;
    if (_workshop.exportedLorebookId != null && _linkedLorebook == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'The linked World Info lorebook is missing. Import or link it again.',
          ),
        ),
      );
      return;
    }
    if (!_hasSourceMaterial) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Chat a bit first, then create a persona.'),
        ),
      );
      return;
    }

    setState(() {
      _exporting = true;
      _exportStatus = 'Finding persona candidates…';
    });

    try {
      final collaborator = await widget.settingsService
          .getCollaboratorSettings();
      final model = await widget.settingsService.getModel();
      final sampling = WorldWorkshopBuilder.workshopExportSampling(
        await widget.settingsService.getSampling(),
      );
      final baseUrl = await widget.settingsService.getApiBaseUrl();
      final existingPersonas = await widget.personaService.loadPersonas();
      final existingNames = {
        for (final p in existingPersonas) p.name.trim().toLowerCase(),
      };

      var detectRaw = await widget.nanoGptService.complete(
        model: model,
        messages: _builder.buildCharacterDetectMessages(
          conversation: _workshop.messages,
          guidanceNote: collaborator.guidanceNote,
          sourceLorebook: _lorebookForPrompt,
          importedSource: _workshop.importedSource,
        ),
        baseUrl: baseUrl,
        sampling: sampling,
      );
      List<WorkshopCharacterCandidate> candidates;
      try {
        candidates = _builder.parseCharacterCandidatesJson(detectRaw);
      } on FormatException {
        detectRaw = await widget.nanoGptService.complete(
          model: model,
          messages: [
            ..._builder.buildCharacterDetectMessages(
              conversation: _workshop.messages,
              guidanceNote: collaborator.guidanceNote,
              sourceLorebook: _lorebookForPrompt,
              importedSource: _workshop.importedSource,
            ),
            {'role': 'assistant', 'content': detectRaw},
            {
              'role': 'user',
              'content':
                  WorldWorkshopBuilder.characterDetectExportRetryUserMessage,
            },
          ],
          baseUrl: baseUrl,
          sampling: sampling,
        );
        candidates = _builder.parseCharacterCandidatesJson(detectRaw);
      }
      if (!mounted) return;
      if (candidates.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No clear people found yet. Add more about your player character, then try again.',
            ),
          ),
        );
        return;
      }

      setState(() {
        _exporting = false;
        _exportStatus = null;
      });
      final selected = await _pickPersonaCandidate(
        candidates: candidates,
        existingNames: existingNames,
      );
      if (!mounted || selected == null) return;

      setState(() {
        _exporting = true;
        _exportStatus = 'Generating persona: ${selected.name}…';
      });
      final personaRaw = await widget.nanoGptService.complete(
        model: model,
        messages: _builder.buildPersonaExportMessages(
          conversation: _workshop.messages,
          personaName: selected.name,
          personaSummary: selected.summary,
          guidanceNote: collaborator.guidanceNote,
          sourceLorebook: _lorebookForPrompt,
          importedSource: _workshop.importedSource,
        ),
        baseUrl: baseUrl,
        sampling: sampling,
      );
      final draft = _builder.parsePersonaJson(
        personaRaw,
        preferredId: widget.personaService.newId(),
        fallbackName: selected.name,
      );
      if (!mounted) return;
      setState(() {
        _exporting = false;
        _exportStatus = null;
      });

      final saved = await Navigator.of(context).push<Persona>(
        MaterialPageRoute(
          builder: (_) => PersonaEditScreen(
            personaService: widget.personaService,
            settingsService: widget.settingsService,
            nanoGptService: widget.nanoGptService,
            existing: draft,
            generatedDraft: true,
          ),
        ),
      );
      if (!mounted || saved == null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved ${saved.name} to Personas.')),
      );
    } on FormatException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } on NanoGptException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not create persona: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _exporting = false;
          _exportStatus = null;
        });
      }
    }
  }

  Future<WorkshopCharacterCandidate?> _pickPersonaCandidate({
    required List<WorkshopCharacterCandidate> candidates,
    required Set<String> existingNames,
  }) async {
    WorkshopCharacterCandidate? selected = candidates.length == 1
        ? candidates.first
        : null;
    return showModalBottomSheet<WorkshopCharacterCandidate>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final theme = Theme.of(context);
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Create your persona',
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Choose the person you will play. Anima will generate '
                      'player-focused fields, then let you review everything '
                      'before saving.',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.sizeOf(context).height * 0.5,
                      ),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: candidates.length,
                        itemBuilder: (context, index) {
                          final candidate = candidates[index];
                          final exists = existingNames.contains(
                            candidate.name.trim().toLowerCase(),
                          );
                          final isSelected = identical(selected, candidate);
                          return ListTile(
                            leading: Icon(
                              isSelected
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_off,
                              color: isSelected
                                  ? Theme.of(context).colorScheme.primary
                                  : null,
                            ),
                            title: Text(candidate.name),
                            subtitle: Text(
                              [
                                if (candidate.summary.isNotEmpty)
                                  candidate.summary,
                                if (exists)
                                  'A persona with this name already exists; saving creates another.',
                              ].join('\n'),
                            ),
                            selected: isSelected,
                            onTap: () {
                              setSheetState(() => selected = candidate);
                            },
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancel'),
                        ),
                        const Spacer(),
                        FilledButton(
                          onPressed: selected == null
                              ? null
                              : () => Navigator.pop(context, selected),
                          child: const Text('Generate persona'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<List<WorkshopCharacterCandidate>?> _pickCandidates({
    required List<WorkshopCharacterCandidate> candidates,
    required Set<String> existingNames,
  }) async {
    final selected = <String>{
      for (final c in candidates)
        if (!existingNames.contains(c.name.trim().toLowerCase()))
          c.name.trim().toLowerCase(),
    };
    // If everything already exists, still preselect all so the user can
    // intentionally create another version.
    if (selected.isEmpty) {
      selected.addAll(candidates.map((c) => c.name.trim().toLowerCase()));
    }

    return showModalBottomSheet<List<WorkshopCharacterCandidate>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final theme = Theme.of(context);
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 8,
                  bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Create characters',
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Choose who to turn into playable character cards. '
                      'You’ll review each card before it’s saved.',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.sizeOf(context).height * 0.5,
                      ),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: candidates.length,
                        itemBuilder: (context, index) {
                          final candidate = candidates[index];
                          final key = candidate.name.trim().toLowerCase();
                          final exists = existingNames.contains(key);
                          final checked = selected.contains(key);
                          return CheckboxListTile(
                            value: checked,
                            onChanged: (value) {
                              setSheetState(() {
                                if (value == true) {
                                  selected.add(key);
                                } else {
                                  selected.remove(key);
                                }
                              });
                            },
                            title: Text(candidate.name),
                            subtitle: Text(
                              [
                                if (candidate.summary.isNotEmpty)
                                  candidate.summary,
                                if (exists)
                                  'Already in Characters (new card won’t overwrite)',
                              ].join('\n'),
                            ),
                            controlAffinity: ListTileControlAffinity.leading,
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancel'),
                        ),
                        const Spacer(),
                        FilledButton(
                          onPressed: selected.isEmpty
                              ? null
                              : () {
                                  final chosen = candidates
                                      .where(
                                        (c) => selected.contains(
                                          c.name.trim().toLowerCase(),
                                        ),
                                      )
                                      .toList();
                                  Navigator.pop(context, chosen);
                                },
                          child: Text('Generate (${selected.length})'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _scrollToEnd() {
    scrollListToEnd(_scroll);
  }

  Future<void> _showImportedSourceDetails() async {
    final source = _workshop.importedSource;
    if (source == null) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Imported: ${source.chatTitle}'),
        content: SingleChildScrollView(
          child: SelectableText(
            source.promptText,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _openingSceneCompactBar(ThemeData theme) {
    final scene = _workshop.openingScene.trim();
    final hasScene = scene.isNotEmpty;
    final preview = hasScene
        ? scene.replaceAll(RegExp(r'\s+'), ' ')
        : 'Tap to add narrator setup for new chats';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Material(
        color: theme.colorScheme.tertiaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: _showOpeningSceneEditor,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(
                  Icons.auto_stories_outlined,
                  size: 20,
                  color: theme.colorScheme.onTertiaryContainer,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Opening scene',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: theme.colorScheme.onTertiaryContainer,
                        ),
                      ),
                      Text(
                        preview,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onTertiaryContainer,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: theme.colorScheme.onTertiaryContainer,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showOpeningSceneEditor() async {
    if (_exporting) return;
    _openingSceneController.text = _workshop.openingScene;
    final theme = Theme.of(context);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
          ),
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Opening scene',
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Narrator setup for roleplay chats — separate from lore entries '
                    'and character greetings. Saved scenes sync to Settings → '
                    'Opening scenes.',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  if (_workshop.openingScene.trim().isNotEmpty) ...[
                    NarratorBubble(
                      text: _workshop.openingScene,
                      onTap: null,
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextField(
                    controller: _openingSceneController,
                    minLines: 4,
                    maxLines: 10,
                    enabled: !_exporting,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      hintText:
                          'Rain on cobblestones. The city holds its breath…',
                      border: OutlineInputBorder(),
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: (_sending || _exporting || _loadingLinkedLorebook)
                        ? null
                        : () async {
                            await _createOpeningScene();
                            if (sheetContext.mounted) {
                              Navigator.pop(sheetContext);
                            }
                          },
                    icon: const Icon(Icons.auto_awesome),
                    label: Text(
                      _workshop.openingScene.trim().isEmpty
                          ? 'Generate from chat'
                          : 'Regenerate from chat',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => Navigator.pop(sheetContext),
                    child: const Text('Done'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    await _saveOpeningSceneField();
  }

  Widget _statusBanner(ThemeData theme, {required bool compact}) {
    final linkedName = _linkedLorebook?.displayName;
    final imported = _workshop.importedSource;
    final hasImported = imported?.hasContent ?? false;
    return Material(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      child: InkWell(
        onTap: _showContextEstimate,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: compact
              ? Text(
                  _exportStatus ?? _estimate.compactBannerLine,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: (_estimate.fillRatio ?? 0) >= 0.85
                        ? theme.colorScheme.error
                        : theme.colorScheme.tertiary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _exportStatus ??
                          (linkedName != null
                              ? 'Linked to “$linkedName” '
                                  '(${_linkedLorebook!.entryCount} entries). '
                                  '${_workshop.includeLinkedLorebookInPrompt ? 'Lorebook included in prompts.' : 'Chat uses the workshop transcript only — ⋮ to include lorebook.'} '
                                  'Update lorebook or create characters via ⋮.'
                              : hasImported
                                  ? 'Seeded from “${imported!.chatTitle}”. '
                                      'Chat to refine, then use ⋮ for lorebook, opening scene, or characters.'
                                  : 'Talk about your world. Use ⋮ for lorebook, opening scene, or characters.'),
                      style: theme.textTheme.bodySmall,
                    ),
                    if (_exportStatus == null) ...[
                      const SizedBox(height: 6),
                      Text(
                        _estimate.compactBannerLine,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: (_estimate.fillRatio ?? 0) >= 0.85
                              ? theme.colorScheme.error
                              : theme.colorScheme.tertiary,
                        ),
                      ),
                    ],
                  ],
                ),
        ),
      ),
    );
  }

  Widget _importedSourceCard(ThemeData theme) {
    final source = _workshop.importedSource;
    if (source == null || !source.hasContent) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Material(
        color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: _showImportedSourceDetails,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(
                  Icons.forum_outlined,
                  color: theme.colorScheme.onSecondaryContainer,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Imported from chat',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: theme.colorScheme.onSecondaryContainer,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${source.chatTitle} · ${source.compactSummary}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSecondaryContainer,
                        ),
                      ),
                      if (source.importProfile.trim().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          source.importProfile.trim(),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSecondaryContainer,
                          ),
                        ),
                      ],
                      if (source.skippedNotes.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          '${source.skippedNotes.length} missing reference'
                          '${source.skippedNotes.length == 1 ? '' : 's'} skipped',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: theme.colorScheme.onSecondaryContainer,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final busy = _sending || _exporting || _loadingLinkedLorebook;
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 24;
    final linkedName = _linkedLorebook?.displayName;
    final imported = _workshop.importedSource;
    final hasImported = imported?.hasContent ?? false;
    final lorebookLabel = _workshop.exportedLorebookId == null
        ? 'Create lorebook'
        : 'Update lorebook';
    final openingLabel = _workshop.openingScene.trim().isEmpty
        ? 'Opening scene'
        : 'Edit opening scene';

    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: Text(
          _workshop.title,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: 'Context estimate',
            onPressed: _showContextEstimate,
            icon: const Icon(Icons.data_usage_outlined),
          ),
          IconButton(
            tooltip: 'Start roleplay chat',
            onPressed: busy ? null : _startRoleplay,
            icon: const Icon(Icons.play_arrow_outlined),
          ),
          PopupMenuButton<String>(
            tooltip: 'Workshop actions',
            enabled: !busy,
            onSelected: (value) {
              switch (value) {
                case 'lorebook':
                  _createLorebook();
                case 'opening':
                  _showOpeningSceneEditor();
                case 'characters':
                  _createCharacters();
                case 'update':
                  _updateExistingCharacter();
                case 'persona':
                  _createPersona();
                case 'toggle_lore_prompt':
                  _toggleLinkedLorebookInPrompt();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'lorebook',
                child: ListTile(
                  leading:
                      _exporting &&
                          (_exportStatus != null &&
                              _exportStatus!.contains('lorebook'))
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.menu_book_outlined),
                  title: Text(lorebookLabel),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'opening',
                child: ListTile(
                  leading:
                      _exporting && (_exportStatus?.contains('opening') == true)
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.auto_stories_outlined),
                  title: Text(openingLabel),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'characters',
                child: ListTile(
                  leading: Icon(Icons.groups_outlined),
                  title: Text('Create AI characters'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'update',
                child: ListTile(
                  leading: Icon(Icons.person_search_outlined),
                  title: Text('Update existing character'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'persona',
                child: ListTile(
                  leading: Icon(Icons.person_outline),
                  title: Text('Create my persona'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              if (_linkedLorebook != null) ...[
                const PopupMenuDivider(),
                PopupMenuItem(
                  value: 'toggle_lore_prompt',
                  child: ListTile(
                    leading: Icon(
                      _workshop.includeLinkedLorebookInPrompt
                          ? Icons.check_box
                          : Icons.check_box_outline_blank,
                    ),
                    title: const Text('Include linked lorebook in prompts'),
                    subtitle: Text(
                      _workshop.includeLinkedLorebookInPrompt
                          ? 'Adds lorebook text to chat / character exports'
                          : 'Off — saves tokens; chat transcript is enough',
                    ),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
      body: KeyboardInset(
        child: Column(
          children: [
            _statusBanner(theme, compact: keyboardOpen),
            Offstage(
              offstage: keyboardOpen,
              child: _importedSourceCard(theme),
            ),
            Offstage(
              offstage: keyboardOpen,
              child: _openingSceneCompactBar(theme),
            ),
            Expanded(
              child: _workshop.messages.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          linkedName != null
                              ? 'This workshop is ready to use “$linkedName”.\n\n'
                                  'Ask the AI to explain, expand, rewrite, or reorganize '
                                  'the lorebook—or create characters directly.'
                              : hasImported
                                  ? 'Your imported chat is ready as source material.\n\n'
                                      'Ask the AI what to extract, then use ⋮ for lorebook or opening scene.'
                                  : 'Example: “I want a rainy coastal city with rival '
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
                        final isLast = index == _workshop.messages.length - 1;
                        final thinking =
                            _sending && isLast && !isUser && message.text.isEmpty;
                        final isLastAi = isLast && !message.isUser;
                        final canGoPrev =
                            !message.isUser &&
                            message.swipes.length > 1 &&
                            message.swipeIndex > 0;
                        final canGoNextExisting =
                            !message.isUser &&
                            message.swipes.length > 1 &&
                            message.swipeIndex < message.swipes.length - 1;
                        final canQuickSwipe =
                            isLastAi &&
                            !thinking &&
                            !_busy &&
                            message.swipeIndex >= message.swipes.length - 1;
                        final showSwipePager =
                            !message.isUser &&
                            !thinking &&
                            (message.swipes.length > 1 || isLastAi);

                        Widget bubble = Material(
                          color: isUser
                              ? theme.colorScheme.primaryContainer
                              : theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(14),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: _busy ? null : () => _editMessage(index),
                            onLongPress:
                                _busy ? null : () => _showMessageMenu(index),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              child: Text(
                                thinking ? '…' : message.text,
                                style: theme.textTheme.bodyMedium,
                              ),
                            ),
                          ),
                        );

                        if (showSwipePager) {
                          bubble = Column(
                            crossAxisAlignment: isUser
                                ? CrossAxisAlignment.end
                                : CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              bubble,
                              _WorkshopSwipePager(
                                index: message.swipeIndex,
                                total: message.swipes.length,
                                onPrev: (!_busy && canGoPrev)
                                    ? () => _shiftSwipe(index, -1)
                                    : null,
                                onNext: (!_busy && canGoNextExisting)
                                    ? () => _shiftSwipe(index, 1)
                                    : (canQuickSwipe
                                          ? () => _regenerateMessage(
                                                index,
                                                asNewSwipe: true,
                                              )
                                          : null),
                                nextGeneratesSwipe: canQuickSwipe,
                              ),
                            ],
                          );
                        }

                        return Align(
                          alignment: isUser
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            constraints: BoxConstraints(
                              maxWidth: MediaQuery.sizeOf(context).width * 0.85,
                            ),
                            child: bubble,
                          ),
                        );
                      },
                    ),
            ),
            SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Offstage(
                    offstage: keyboardOpen,
                    child: _replyLengthPicker(theme),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: ChatComposerField(
                            key: const ValueKey('workshop_composer'),
                            focusNode: _composerFocus,
                            controller: _input,
                            enabled: !_busy,
                            enterToSend: _enterToSend,
                            decoration: const InputDecoration(
                              hintText: 'Describe your world…',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            onSend: () {
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
                          onPressed:
                              _exporting ? null : (_sending ? _stop : _send),
                          icon: Icon(_sending ? Icons.stop : Icons.send),
                          tooltip: _sending ? 'Stop' : 'Send',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkshopEditResult {
  const _WorkshopEditResult({required this.text, required this.regenerate});

  final String text;
  final bool regenerate;
}

class _WorkshopSwipePager extends StatelessWidget {
  const _WorkshopSwipePager({
    required this.index,
    required this.total,
    this.onPrev,
    this.onNext,
    this.nextGeneratesSwipe = false,
  });

  final int index;
  final int total;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  final bool nextGeneratesSwipe;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 4, right: 4, bottom: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Previous swipe',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 32),
            onPressed: onPrev,
            icon: Icon(
              Icons.chevron_left,
              color: onPrev == null
                  ? colorScheme.onSurface.withValues(alpha: 0.28)
                  : colorScheme.primary,
            ),
          ),
          Text(
            '${index + 1}/$total',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          IconButton(
            tooltip: nextGeneratesSwipe ? 'Generate new swipe' : 'Next swipe',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 32),
            onPressed: onNext,
            icon: Icon(
              Icons.chevron_right,
              color: onNext == null
                  ? colorScheme.onSurface.withValues(alpha: 0.28)
                  : colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}
