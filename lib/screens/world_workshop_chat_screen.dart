import 'dart:async' show unawaited;
import 'dart:convert';

import 'package:flutter/material.dart';

import '../models/character.dart';
import '../models/chat_message.dart';
import '../models/chat_session.dart';
import '../models/global_lorebook.dart';
import '../models/lorebook.dart';
import '../models/persona.dart';
import '../models/opening_scene_length.dart';
import '../models/world_workshop.dart';
import '../services/api_key_service.dart';
import '../services/appearance_controller.dart';
import '../services/character_category_service.dart';
import '../services/character_service.dart';
import '../services/chat_context_service.dart';
import '../services/chat_service.dart';
import '../services/nanogpt_service.dart';
import '../services/persona_service.dart';
import '../services/reply_rewrite_service.dart';
import '../services/settings_service.dart';
import '../services/world_info_service.dart';
import '../services/world_workshop_builder.dart';
import '../services/opening_scene_service.dart';
import '../services/world_workshop_service.dart';
import '../models/workshop_hub_models.dart';
import '../services/workshop_hub_controller.dart';
import '../widgets/workshop_compact_toolbar.dart';
import '../widgets/workshop_overview_sheet.dart';
import 'lorebooks_screen.dart';
import '../utils/scroll_to_end.dart';
import '../widgets/anima_avatar.dart';
import '../widgets/chat_composer_field.dart';
import '../widgets/greeting_picker.dart';
import '../widgets/keyboard_inset.dart';
import '../widgets/minimal_chip_button.dart';
import '../widgets/narrator_bubble.dart';
import '../widgets/opening_scene_picker.dart';
import '../widgets/reply_rewrite_sheet.dart';
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
  final _hubController = WorkshopHubController();
  final _contextService = const ChatContextService();
  static const _replyRewrite = ReplyRewriteService();

  final _input = TextEditingController();
  final _composerFocusNode = FocusNode();
  final _openingSceneController = TextEditingController();
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
  bool _fixLastReplyMode = false;

  bool get _canFixLastReply {
    if (_workshop.messages.isEmpty) return false;
    final last = _workshop.messages.last;
    return !last.isUser && last.text.trim().isNotEmpty;
  }

  /// Last message is yours with no AI reply yet (e.g. you deleted a bad reply).
  bool get _needsWorkshopReply {
    if (_workshop.messages.isEmpty) return false;
    return _workshop.messages.last.isUser;
  }

  bool get _canContinueWorkshop {
    if (_busy || _workshop.messages.isEmpty) return false;
    final last = _workshop.messages.last;
    if (last.isUser) return true;
    if (!last.isUser && last.text.trim().isEmpty) return true;
    return !last.isUser && last.text.trim().isNotEmpty;
  }

  void _refocusComposer() {
    if (!mounted || _busy) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _busy) return;
      if (_composerFocusNode.hasFocus || !_composerFocusNode.canRequestFocus) {
        return;
      }
      _composerFocusNode.requestFocus();
    });
  }

  void _onComposerContinue() {
    if (_busy) return;
    unawaited(_continueWorkshop());
  }

  Future<void> _pickModeFromSheet() async {
    final picked = await pickWorkshopMode(context, current: _workshop.mode);
    if (picked == null || !mounted) return;
    await _setMode(picked);
  }

  Future<void> _pickReplyLengthFromSheet() async {
    final picked = await pickWorkshopReplyLength(
      context,
      current: _workshop.replyLength,
    );
    if (picked == null || !mounted) return;
    await _setReplyLength(picked);
  }

  Future<void> _pickPromptIdeaFromSheet() async {
    final idea = await pickWorkshopPromptIdea(context);
    if (idea == null || !mounted) return;
    _applyPromptChip(idea);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _workshop = widget.workshop;
    _openingSceneController.text = _workshop.openingScene;
    unawaited(widget.workshopService.setLastOpenedId(_workshop.id));
    _loadLinkedLorebook();
    _loadModelContext();
    _loadContextBudget();
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
      worldSummary: _workshop.worldSummary,
      worldSummaryCoveredCount: _workshop.worldSummary.trim().isEmpty
          ? 0
          : _workshop.worldSummaryCoveredCount,
      historyTokenBudget: _historyTokenBudget,
      modelContextLength: _modelContextLength,
    );
  }

  int _historyTokenBudget = ContextSettings.defaultHistoryTokens;

  List<ChatMessage> _workshopHistoryForApi(int endExclusive) {
    final covered = _workshop.worldSummary.trim().isEmpty
        ? 0
        : _workshop.worldSummaryCoveredCount;
    return _contextService.selectHistory(
      messages: _workshop.messages,
      endExclusive: endExclusive,
      memoryCoveredCount: covered,
      historyTokenBudget: _historyTokenBudget,
    );
  }

  Future<void> _loadContextBudget() async {
    final ctx = await widget.settingsService.getContextSettings();
    if (!mounted) return;
    setState(() => _historyTokenBudget = ctx.historyTokenBudget);
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
              Text('Messages saved: ${estimate.messageCount}'),
              if (estimate.messagesInPrompt != null)
                Text(
                  'Messages sent on next turn: ${estimate.messagesInPrompt}',
                ),
              if (estimate.messagesTrimmedAway > 0)
                Text(
                  'Folded / trimmed from send: ${estimate.messagesTrimmedAway}',
                ),
              if (_workshop.worldSummaryCoveredCount > 0)
                Text(
                  'Folded into world summary: '
                  '${_workshop.worldSummaryCoveredCount} messages',
                ),
              Text(
                'Full transcript on device: '
                '~${ContextEstimate.formatTokenCount(estimate.fullTranscriptTokens)} tokens',
              ),
              if (_workshop.worldSummary.trim().isNotEmpty)
                Text(
                  'World summary: ~${ContextEstimate.formatTokenCount(_contextService.estimateTokens(_workshop.worldSummary))} tokens',
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
    widget.nanoGptService.cancelActiveStream();
    _input.dispose();
    _composerFocusNode.dispose();
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

    if (_fixLastReplyMode && _canFixLastReply) {
      _input.clear();
      await _sendFixLastReply(text);
      return;
    }

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

  /// Generate a workshop reply without a new user message — like Continue in chat.
  Future<void> _continueWorkshop() async {
    if (_busy || _workshop.messages.isEmpty) return;

    final lastIndex = _workshop.messages.length - 1;
    final last = _workshop.messages[lastIndex];

    if (last.isUser) {
      await _regenerateAfterUserMessage(lastIndex, confirmTruncate: false);
      return;
    }

    if (last.text.trim().isEmpty) {
      await _regenerateMessage(lastIndex, asNewSwipe: false);
      return;
    }

    final assistantId = ChatMessage.newId();
    setState(() {
      _sending = true;
      _workshop = _workshop.copyWith(
        messages: [
          ..._workshop.messages,
          ChatMessage(id: assistantId, role: ChatRole.assistant, text: ''),
        ],
      );
    });
    await _persist(_workshop);
    _scrollToEnd();

    await _streamAssistantReply(
      assistantIndex: _workshop.messages.length - 1,
      continueScene: true,
    );
  }

  /// User correction note + revise the previous assistant bubble (no new AI reply).
  Future<void> _sendFixLastReply(String correction) async {
    if (!_canFixLastReply || correction.trim().isEmpty) return;

    final assistantIndex = _workshop.messages.length - 1;
    final assistant = _workshop.messages[assistantIndex];
    final original = assistant.text;

    final userMessage = ChatMessage(
      id: ChatMessage.newId(),
      role: ChatRole.user,
      text: correction.trim(),
    );
    final messages = [..._workshop.messages, userMessage];

    setState(() {
      _sending = true;
      _fixLastReplyMode = false;
      _workshop = _workshop.copyWith(messages: messages);
    });
    await _persist(_workshop);
    _scrollToEnd();

    try {
      final model = await widget.settingsService.getModel();
      final sampling = WorldWorkshopBuilder.workshopCorrectionSampling(
        await widget.settingsService.getSampling(),
        originalCharCount: original.length,
      );
      final baseUrl = await widget.settingsService.getApiBaseUrl();
      final revised = await widget.nanoGptService.complete(
        model: model,
        messages: _builder.buildApplyCorrectionMessages(
          assistantReply: original,
          correctionNote: correction.trim(),
        ),
        baseUrl: baseUrl,
        sampling: sampling,
      );
      final trimmed = revised.trim();
      if (trimmed.isEmpty) {
        throw NanoGptException(
          'NanoGPT returned an empty revision. Try again.',
        );
      }
      if (!mounted) return;
      final updated = List<ChatMessage>.from(_workshop.messages);
      updated[assistantIndex] = assistant.withEditedText(trimmed);
      await _persist(_workshop.copyWith(messages: updated));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Last reply updated in place.')),
      );
    } on NanoGptException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not apply correction: $error')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _promptApplyCorrection(int assistantIndex) async {
    if (_busy) return;
    if (assistantIndex < 0 || assistantIndex >= _workshop.messages.length) {
      return;
    }
    final message = _workshop.messages[assistantIndex];
    if (message.isUser || message.text.trim().isEmpty) return;
    final controller = TextEditingController();
    final note = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Apply correction'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Describe what to change. The AI will rewrite this reply in place '
              '— not add a new message.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              minLines: 2,
              maxLines: 6,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'e.g. He was already from the U.S., not moved there.',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Apply'),
          ),
        ],
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
    if (note == null || note.isEmpty || !mounted) return;

    if (assistantIndex == _workshop.messages.length - 1) {
      await _sendFixLastReply(note);
      return;
    }

    await _applyCorrectionAtIndex(assistantIndex, note);
  }

  Future<void> _applyCorrectionAtIndex(
    int assistantIndex,
    String correction,
  ) async {
    if (_busy) return;
    final assistant = _workshop.messages[assistantIndex];
    final original = assistant.text.trim();
    if (original.isEmpty || correction.trim().isEmpty) return;

    setState(() => _sending = true);
    try {
      final model = await widget.settingsService.getModel();
      final sampling = WorldWorkshopBuilder.workshopCorrectionSampling(
        await widget.settingsService.getSampling(),
        originalCharCount: original.length,
      );
      final baseUrl = await widget.settingsService.getApiBaseUrl();
      final revised = await widget.nanoGptService.complete(
        model: model,
        messages: _builder.buildApplyCorrectionMessages(
          assistantReply: original,
          correctionNote: correction.trim(),
        ),
        baseUrl: baseUrl,
        sampling: sampling,
      );
      final trimmed = revised.trim();
      if (trimmed.isEmpty) {
        throw NanoGptException(
          'NanoGPT returned an empty revision. Try again.',
        );
      }
      if (!mounted) return;
      final updated = List<ChatMessage>.from(_workshop.messages);
      updated[assistantIndex] = assistant.withEditedText(trimmed);
      await _persist(_workshop.copyWith(messages: updated));
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Reply updated in place.')));
    } on NanoGptException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not apply correction: $error')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _streamAssistantReply({
    required int assistantIndex,
    List<Map<String, String>>? rewriteMessages,
    bool continueScene = false,
  }) async {
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

      final history = _workshopHistoryForApi(assistantIndex);
      final guidance = _workshop.workshopGuidanceNote.trim().isNotEmpty
          ? _workshop.workshopGuidanceNote
          : collaborator.guidanceNote;
      final apiMessages = <Map<String, String>>[
        {
          'role': 'system',
          'content': _builder.chatSystemPrompt(
            guidanceNote: guidance,
            sourceLorebook: _lorebookForPrompt,
            importedSource: _workshop.importedSource,
            replyLength: _workshop.replyLength,
            mode: _workshop.mode,
            workshopGuidanceNote: _workshop.workshopGuidanceNote,
            worldSummary: _workshop.worldSummary,
            conversation: _workshop.messages,
            canonPinMessageIds: _workshop.canonPinMessageIds,
          ),
        },
        for (final message in history) message.toApiMap(),
      ];
      if (rewriteMessages != null) {
        apiMessages.addAll(rewriteMessages);
      } else if (continueScene) {
        apiMessages.add({
          'role': 'user',
          'content': '(Continue. Write the workshop guide\'s next reply.)',
        });
      }

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
      await _maybeAutoFoldWorkshop();
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
      if (_looksLikeCancel(error)) {
        await _handleCancelledAssistant(assistantIndex);
        return;
      }
      await _handleFailedAssistant(assistantIndex);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Something went wrong: $error')));
    } finally {
      if (mounted) {
        setState(() => _sending = false);
        _refocusComposer();
      }
    }
  }

  bool _looksLikeCancel(Object error) {
    final text = '$error'.toLowerCase();
    return text.contains('cancel') ||
        text.contains('closed') ||
        text.contains('connection abort') ||
        text.contains('client is already closed');
  }

  Future<void> _maybeAutoFoldWorkshop() async {
    if (_busy) return;
    final contextSettings = await widget.settingsService.getContextSettings();
    if (!_contextService.shouldAutoSummarize(
      messageCount: _workshop.messages.length,
      memoryCoveredCount: _workshop.worldSummaryCoveredCount,
      context: contextSettings,
    )) {
      return;
    }
    await _foldWorkshopNow(quiet: true, contextSettings: contextSettings);
  }

  Future<void> _foldWorkshopNow({
    bool quiet = false,
    ContextSettings? contextSettings,
    bool fullTranscript = false,
  }) async {
    if (_busy && !quiet) return;
    final ctx =
        contextSettings ?? await widget.settingsService.getContextSettings();
    setState(() => _historyTokenBudget = ctx.historyTokenBudget);
    final cut = _contextService.summarizeCutIndex(
      messageCount: _workshop.messages.length,
      memoryCoveredCount: _workshop.worldSummaryCoveredCount,
      summarizeKeepRecent: ctx.summarizeKeepRecent,
    );
    if (!fullTranscript && cut <= _workshop.worldSummaryCoveredCount) {
      if (!quiet && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Not enough older messages to fold yet. Chat more, or lower '
              '“Keep recent” in Generation parameters.',
            ),
          ),
        );
      }
      return;
    }

    if (!quiet) {
      setState(() {
        _exporting = true;
        _exportStatus = 'Folding chat into world summary…';
      });
    }

    try {
      final collaborator = await widget.settingsService
          .getCollaboratorSettings();
      final model = await widget.settingsService.getModel();
      final sampling = ChatContextService.summarizeSampling(
        await widget.settingsService.getSampling(),
      );
      final baseUrl = await widget.settingsService.getApiBaseUrl();
      final guidance = _workshop.workshopGuidanceNote.trim().isNotEmpty
          ? _workshop.workshopGuidanceNote
          : collaborator.guidanceNote;
      final chunk = fullTranscript
          ? _workshop.messages
          : _workshop.messages.sublist(_workshop.worldSummaryCoveredCount, cut);
      final updatedSummary = await widget.nanoGptService.complete(
        model: model,
        messages: _builder.buildWorldSummaryMessages(
          conversation: _workshop.messages,
          chunk: fullTranscript ? null : chunk,
          existingSummary: _workshop.worldSummary,
          guidanceNote: guidance,
          importedSource: _workshop.importedSource,
          sourceLorebook: _linkedLorebook?.book,
          canonPinMessageIds: _workshop.canonPinMessageIds,
        ),
        baseUrl: baseUrl,
        sampling: sampling,
      );
      if (!mounted) return;
      final trimmed = updatedSummary.trim();
      if (trimmed.isEmpty) return;
      final newCovered = fullTranscript
          ? _contextService.summarizeCutIndex(
              messageCount: _workshop.messages.length,
              memoryCoveredCount: 0,
              summarizeKeepRecent: ctx.summarizeKeepRecent,
            )
          : cut;
      await _persist(
        _workshop.copyWith(
          worldSummary: trimmed,
          worldSummaryCoveredCount: newCovered,
        ),
      );
      if (!quiet && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'World summary updated (folded $newCovered messages).',
            ),
          ),
        );
      } else if (quiet && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('World summary optimized')),
        );
      }
    } on NanoGptException catch (error) {
      if (!quiet && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fold failed: ${error.message}')),
        );
      }
    } catch (error) {
      if (!quiet && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Fold failed: $error')));
      }
    } finally {
      if (!quiet && mounted) {
        setState(() {
          _exporting = false;
          _exportStatus = null;
        });
      }
    }
  }

  Future<void> _handleCancelledAssistant(int assistantIndex) async {
    if (!mounted) return;
    final updated = List<ChatMessage>.from(_workshop.messages);
    if (assistantIndex < 0 || assistantIndex >= updated.length) return;
    final message = updated[assistantIndex];
    if (message.text.trim().isNotEmpty) {
      setState(() => _workshop = _workshop.copyWith(messages: updated));
      await _persist(_workshop);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Stopped — kept partial reply.')),
        );
      }
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
      ChatMessage(id: ChatMessage.newId(), role: ChatRole.assistant, text: ''),
    );

    setState(() {
      _sending = true;
      _workshop = _workshop.copyWith(messages: messages);
    });
    await _persist(_workshop);
    await _streamAssistantReply(assistantIndex: messages.length - 1);
  }

  Future<void> _rewriteMessage(int index) async {
    if (_busy) return;
    if (index < 0 || index >= _workshop.messages.length) return;
    final message = _workshop.messages[index];
    if (message.isUser) return;
    final choice = await showReplyRewriteSheet(context);
    if (!mounted || choice == null) return;
    await _regenerateMessage(
      index,
      asNewSwipe: choice.asNewSwipe,
      rewrite: choice,
    );
  }

  Future<void> _regenerateMessage(
    int index, {
    required bool asNewSwipe,
    ReplyRewriteChoice? rewrite,
  }) async {
    if (_busy) return;
    if (index < 0 || index >= _workshop.messages.length) return;
    final message = _workshop.messages[index];
    if (message.isUser) return;
    if (!await _confirmRegenerateTruncating(index)) return;

    final originalText = message.text;
    var messages = _workshop.messages;
    if (index < messages.length - 1) {
      messages = messages.sublist(0, index + 1);
    }
    final prepared = _prepareAssistantForRegeneration(
      messages[index],
      asNewSwipe: asNewSwipe,
    );
    messages = List<ChatMessage>.from(messages)..[index] = prepared;

    List<Map<String, String>>? rewriteMessages;
    if (rewrite != null) {
      rewriteMessages = _replyRewrite.buildRewriteMessages(
        mode: rewrite.mode,
        originalReply: originalText,
        characterName: 'Workshop guide',
        contextMessages: messages.sublist(0, index),
        customInstruction: rewrite.customInstruction,
      );
    }

    setState(() {
      _sending = true;
      _workshop = _workshop.copyWith(messages: messages);
    });

    await _streamAssistantReply(
      assistantIndex: index,
      rewriteMessages: rewriteMessages,
    );
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
    final clearFold = index < _workshop.worldSummaryCoveredCount;
    final updated = List<ChatMessage>.from(_workshop.messages)..removeAt(index);
    setState(
      () => _workshop = _workshop.copyWith(
        messages: updated,
        worldSummaryCoveredCount: clearFold
            ? 0
            : _workshop.worldSummaryCoveredCount,
      ),
    );
    await _persist(_workshop);
  }

  Future<void> _rewindToMessage(int index) async {
    if (_busy) return;
    if (index < 0 || index >= _workshop.messages.length) return;
    if (index >= _workshop.messages.length - 1) return;
    final messages = _workshop.messages.sublist(0, index + 1);
    final clearFold = index + 1 < _workshop.worldSummaryCoveredCount;
    setState(
      () => _workshop = _workshop.copyWith(
        messages: messages,
        worldSummaryCoveredCount: clearFold
            ? 0
            : _workshop.worldSummaryCoveredCount,
      ),
    );
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
      isScrollControlled: true,
      builder: (context) {
        final height = MediaQuery.sizeOf(context).height * 0.55;
        return SafeArea(
          child: SizedBox(
            height: height,
            child: ListView(
              children: [
                ListTile(
                  leading: const Icon(Icons.push_pin_outlined),
                  title: Text(
                    _workshop.canonPinMessageIds.contains(message.id)
                        ? 'Unpin canon'
                        : 'Pin as canon',
                  ),
                  onTap: () => Navigator.pop(context, 'canon'),
                ),
                if (_workshop.messages.length >= 4)
                  ListTile(
                    leading: const Icon(Icons.compress),
                    title: const Text('Fold older chat into summary'),
                    subtitle: const Text(
                      'Merge earlier messages into world summary to save tokens',
                    ),
                    onTap: () => Navigator.pop(context, 'fold'),
                  ),
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
                if (isLast && _needsWorkshopReply) ...[
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.play_arrow),
                    title: const Text('Continue'),
                    subtitle: const Text(
                      'Generate the workshop guide\'s reply to your message',
                    ),
                    onTap: () => Navigator.pop(context, 'continue'),
                  ),
                ],
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
                    leading: const Icon(Icons.edit_note),
                    title: const Text('Apply correction'),
                    subtitle: const Text(
                      'Rewrite this reply in place from a short fix note',
                    ),
                    onTap: () => Navigator.pop(context, 'apply_fix'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.tune),
                    title: const Text('Rewrite reply…'),
                    subtitle: const Text(
                      'Shorten, expand, change mood, or custom',
                    ),
                    onTap: () => Navigator.pop(context, 'rewrite'),
                  ),
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
                    subtitle: const Text(
                      'Keep this version and generate another',
                    ),
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
      },
    );

    if (action == 'canon') {
      final next = _hubController.hub.toggleCanonPin(_workshop, message.id);
      setState(() => _workshop = next);
      await _persist(next);
    }
    if (action == 'fold') await _foldWorkshopNow();
    if (action == 'edit') await _editMessage(index);
    if (action == 'delete') await _deleteMessage(index);
    if (action == 'rewind') await _rewindToMessage(index);
    if (action == 'continue') await _continueWorkshop();
    if (action == 'regen_reply') await _regenerateAfterUserMessage(index);
    if (action == 'regen') {
      await _regenerateMessage(index, asNewSwipe: false);
    }
    if (action == 'swipe') {
      await _regenerateMessage(index, asNewSwipe: true);
    }
    if (action == 'rewrite') await _rewriteMessage(index);
    if (action == 'apply_fix') await _promptApplyCorrection(index);
    if (action == 'swipe_prev') _shiftSwipe(index, -1);
    if (action == 'swipe_next') _shiftSwipe(index, 1);
  }

  Future<void> _toggleLinkedLorebookInPrompt() async {
    final next = !_workshop.includeLinkedLorebookInPrompt;
    setState(
      () => _workshop = _workshop.copyWith(includeLinkedLorebookInPrompt: next),
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

  Future<void> _setOpeningSceneLength(OpeningSceneLength length) async {
    if (_workshop.openingSceneLength == length) return;
    setState(() => _workshop = _workshop.copyWith(openingSceneLength: length));
    await _persist(_workshop);
  }

  Widget _openingSceneLengthPicker(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Length', style: theme.textTheme.labelLarge),
          const SizedBox(height: 6),
          SegmentedButton<OpeningSceneLength>(
            segments: [
              for (final mode in OpeningSceneLength.values)
                ButtonSegment<OpeningSceneLength>(
                  value: mode,
                  label: Text(mode.label),
                  tooltip: mode.subtitle,
                ),
            ],
            selected: {_workshop.openingSceneLength},
            onSelectionChanged: _busy || _exporting
                ? null
                : (selected) {
                    if (selected.isEmpty) return;
                    unawaited(_setOpeningSceneLength(selected.first));
                  },
            showSelectedIcon: false,
            style: ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _workshop.openingSceneLength.subtitle,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Future<void> _setReplyLength(WorkshopReplyLength length) async {
    if (_workshop.replyLength == length) return;
    setState(() => _workshop = _workshop.copyWith(replyLength: length));
    await _persist(_workshop);
  }

  void _stopGeneration() {
    if (!_sending) return;
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

    final isUpdate = _workshop.exportedLorebookId != null;

    // Updates merge chat into the linked book automatically — no pre-flight audit.
    if (!isUpdate) {
      final localChecks = _hubController.hub.localExportChecklist(_workshop);
      final aiChecks = await _hubController.aiChecklist(
        workshop: _workshop,
        nanoGpt: widget.nanoGptService,
        settings: widget.settingsService,
        sourceLorebook: _linkedLorebook?.book,
      );
      if (!mounted) return;
      final allChecks = [...localChecks, ...aiChecks];
      if (allChecks.isNotEmpty) {
        final proceed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Before lorebook export'),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Next step: AI builds a lorebook from this workshop chat. '
                    'These notes are a preview — the export will try to cover them.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  for (final item in allChecks)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text('• $item'),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Create lorebook'),
              ),
            ],
          ),
        );
        if (proceed != true) return;
      }
    }

    setState(() {
      _exporting = true;
      _exportStatus = isUpdate ? 'Updating lorebook…' : 'Creating lorebook…';
    });
    try {
      final collaborator = await widget.settingsService
          .getCollaboratorSettings();
      final model = await widget.settingsService.getModel();
      final sampling = WorldWorkshopBuilder.workshopExportSampling(
        await widget.settingsService.getSampling(),
      );
      final baseUrl = await widget.settingsService.getApiBaseUrl();

      final guidance = _workshop.workshopGuidanceNote.trim().isNotEmpty
          ? _workshop.workshopGuidanceNote
          : collaborator.guidanceNote;
      final exportMessages = _builder.buildExportMessages(
        conversation: _workshop.messages,
        guidanceNote: guidance,
        sourceLorebook: _linkedLorebook?.book,
        importedSource: _workshop.importedSource,
        worldSummary: _workshop.worldSummary,
        canonPinMessageIds: _workshop.canonPinMessageIds,
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
          lorebookUpdatedAtMessageCount: _workshop.messages.length,
        ),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isUpdate
                ? 'Updated “${global.displayName}” (${book.entries.length} entries) '
                      'in World Info.'
                : 'Saved “${global.displayName}” (${book.entries.length} entries) '
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
        SnackBar(
          content: Text(
            isUpdate
                ? 'Could not update lorebook: $error'
                : 'Could not create lorebook: $error',
          ),
        ),
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

  Future<void> _createOpeningScene({required bool reviseExisting}) async {
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
          reviseExisting: reviseExisting,
          length: _workshop.openingSceneLength,
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
        SnackBar(
          content: Text(
            reviseExisting
                ? 'Opening scene revised from chat.'
                : 'Fresh opening scene generated from chat.',
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
      sourceWorkshopId: _workshop.id,
    );
    if (!mounted) return;
    var linked = session;
    if (_workshop.chatKit.defaultAuthorsNote.trim().isNotEmpty) {
      linked = linked.copyWith(
        authorsNote: _workshop.chatKit.defaultAuthorsNote,
      );
      await widget.chatService.saveChat(linked);
    }
    await _openChat(linked);
  }

  Future<void> _playThisWorld() async {
    if (_sending || _exporting || _loadingLinkedLorebook) return;
    await _saveOpeningSceneField();
    if (!mounted) return;

    final allChars = await widget.characterService.loadCharacters();
    final defaultPersona = await widget.personaService.getActivePersona();
    if (!mounted) return;

    final plan = await _hubController.playPlan(
      workshop: _workshop,
      allCharacters: allChars,
      defaultPersona: defaultPersona,
      linkedLorebook: _linkedLorebook,
    );

    if (!plan.canPlaySolo && !plan.canPlayGroup) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Save characters from this workshop first (⋮ → Create characters), '
            'then Play this world.',
          ),
        ),
      );
      return;
    }

    Persona? persona = defaultPersona;
    final personaId = plan.personaId;
    if (personaId != null) {
      persona = await widget.personaService.getById(personaId);
    }
    persona ??= defaultPersona;
    if (!mounted) return;

    if (plan.canPlayGroup && plan.characters.length >= 2) {
      final ordered = plan.characters;
      final session = await widget.chatService.startGroupChat(
        ordered,
        userName: persona.name,
        personaId: persona.id,
        authorsNote: plan.authorsNote,
        autoReply: plan.autoReply,
        lorebookIds: plan.lorebookIds,
        openingScene: plan.openingScene,
        title: plan.title,
        sourceWorkshopId: plan.sourceWorkshopId,
      );
      if (!mounted) return;
      await _openChat(session);
      return;
    }

    final character = plan.characters.first;
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
      openingScene: plan.openingScene,
      sourceWorkshopId: plan.sourceWorkshopId,
    );
    if (!mounted) return;
    var linked = session;
    if (plan.authorsNote.trim().isNotEmpty) {
      linked = linked.copyWith(authorsNote: plan.authorsNote);
    }
    if (plan.lorebookIds != null) {
      linked = linked.copyWith(lorebookIds: plan.lorebookIds);
    }
    if (plan.autoReply) {
      linked = linked.copyWith(autoReply: true);
    }
    await widget.chatService.saveChat(linked);
    await _openChat(linked);
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
      final build = await widget.settingsService.resolveCharacterBuild();
      final sampling = WorldWorkshopBuilder.workshopExportSampling(
        build.sampling,
      );
      final baseUrl = await widget.settingsService.getApiBaseUrl();
      final existingChars = await widget.characterService.loadCharacters();
      final existingNames = {
        for (final c in existingChars) c.name.trim().toLowerCase(),
      };

      var detectRaw = await widget.nanoGptService.complete(
        model: build.model,
        messages: _builder.buildCharacterDetectMessages(
          conversation: _workshop.messages,
          buildPromptNote: build.promptNote,
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
          model: build.model,
          messages: [
            ..._builder.buildCharacterDetectMessages(
              conversation: _workshop.messages,
              buildPromptNote: build.promptNote,
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
            sampling: WorldWorkshopBuilder.workshopExportSampling(
              build.sampling,
            ),
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
            final tagged = saved.sourceWorkshopId == _workshop.id
                ? saved
                : (await widget.characterService.upsert(
                    saved.copyWith(sourceWorkshopId: _workshop.id),
                  )).where((c) => c.id == saved.id).first;
            final nextWorkshop = _hubController.hub.linkCharacter(
              _workshop,
              tagged.id,
            );
            await _persist(nextWorkshop);
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

  Future<void> _updateWorkshopCast({Character? preselected}) async {
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

    if (preselected != null) {
      await _runCharacterUpdate(preselected);
      return;
    }

    setState(() {
      _exporting = true;
      _exportStatus = 'Loading workshop cast…';
    });

    try {
      final existingChars = await widget.characterService.loadCharacters();
      if (!mounted) return;
      final cast = _builder.workshopCastCharacters(
        workshop: _workshop,
        allCharacters: existingChars,
      );

      setState(() {
        _exporting = false;
        _exportStatus = null;
      });

      if (cast.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No workshop characters yet. Use ⋮ → Create AI characters first.',
            ),
          ),
        );
        return;
      }

      Character? selected = await _pickWorkshopCastCharacter(cast);
      if (!mounted || selected == null) return;

      await _runCharacterUpdate(selected);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not load cast: $error')));
    } finally {
      if (mounted) {
        setState(() {
          _exporting = false;
          _exportStatus = null;
        });
      }
    }
  }

  Future<void> _runCharacterUpdate(Character selected) async {
    if (_sending || _exporting || _loadingLinkedLorebook) return;

    setState(() {
      _exporting = true;
      _exportStatus = 'Updating ${selected.name}…';
    });

    try {
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
        final tagged = saved.sourceWorkshopId == _workshop.id
            ? saved
            : (await widget.characterService.upsert(
                saved.copyWith(sourceWorkshopId: _workshop.id),
              )).where((c) => c.id == saved.id).first;
        final nextWorkshop = _hubController.hub.linkCharacter(
          _workshop,
          tagged.id,
        );
        await _persist(nextWorkshop);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Updated “${tagged.name}”.')));
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

  Future<Character?> _pickWorkshopCastCharacter(List<Character> cast) async {
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
                    'Update workshop cast',
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: Text(
                    'Characters created or linked in this workshop. Pick one to '
                    'merge the latest chat into that card — you review before save.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: cast.length,
                    itemBuilder: (context, index) {
                      final character = cast[index];
                      return ListTile(
                        leading: AnimaAvatar(
                          fileName: character.avatarFileName,
                          label: character.name,
                          radius: 20,
                        ),
                        title: Text(character.name),
                        subtitle: Text(
                          character.description.trim().isNotEmpty
                              ? character.description.trim()
                              : 'Tap to update from workshop chat',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.pop(context, character),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _createCharacters();
                    },
                    icon: const Icon(Icons.person_add_outlined),
                    label: const Text('Create new characters'),
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
      final build = await widget.settingsService.resolveCharacterBuild();
      final sampling = WorldWorkshopBuilder.workshopExportSampling(
        build.sampling,
      );
      final baseUrl = await widget.settingsService.getApiBaseUrl();
      final existingPersonas = await widget.personaService.loadPersonas();
      final existingNames = {
        for (final p in existingPersonas) p.name.trim().toLowerCase(),
      };

      var detectRaw = await widget.nanoGptService.complete(
        model: build.model,
        messages: _builder.buildCharacterDetectMessages(
          conversation: _workshop.messages,
          buildPromptNote: build.promptNote,
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
          model: build.model,
          messages: [
            ..._builder.buildCharacterDetectMessages(
              conversation: _workshop.messages,
              buildPromptNote: build.promptNote,
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
      final collaborator = await widget.settingsService
          .getCollaboratorSettings();
      final personaRaw = await widget.nanoGptService.complete(
        model: build.model,
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
      final tagged = saved.sourceWorkshopId == _workshop.id
          ? saved
          : (await widget.personaService.upsert(
              saved.copyWith(sourceWorkshopId: _workshop.id),
            )).where((p) => p.id == saved.id).first;
      await _persist(_workshop.copyWith(linkedPersonaId: tagged.id));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved ${tagged.name} to Personas.')),
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

  Future<void> _updateWorkshopPersona() async {
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
            'Chat a bit first (or import a roleplay chat), then update your persona.',
          ),
        ),
      );
      return;
    }

    final personaId = _workshop.linkedPersonaId;
    if (personaId == null || personaId.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No workshop persona yet. Use ⋮ → Create my persona first.',
          ),
        ),
      );
      return;
    }

    final existing = await widget.personaService.getById(personaId);
    if (!mounted) return;
    if (existing == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Linked persona is missing. Create my persona again from this workshop.',
          ),
        ),
      );
      return;
    }

    await _runPersonaUpdate(existing);
  }

  Future<void> _runPersonaUpdate(Persona existing) async {
    if (_sending || _exporting || _loadingLinkedLorebook) return;

    setState(() {
      _exporting = true;
      _exportStatus = 'Updating ${existing.name}…';
    });

    try {
      final collaborator = await widget.settingsService
          .getCollaboratorSettings();
      final model = await widget.settingsService.getModel();
      final sampling = WorldWorkshopBuilder.workshopExportSampling(
        await widget.settingsService.getSampling(),
      );
      final baseUrl = await widget.settingsService.getApiBaseUrl();

      final personaRaw = await widget.nanoGptService.complete(
        model: model,
        messages: _builder.buildPersonaUpdateMessages(
          conversation: _workshop.messages,
          existing: existing,
          guidanceNote: collaborator.guidanceNote,
          sourceLorebook: _lorebookForPrompt,
          importedSource: _workshop.importedSource,
          worldSummary: _workshop.worldSummary,
          canonPinMessageIds: _workshop.canonPinMessageIds,
        ),
        baseUrl: baseUrl,
        sampling: sampling,
      );

      final draft = _builder.parsePersonaUpdateJson(
        personaRaw,
        original: existing,
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
      final tagged = saved.sourceWorkshopId == _workshop.id
          ? saved
          : (await widget.personaService.upsert(
              saved.copyWith(sourceWorkshopId: _workshop.id),
            )).where((p) => p.id == saved.id).first;
      await _persist(_workshop.copyWith(linkedPersonaId: tagged.id));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Updated persona “${tagged.name}”.')),
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
        SnackBar(content: Text('Could not update persona: $error')),
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
                  Text('Opening scene', style: theme.textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text(
                    'Narrator setup for roleplay chats — separate from lore entries '
                    'and character greetings. Saved scenes sync to Settings → '
                    'Opening scenes.',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  _openingSceneLengthPicker(theme),
                  if (_workshop.openingScene.trim().isNotEmpty) ...[
                    NarratorBubble(text: _workshop.openingScene, onTap: null),
                    const SizedBox(height: 8),
                    Text(
                      'An opening scene is already saved for this workshop. '
                      'Choose fresh to ignore the saved text, or revise to merge '
                      'changes from chat.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
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
                  if (_workshop.openingScene.trim().isEmpty)
                    FilledButton.icon(
                      onPressed:
                          (_sending || _exporting || _loadingLinkedLorebook)
                          ? null
                          : () async {
                              await _createOpeningScene(reviseExisting: false);
                              if (sheetContext.mounted) {
                                Navigator.pop(sheetContext);
                              }
                            },
                      icon: const Icon(Icons.auto_awesome),
                      label: const Text('Generate from chat'),
                    )
                  else ...[
                    FilledButton.icon(
                      onPressed:
                          (_sending || _exporting || _loadingLinkedLorebook)
                          ? null
                          : () async {
                              await _createOpeningScene(reviseExisting: false);
                              if (sheetContext.mounted) {
                                Navigator.pop(sheetContext);
                              }
                            },
                      icon: const Icon(Icons.refresh),
                      label: const Text('Fresh from chat'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed:
                          (_sending || _exporting || _loadingLinkedLorebook)
                          ? null
                          : () async {
                              await _createOpeningScene(reviseExisting: true);
                              if (sheetContext.mounted) {
                                Navigator.pop(sheetContext);
                              }
                            },
                      icon: const Icon(Icons.edit_note),
                      label: const Text('Revise from chat'),
                    ),
                  ],
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

  Future<void> _showOverview() async {
    final allChars = await widget.characterService.loadCharacters();
    final chats = await widget.chatService.listChatsForWorkshop(_workshop.id);
    Persona? persona;
    if (_workshop.linkedPersonaId != null) {
      persona = await widget.personaService.getById(_workshop.linkedPersonaId!);
    }
    if (!mounted) return;

    final linkedChars = _builder.workshopCastCharacters(
      workshop: _workshop,
      allCharacters: allChars,
    );

    final status = _hubController.statusFor(
      workshop: _workshop,
      allCharacters: allChars,
      workshopChats: chats,
      linkedLorebook: _linkedLorebook,
    );

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => WorkshopOverviewSheet(
        workshop: _workshop,
        status: status,
        linkedLorebook: _linkedLorebook,
        linkedCharacters: linkedChars,
        linkedPersona: persona,
        workshopChats: chats,
        onPlayWorld: _busy
            ? null
            : () {
                Navigator.pop(context);
                _playThisWorld();
              },
        onOpenLorebook: _linkedLorebook == null
            ? null
            : () {
                Navigator.pop(context);
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => LorebooksScreen(
                      worldInfoService: widget.worldInfoService,
                      settingsService: widget.settingsService,
                      nanoGptService: widget.nanoGptService,
                    ),
                  ),
                );
              },
        onOpenOpeningScene: () {
          Navigator.pop(context);
          _showOpeningSceneEditor();
        },
        onOpenChat: (chat) {
          Navigator.pop(context);
          _openChat(chat);
        },
        onSummarizeWorld: _busy
            ? null
            : () {
                Navigator.pop(context);
                _summarizeWorkshop();
              },
        onGenerateOverview: _busy
            ? null
            : () {
                Navigator.pop(context);
                _generateWorldOverview();
              },
        onGlossary: _busy
            ? null
            : () {
                Navigator.pop(context);
                _glossaryToLorebook();
              },
        onSceneIdeas: _busy
            ? null
            : () {
                Navigator.pop(context);
                _generateSceneIdeas();
              },
        onEditSheets: () {
          Navigator.pop(context);
          _editSheets();
        },
        onEditChatKit: () {
          Navigator.pop(context);
          _editChatKit();
        },
        onEditWorldSummary: () {
          Navigator.pop(context);
          _editWorldSummary();
        },
        onRefreshFromChat: chats.isEmpty
            ? null
            : () {
                Navigator.pop(context);
                _refreshFromChat(chats.first);
              },
        onExportBundle: () {
          Navigator.pop(context);
          _exportBundle(linkedChars, persona);
        },
        onDuplicate: () {
          Navigator.pop(context);
          _duplicateWorkshop();
        },
        onMerge: () {
          Navigator.pop(context);
          _mergeWorkshop();
        },
        onUpdateCharacter: _busy
            ? null
            : (character) {
                Navigator.pop(context);
                _updateWorkshopCast(preselected: character);
              },
        onUpdatePersona: _busy || persona == null
            ? null
            : () {
                Navigator.pop(context);
                _updateWorkshopPersona();
              },
      ),
    );
  }

  Future<void> _summarizeWorkshop() async {
    await _foldWorkshopNow(fullTranscript: true);
  }

  Future<void> _generateWorldOverview() async {
    setState(() {
      _exporting = true;
      _exportStatus = 'Generating overview…';
    });
    try {
      final overview = await _hubController.generateOverview(
        workshop: _workshop,
        nanoGpt: widget.nanoGptService,
        settings: widget.settingsService,
        sourceLorebook: _linkedLorebook?.book,
      );
      if (overview == null || overview.trim().isEmpty) return;
      await _persist(_workshop.copyWith(worldOverview: overview.trim()));
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('World overview saved.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Overview failed: $error')));
    } finally {
      if (mounted) {
        setState(() {
          _exporting = false;
          _exportStatus = null;
        });
      }
    }
  }

  Future<void> _glossaryToLorebook() async {
    if (_linkedLorebook == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Create or link a lorebook first.')),
      );
      return;
    }
    setState(() {
      _exporting = true;
      _exportStatus = 'Extracting glossary…';
    });
    try {
      final entries = await _hubController.extractGlossary(
        workshop: _workshop,
        nanoGpt: widget.nanoGptService,
        settings: widget.settingsService,
        sourceLorebook: _linkedLorebook?.book,
      );
      if (entries.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No glossary terms found.')),
        );
        return;
      }
      final merged = _hubController.mergeGlossaryIntoBook(
        _linkedLorebook!.book,
        entries,
      );
      final global = _linkedLorebook!.copyWith(book: merged);
      await widget.worldInfoService.upsert(global);
      if (mounted) setState(() => _linkedLorebook = global);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Added ${entries.length} glossary entries to lorebook.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Glossary failed: $error')));
    } finally {
      if (mounted) {
        setState(() {
          _exporting = false;
          _exportStatus = null;
        });
      }
    }
  }

  Future<void> _generateSceneIdeas() async {
    setState(() {
      _exporting = true;
      _exportStatus = 'Generating scene ideas…';
    });
    try {
      final ideas = await _hubController.generateSceneIdeas(
        workshop: _workshop,
        nanoGpt: widget.nanoGptService,
        settings: widget.settingsService,
      );
      if (ideas.isEmpty) return;
      await _persist(
        _workshop.copyWith(sceneIdeas: [..._workshop.sceneIdeas, ...ideas]),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added ${ideas.length} scene ideas.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Scene ideas failed: $error')));
    } finally {
      if (mounted) {
        setState(() {
          _exporting = false;
          _exportStatus = null;
        });
      }
    }
  }

  Future<void> _editSheets() async {
    final locController = TextEditingController(
      text: _workshop.locations
          .map((l) => '${l.name}: ${l.description}')
          .join('\n'),
    );
    final relController = TextEditingController(
      text: _workshop.relationships
          .map((r) => '${r.fromName} ↔ ${r.toName}: ${r.relationDynamic}')
          .join('\n'),
    );
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Locations & relationships',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: locController,
                  minLines: 3,
                  maxLines: 8,
                  decoration: const InputDecoration(
                    labelText: 'Locations (name: description per line)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: relController,
                  minLines: 3,
                  maxLines: 8,
                  decoration: const InputDecoration(
                    labelText: 'Relationships (A ↔ B: dynamic per line)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _busy
                      ? null
                      : () async {
                          setState(() {
                            _exporting = true;
                            _exportStatus = 'Extracting sheets…';
                          });
                          try {
                            final (locs, rels) = await _hubController
                                .extractSheets(
                                  workshop: _workshop,
                                  nanoGpt: widget.nanoGptService,
                                  settings: widget.settingsService,
                                );
                            locController.text = locs
                                .map((l) => '${l.name}: ${l.description}')
                                .join('\n');
                            relController.text = rels
                                .map(
                                  (r) =>
                                      '${r.fromName} ↔ ${r.toName}: ${r.relationDynamic}',
                                )
                                .join('\n');
                          } finally {
                            if (mounted) {
                              setState(() {
                                _exporting = false;
                                _exportStatus = null;
                              });
                            }
                          }
                        },
                  child: const Text('AI extract from chat'),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: () {
                    final locs = <WorkshopLocation>[];
                    for (final line in locController.text.split('\n')) {
                      final parts = line.split(':');
                      if (parts.isEmpty || parts.first.trim().isEmpty) continue;
                      locs.add(
                        WorkshopLocation(
                          name: parts.first.trim(),
                          description: parts.length > 1
                              ? parts.sublist(1).join(':').trim()
                              : '',
                        ),
                      );
                    }
                    final rels = <WorkshopRelationship>[];
                    for (final line in relController.text.split('\n')) {
                      final trimmed = line.trim();
                      if (trimmed.isEmpty) continue;
                      final sep = trimmed.contains('↔') ? '↔' : ':';
                      final parts = trimmed.split(sep);
                      if (parts.length < 2) continue;
                      final relDynamic = parts.length > 2
                          ? parts.sublist(2).join(sep).trim()
                          : parts[1].contains(':')
                          ? parts[1].split(':').skip(1).join(':').trim()
                          : '';
                      rels.add(
                        WorkshopRelationship(
                          fromName: parts[0].trim(),
                          toName: parts[1].split(':').first.trim(),
                          relationDynamic: relDynamic,
                        ),
                      );
                    }
                    unawaited(
                      _persist(
                        _workshop.copyWith(
                          locations: locs,
                          relationships: rels,
                        ),
                      ),
                    );
                    Navigator.pop(context);
                  },
                  child: const Text('Save'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _editWorldSummary() async {
    final controller = TextEditingController(text: _workshop.worldSummary);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('World summary'),
        content: TextField(
          controller: controller,
          minLines: 4,
          maxLines: 12,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: 'Established facts for this world…',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              unawaited(
                _persist(_workshop.copyWith(worldSummary: controller.text)),
              );
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _editChatKit() async {
    final kit = _workshop.chatKit;
    final noteController = TextEditingController(text: kit.defaultAuthorsNote);
    bool loreEnabled = kit.defaultLorebookEnabled;
    bool autoReply = kit.autoReply;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Default chat kit',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                SwitchListTile(
                  title: const Text('Enable linked lorebook on new chats'),
                  value: loreEnabled,
                  onChanged: (v) => setSheet(() => loreEnabled = v),
                ),
                SwitchListTile(
                  title: const Text('Auto-reply on new chats'),
                  value: autoReply,
                  onChanged: (v) => setSheet(() => autoReply = v),
                ),
                TextField(
                  controller: noteController,
                  minLines: 2,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    labelText: "Default Author's Note",
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () {
                    unawaited(
                      _persist(
                        _workshop.copyWith(
                          chatKit: kit.copyWith(
                            defaultLorebookEnabled: loreEnabled,
                            autoReply: autoReply,
                            defaultAuthorsNote: noteController.text,
                          ),
                        ),
                      ),
                    );
                    Navigator.pop(context);
                  },
                  child: const Text('Save'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _refreshFromChat(ChatSession chat) async {
    final chars = await widget.characterService.loadCharacters();
    final cast = <Character>[];
    for (final id in chat.effectiveParticipantIds) {
      for (final c in chars) {
        if (c.id == id) cast.add(c);
      }
    }
    Persona? persona;
    if (chat.personaId != null) {
      persona = await widget.personaService.getById(chat.personaId!);
    }
    setState(() {
      _exporting = true;
      _exportStatus = 'Refreshing from chat…';
    });
    try {
      final next = await _hubController.refreshWorkshopSource(
        workshop: _workshop,
        chat: chat,
        characters: cast,
        persona: persona,
      );
      if (next == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No new source material from that chat.'),
          ),
        );
        return;
      }
      await _persist(next);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Imported source refreshed from chat.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Refresh failed: $error')));
    } finally {
      if (mounted) {
        setState(() {
          _exporting = false;
          _exportStatus = null;
        });
      }
    }
  }

  Future<void> _exportBundle(
    List<Character> characters,
    Persona? persona,
  ) async {
    try {
      await _hubController.exportBundleFile(
        context: context,
        workshop: _workshop,
        lorebook: _linkedLorebook,
        characters: characters,
        persona: persona,
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Export failed: $error')));
    }
  }

  Future<void> _duplicateWorkshop() async {
    final copy = _hubController.hub.duplicate(_workshop);
    await widget.workshopService.upsert(copy);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Duplicated as “${copy.title}”.')));
  }

  Future<void> _mergeWorkshop() async {
    final workshops = await widget.workshopService.loadWorkshops();
    final others = workshops.where((w) => w.id != _workshop.id).toList();
    if (!mounted || others.isEmpty) return;
    final pick = await showModalBottomSheet<WorldWorkshop>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('Merge with workshop')),
            for (final w in others)
              ListTile(
                title: Text(w.title),
                subtitle: Text('${w.messages.length} messages'),
                onTap: () => Navigator.pop(context, w),
              ),
          ],
        ),
      ),
    );
    if (pick == null || !mounted) return;
    final merged = _hubController.hub.merge(_workshop, pick);
    await widget.workshopService.upsert(merged);
    await widget.workshopService.delete(pick.id);
    if (!mounted) return;
    setState(() => _workshop = merged);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Workshops merged.')));
  }

  Future<void> _setMode(WorkshopMode mode) async {
    if (mode == _workshop.mode) return;
    await _persist(_workshop.copyWith(mode: mode));
  }

  void _applyPromptChip(String text) {
    _input.text = text;
    _input.selection = TextSelection.collapsed(offset: text.length);
  }

  Widget _workshopOverflowButton({
    required bool busy,
    required String lorebookLabel,
    required String openingLabel,
  }) {
    return PopupMenuButton<String>(
      tooltip: 'Workshop menu',
      enabled: !busy,
      onSelected: _handleWorkshopMenuAction,
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'dashboard',
          child: ListTile(
            leading: Icon(Icons.dashboard_outlined),
            title: Text('World dashboard'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        const PopupMenuItem(
          value: 'context',
          child: ListTile(
            leading: Icon(Icons.data_usage_outlined),
            title: Text('Context estimate'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        const PopupMenuItem(
          value: 'play_roleplay',
          child: ListTile(
            leading: Icon(Icons.play_arrow_outlined),
            title: Text('Start roleplay (pick cast)'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        const PopupMenuDivider(),
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
            leading: _exporting && (_exportStatus?.contains('opening') == true)
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
            leading: Icon(Icons.edit_outlined),
            title: Text('Update workshop cast'),
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
        if (_workshop.linkedPersonaId != null)
          const PopupMenuItem(
            value: 'update_persona',
            child: ListTile(
              leading: Icon(Icons.badge_outlined),
              title: Text('Update my persona'),
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
    );
  }

  void _handleWorkshopMenuAction(String value) {
    switch (value) {
      case 'dashboard':
        _showOverview();
      case 'context':
        _showContextEstimate();
      case 'play_roleplay':
        _startRoleplay();
      case 'lorebook':
        _createLorebook();
      case 'opening':
        _showOpeningSceneEditor();
      case 'characters':
        _createCharacters();
      case 'update':
        _updateWorkshopCast();
      case 'persona':
        _createPersona();
      case 'update_persona':
        _updateWorkshopPersona();
      case 'toggle_lore_prompt':
        _toggleLinkedLorebookInPrompt();
    }
  }

  Widget _statusBanner(ThemeData theme) {
    return Material(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      child: InkWell(
        onTap: _showContextEstimate,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _exportStatus ??
                      (_sending
                          ? 'Generating… tap Stop to cancel'
                          : _estimate.compactBannerLine),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: (_estimate.fillRatio ?? 0) >= 0.85
                        ? theme.colorScheme.error
                        : theme.colorScheme.tertiary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (_exportStatus == null && _workshop.isLorebookStale)
                IconButton(
                  tooltip: 'Update lorebook',
                  visualDensity: VisualDensity.compact,
                  onPressed: _busy ? null : _createLorebook,
                  icon: const Icon(Icons.refresh, size: 20),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
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
        title: GestureDetector(
          onTap: _showOverview,
          child: Text(_workshop.title, overflow: TextOverflow.ellipsis),
        ),
        actions: [
          IconButton(
            tooltip: 'Play this world',
            onPressed: busy ? null : _playThisWorld,
            icon: const Icon(Icons.play_circle_outline),
          ),
          _workshopOverflowButton(
            busy: busy,
            lorebookLabel: lorebookLabel,
            openingLabel: openingLabel,
          ),
        ],
      ),
      body: KeyboardInset(
        child: Column(
          children: [
            if (!keyboardOpen) _statusBanner(theme),
            if (!keyboardOpen)
              WorkshopCompactToolbar(
                workshop: _workshop,
                hasImportedSource: hasImported,
                enabled: !busy,
                onPickMode: _pickModeFromSheet,
                onPickReplyLength: _pickReplyLengthFromSheet,
                onOpeningScene: _showOpeningSceneEditor,
                onImportedSource: hasImported
                    ? _showImportedSourceDetails
                    : null,
                onPromptIdeas: _pickPromptIdeaFromSheet,
                showPromptIdeas: _workshop.messages.isEmpty,
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
                            _sending &&
                            isLast &&
                            !isUser &&
                            message.text.isEmpty;
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
                            onLongPress: _busy
                                ? null
                                : () => _showMessageMenu(index),
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
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Row(
                  children: [
                    if (_canFixLastReply)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: MinimalChipButton(
                          label: 'Fix last',
                          icon: Icons.edit_note,
                          selected: _fixLastReplyMode,
                          onPressed: busy
                              ? null
                              : () => setState(
                                  () => _fixLastReplyMode = !_fixLastReplyMode,
                                ),
                        ),
                      ),
                    Expanded(
                      child: ChatComposerField(
                        key: const ValueKey('workshop_composer'),
                        controller: _input,
                        focusNode: _composerFocusNode,
                        enabled: !busy,
                        enterToSend: _enterToSend,
                        decoration: InputDecoration(
                          hintText: _fixLastReplyMode && _canFixLastReply
                              ? 'Correction for last reply…'
                              : _needsWorkshopReply
                              ? 'Tap ▶ Continue for a workshop reply…'
                              : 'Describe your world…',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        onSend: _send,
                        onContinue: _enterToSend ? _onComposerContinue : null,
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (!_sending)
                      IconButton(
                        tooltip: _needsWorkshopReply
                            ? 'Continue — generate reply to your message'
                            : 'Continue — generate the next workshop reply',
                        visualDensity: VisualDensity.compact,
                        onPressed: _canContinueWorkshop
                            ? _continueWorkshop
                            : null,
                        icon: const Icon(Icons.play_arrow),
                      ),
                    if (_sending)
                      FilledButton(
                        onPressed: _stopGeneration,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.all(14),
                          minimumSize: const Size(48, 48),
                          backgroundColor: colorScheme.error,
                          foregroundColor: colorScheme.onError,
                        ),
                        child: const Icon(Icons.stop),
                      )
                    else
                      IconButton.filled(
                        onPressed: _exporting ? null : _send,
                        icon: const Icon(Icons.send),
                        tooltip: 'Send',
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
