import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/anima_presets.dart';
import '../models/character.dart';
import '../models/chat_message.dart';
import '../models/chat_session.dart';
import '../models/persona.dart';
import '../models/lorebook.dart';
import '../models/ui_style_settings.dart';
import '../services/api_key_service.dart';
import '../services/appearance_controller.dart';
import '../services/authors_note_composer.dart';
import '../services/chat_background_service.dart';
import '../services/character_category_service.dart';
import '../services/character_guide_service.dart';
import '../services/character_service.dart';
import '../services/character_token_service.dart';
import '../services/chat_context_service.dart';
import '../services/chat_service.dart';
import '../services/chat_session_resolver.dart';
import '../models/field_wand_options.dart';
import '../services/field_wand_context_builder.dart';
import '../services/chat_transcript_codec.dart';
import '../services/composer_draft_service.dart';
import '../models/group_beat_part.dart';
import '../services/group_beat_codec.dart';
import '../services/group_reply_service.dart';
import '../services/group_speaker_inference.dart';
import '../services/lorebook_service.dart';
import '../services/presence_service.dart';
import '../services/director_service.dart';
import '../services/narrator_service.dart';
import '../services/nanogpt_service.dart';
import '../services/persona_service.dart';
import '../services/prompt_builder.dart';
import '../services/roadway_cache_service.dart';
import '../services/roadway_service.dart';
import '../services/reply_rewrite_service.dart';
import '../services/settings_service.dart';
import '../services/speaker_prefix.dart';
import '../services/world_info_service.dart';
import '../models/world_workshop.dart';
import '../models/workshop_chat_import_options.dart';
import '../services/world_workshop_service.dart';
import '../utils/platform_utils.dart';
import '../utils/scroll_to_end.dart';
import '../utils/text_punctuation.dart';
import '../utils/composer_markup.dart';
import '../widgets/chat_composer_field.dart';
import '../widgets/chat_composer_tools_sheet.dart';
import '../widgets/chat_lorebook_picker.dart';
import '../widgets/chat_overrides_sheet.dart';
import '../widgets/chat_hero_portrait.dart';
import '../widgets/chat_image_background.dart';
import '../widgets/create_character_from_chat_sheet.dart';
import '../widgets/temporary_character_sheet.dart';
import '../widgets/update_character_from_chat_sheet.dart';
import '../widgets/anima_avatar.dart';
import '../widgets/greeting_picker.dart';
import '../widgets/group_beat_bubble.dart';
import '../widgets/group_beat_edit_sheet.dart';
import '../widgets/group_reply_sheet.dart';
import '../widgets/keyboard_inset.dart';
import '../widgets/minimal_chip_button.dart';
import '../widgets/narrator_bubble.dart';
import '../widgets/narrator_sheet.dart';
import '../widgets/preset_picker.dart';
import '../widgets/quick_api_connection_sheet.dart';
import '../widgets/reply_rewrite_sheet.dart';
import '../widgets/rp_rich_text.dart';
import '../widgets/memory_summary_sheet.dart';
import '../widgets/scene_mood_sheet.dart';
import 'characters_screen.dart';
import 'character_edit_screen.dart';
import 'group_chat_setup_screen.dart';
import 'lorebook_edit_screen.dart';
import 'persona_edit_screen.dart';
import 'personas_screen.dart';
import '../services/world_workshop_builder.dart';
import 'settings_screen.dart';
import 'world_workshop_chat_screen.dart';

/// Main chat screen with saved history, streaming, and SillyTavern-like controls.
class ChatScreen extends StatefulWidget {
  const ChatScreen({
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
    required this.initialSession,
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
  final ChatSession initialSession;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final _inputController = TextEditingController();
  FocusNode? _composerFocusNode;
  final _scrollController = ScrollController();
  final _promptBuilder = const PromptBuilder();
  final _lorebookService = const LorebookService();
  final _contextService = const ChatContextService();
  static const _tokenService = CharacterTokenService();
  final _transcriptCodec = ChatTranscriptCodec();
  final _draftService = ComposerDraftService();
  static const _replyRewrite = ReplyRewriteService();
  static const _narrator = NarratorService();
  static const _director = DirectorService();
  static const _characterGuide = CharacterGuideService();
  static const _presence = PresenceService();
  static const _groupReply = GroupReplyService();
  static const _groupSpeakerInference = GroupSpeakerInference();
  static const _sessionResolver = ChatSessionResolver();
  final _workshopBuilder = WorldWorkshopBuilder();

  Character _resolvedGroupSpeaker({Character? explicit}) {
    if (explicit != null) return explicit;
    if (!_isGroup || _participants.isEmpty) return _character!;
    if (!(_session?.autoReply ?? false)) {
      return _groupSpeakerInference.resolve(
        participants: _participants,
        messages: _messages,
        primaryCharacter: _character,
      );
    }
    return _speakerForTurn();
  }

  bool get _shouldAdvanceGroupSpeaker =>
      _isGroup && (_session?.autoReply ?? false);

  List<FieldWandExternalSource> _chatWandSources() {
    final session = _session;
    if (session == null) return const [];
    final title = session.title.trim();
    final source = FieldWandContextBuilder(_workshopBuilder).chatSource(
      messages: _messages,
      chatTitle: title.isNotEmpty
          ? title
          : (_character?.name.trim().isNotEmpty == true
              ? _character!.name.trim()
              : 'Chat'),
    );
    if (source == null) return const [];
    return [source];
  }

  void _refocusComposer() {
    if (!isDesktopPlatform || _composerFocusNode == null) return;
    if (!mounted || _busy) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _busy) return;
      final node = _composerFocusNode;
      if (node == null || node.hasFocus || !node.canRequestFocus) return;
      node.requestFocus();
    });
  }

  void _dismissComposerKeyboard() {
    if (isDesktopPlatform) return;
    FocusManager.instance.primaryFocus?.unfocus();
  }

  void _onComposerContinue() {
    if (_busy) return;
    unawaited(_continueScene());
  }

  bool _hasApiKey = false;
  bool _loading = true;
  bool _busy = false;
  bool _summarizing = false;
  int _summarizeGeneration = 0;
  bool _enterToSend = false;
  bool _autoWrapDialogueOnSend = false;

  /// When on, Send posts a Director note that commands the next AI reply.
  bool _directorMode = false;

  /// When set, the composer writes a manual character line (assistant bubble).
  String? _composerVoiceCharacterId;

  /// When a character voice is active: false = type their line; true = guide AI.
  bool _composerVoiceGuideMode = false;
  AvatarStyleSettings _avatarStyle = const AvatarStyleSettings();
  String? _chatBackgroundPath;
  String? _resolvedBackgroundFileName;
  final _chatBackgroundService = ChatBackgroundService();
  String? _error;
  Character? _character;
  List<Character> _participants = const [];
  ChatSession? _session;
  Persona? _persona;
  Timer? _draftSaveTimer;
  Timer? _toastTimer;
  OverlayEntry? _toastEntry;
  String _lastSavedDraft = '';

  List<ChatMessage> get _messages => _session?.messages ?? const [];
  bool get _isGroup => _session?.isGroup == true;
  String get _userName => _persona?.name.trim().isNotEmpty == true
      ? _persona!.name.trim()
      : SettingsService.defaultUserName;
  String? get _personaAvatarFileName => _persona?.avatarFileName;

  @override
  void initState() {
    super.initState();
    _composerFocusNode = FocusNode();
    WidgetsBinding.instance.addObserver(this);
    _inputController.addListener(_onComposerChanged);
    _bootstrap();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      _flushDraftNow();
    }
  }

  void _onComposerChanged() {
    _draftSaveTimer?.cancel();
    _draftSaveTimer = Timer(const Duration(milliseconds: 450), _flushDraftNow);
  }

  Future<void> _flushDraftNow() async {
    _draftSaveTimer?.cancel();
    _draftSaveTimer = null;
    final session = _session;
    if (session == null) return;
    final text = _inputController.text;
    if (text == _lastSavedDraft) return;
    _lastSavedDraft = text;
    await _draftService.saveDraft(_composerDraftKey(session.id), text);
  }

  String _composerDraftKey(String chatId) {
    final voice = _composerVoiceCharacterId?.trim();
    if (voice == null || voice.isEmpty) return chatId;
    return '$chatId::voice::$voice';
  }

  Character? _characterById(String id) {
    final trimmed = id.trim();
    if (trimmed.isEmpty) return null;
    for (final c in _participants) {
      if (c.id == trimmed) return c;
    }
    if (_character?.id == trimmed) return _character;
    return null;
  }

  Character? get _composerVoiceCharacter {
    final id = _composerVoiceCharacterId;
    if (id == null || id.trim().isEmpty) return null;
    return _characterById(id);
  }

  Future<void> _setComposerVoice(String? characterId) async {
    if (_busy) return;
    final session = _session;
    if (session == null) return;
    final nextId = characterId?.trim();
    if (nextId == _composerVoiceCharacterId) {
      _composerFocusNode?.requestFocus();
      return;
    }

    await _flushDraftNow();
    if (!mounted) return;

    setState(() {
      _composerVoiceCharacterId =
          (nextId == null || nextId.isEmpty) ? null : nextId;
      if (_composerVoiceCharacterId != null) {
        _directorMode = false;
      } else {
        _composerVoiceGuideMode = false;
      }
    });

    final draft = await _draftService.loadDraft(_composerDraftKey(session.id));
    if (!mounted) return;
    _inputController.text = draft;
    _inputController.selection = TextSelection.collapsed(offset: draft.length);
    _lastSavedDraft = draft;
    _composerFocusNode?.requestFocus();
    final voice = _composerVoiceCharacter;
    if (voice != null) {
      final name = voice.name.trim().isEmpty ? 'character' : voice.name.trim();
      _showLocalToast(
        _composerVoiceGuideMode
            ? 'Guiding $name — type what they should do, then send'
            : 'Writing as $name — tap You to switch back',
      );
    }
  }

  Future<void> _clearSavedDraft() async {
    _draftSaveTimer?.cancel();
    _draftSaveTimer = null;
    _lastSavedDraft = '';
    final session = _session;
    if (session == null) return;
    await _draftService.clearDraft(_composerDraftKey(session.id));
  }

  Future<void> _bootstrap() async {
    final hasKey = await widget.apiKeyService.hasApiKey();
    var session = widget.initialSession;
    await widget.chatService.setActiveChatId(session.characterId, session.id);
    final character = await _resolveCharacterForSession(session);
    final uiStyle = await widget.settingsService.getUiStyle();
    final enterToSend = await widget.settingsService.getEnterToSendComposer();
    final autoWrapDialogue =
        await widget.settingsService.getAutoWrapDialogueOnSend();
    var persona = await widget.personaService.resolve(session.personaId);
    if (session.personaId == null) {
      final savedDefault = await widget.personaService.tryGetActivePersona();
      if (savedDefault != null) {
        session = session.copyWith(personaId: savedDefault.id);
        persona = savedDefault;
        await widget.chatService.saveChat(session);
      }
    }
    final participants = await _resolveParticipants(session, character);
    persona = _resolvePersonaForSession(session, persona) ?? persona;
    final draft = await _draftService.loadDraft(session.id);
    if (!mounted) return;
    if (draft.isNotEmpty) {
      _inputController.text = draft;
      _inputController.selection = TextSelection.collapsed(
        offset: draft.length,
      );
      _lastSavedDraft = draft;
    }
    setState(() {
      _hasApiKey = hasKey;
      _character = character;
      _participants = participants;
      _session = session;
      _avatarStyle = uiStyle.avatarStyle;
      _persona = persona;
      _enterToSend = enterToSend;
      _autoWrapDialogueOnSend = autoWrapDialogue;
      _loading = false;
    });
    _scrollToBottom(jump: true);
    unawaited(_syncChatBackgroundPath());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    unawaited(_syncChatBackgroundPath());
  }

  Future<void> _syncChatBackgroundPath() async {
    final exp = AnimaUiTheme.of(context).chatExperience;
    final fileName = exp.backgroundEnabled && exp.hasBackgroundImage
        ? exp.backgroundImageFileName
        : null;
    if (fileName == _resolvedBackgroundFileName) return;
    _resolvedBackgroundFileName = fileName;
    final path =
        fileName != null ? await _chatBackgroundService.resolvePath(fileName) : null;
    if (!mounted) return;
    if (path != _chatBackgroundPath) {
      setState(() => _chatBackgroundPath = path);
    }
  }

  Future<Character> _resolveCharacterForSession(ChatSession session) async {
    if (session.isGroup) {
      final all = await widget.characterService.loadCharacters();
      final byId = {for (final c in all) c.id: c};
      for (final id in session.effectiveParticipantIds) {
        final match = byId[id];
        if (match != null) return match;
      }
      return _resolveSelectedCharacter();
    }
    final solo = await widget.characterService.getById(session.characterId);
    return solo ?? _resolveSelectedCharacter();
  }

  Future<List<Character>> _resolveParticipants(
    ChatSession session,
    Character fallback,
  ) async {
    if (!session.isGroup) {
      final solo = await widget.characterService.getById(session.characterId);
      final base = solo ?? fallback;
      return [_sessionResolver.resolveCharacter(base, session)];
    }
    final all = await widget.characterService.loadCharacters();
    final byId = {for (final c in all) c.id: c};
    final resolved = <Character>[];
    for (final id in session.effectiveParticipantIds) {
      final c = byId[id];
      if (c != null) {
        resolved.add(_sessionResolver.resolveCharacter(c, session));
      }
    }
    return resolved.isEmpty
        ? [_sessionResolver.resolveCharacter(fallback, session)]
        : resolved;
  }

  Future<List<Lorebook>> _lorebooksForSession(ChatSession? session) async {
    final global = await widget.worldInfoService.booksForChat(
      chatLorebookIds: session?.lorebookIds,
    );
    if (session == null) return global;
    return [...global, ..._sessionResolver.chatLorebooks(session)];
  }

  Persona? _resolvePersonaForSession(ChatSession session, Persona? library) {
    return _sessionResolver.resolvePersona(library, session);
  }

  Future<void> _refreshCastFromSession(ChatSession session) async {
    final fallback = _character ?? await _resolveCharacterForSession(session);
    final participants = await _resolveParticipants(session, fallback);
    final primary = session.isGroup
        ? (participants.isNotEmpty ? participants.first : fallback)
        : (participants.isNotEmpty ? participants.first : fallback);
    var persona = await widget.personaService.resolve(session.personaId);
    persona = _resolvePersonaForSession(session, persona) ?? persona;
    if (!mounted) return;
    setState(() {
      _session = session;
      _character = primary;
      _participants = participants;
      _persona = persona;
    });
  }

  void _setCharacterOverride(Character character) {
    final session = _session;
    if (session == null) return;
    final overrides = Map<String, Character>.from(session.characterOverrides)
      ..[character.id] = character;
    final updated = session.copyWith(characterOverrides: overrides);
    unawaited(_persistSessionAndRefreshCast(updated));
  }

  void _setPersonaOverride(Persona persona) {
    final session = _session;
    if (session == null) return;
    final updated = session.copyWith(personaOverride: persona);
    unawaited(_persistSessionAndRefreshCast(updated));
  }

  Future<void> _persistSessionAndRefreshCast(ChatSession session) async {
    await widget.chatService.saveChat(session);
    if (!mounted) return;
    await _refreshCastFromSession(session);
  }

  Character _speakerForTurn() {
    final session = _session;
    if (session == null || !_isGroup || _participants.isEmpty) {
      return _character!;
    }
    final index = session.nextSpeakerIndex.clamp(0, _participants.length - 1);
    return _participants[index];
  }

  void _advanceGroupSpeaker() {
    final session = _session;
    if (session == null || !_isGroup || _participants.length < 2) return;
    final next = (session.nextSpeakerIndex + 1) % _participants.length;
    _session = session.copyWith(nextSpeakerIndex: next);
  }

  Future<Character> _resolveSelectedCharacter() async {
    final characters = await widget.characterService.loadCharacters();
    if (characters.isEmpty) {
      final session = _session;
      if (session != null && !session.isGroup) {
        final solo = await widget.characterService.getById(session.characterId);
        if (solo != null) return solo;
        return Character(
          id: session.characterId,
          name: session.title.trim().isNotEmpty ? session.title : 'Character',
        );
      }
      return const Character(id: 'char_missing', name: 'Character');
    }
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

  String? _avatarForMessage(ChatMessage message) {
    if (message.isUser) return _personaAvatarFileName;
    final speakerId = message.speakerId;
    if (speakerId != null && speakerId.isNotEmpty) {
      for (final c in _participants) {
        if (c.id == speakerId) return c.avatarFileName;
      }
    }
    return _character?.avatarFileName;
  }

  String? _avatarForParticipantId(String speakerId) {
    if (speakerId.isEmpty) return null;
    for (final c in _participants) {
      if (c.id == speakerId) return c.avatarFileName;
    }
    return null;
  }

  List<GroupBeatPart> _partsFromBeatLines(List<GroupBeatLine> beats) {
    return beats
        .map((beat) {
          final name = beat.character.name.trim();
          return GroupBeatPart(
            speakerId: beat.character.id,
            speakerName: name,
            text: stripLeadingSpeakerPrefix(beat.text, name),
          );
        })
        .toList(growable: false);
  }

  List<Character> _resolveGroupBeatSpeakers(List<GroupBeatPart> lines) {
    final out = <Character>[];
    final seen = <String>{};

    void add(Character character) {
      if (seen.contains(character.id)) return;
      seen.add(character.id);
      out.add(character);
    }

    for (final line in lines) {
      final name = line.speakerName.trim();
      final speakerId = line.speakerId.trim();
      Character? match;

      if (speakerId.isNotEmpty) {
        for (final c in _participants) {
          if (c.id == speakerId) {
            match = c;
            break;
          }
        }
      }

      if (match == null && name.isNotEmpty) {
        final lower = name.toLowerCase();
        for (final c in _participants) {
          if (c.name.trim().toLowerCase() == lower) {
            match = c;
            break;
          }
        }
      }

      if (match != null) {
        add(match);
      } else if (name.isNotEmpty) {
        add(
          Character(
            id: speakerId.isNotEmpty ? speakerId : 'beat_${_lowerName(name)}',
            name: name,
          ),
        );
      }
    }

    if (out.length >= 2) return out;

    // Beat lines may be stale after cast edits — fall back to the live group cast.
    if (_participants.length >= 2) {
      return List<Character>.from(_participants);
    }

    return out;
  }

  String _lowerName(String name) =>
      name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');

  ChatMessage _applyGroupBeatParts(ChatMessage message, List<GroupBeatPart> parts) {
    if (parts.isEmpty || message.beatSwipes == null) return message;
    final variants = List<List<GroupBeatPart>>.from(message.beatSwipes!);
    final idx = message.swipeIndex.clamp(0, variants.length - 1);
    variants[idx] = parts;
    return ChatMessage.groupBeat(
      id: message.id,
      lines: parts,
      beatSwipes: variants,
      swipeIndex: idx,
    );
  }

  Future<void> _persist() async {
    final session = _session;
    if (session == null) return;
    await widget.chatService.saveChat(session);
  }

  /// Errors stay in the chat banner (above the composer) — never a bottom toast.
  void _showChatError(String message) {
    if (!mounted) return;
    setState(() => _error = message);
  }

  void _showLocalToast(String message) {
    if (!mounted) return;
    _toastTimer?.cancel();
    _toastEntry?.remove();

    final entry = OverlayEntry(
      builder: (context) => IgnorePointer(
        child: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHigh.withValues(alpha: 0.96),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.45),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: 0.12),
                      blurRadius: 18,
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 11,
                  ),
                  child: Text(
                    message,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    _toastEntry = entry;
    Overlay.of(context).insert(entry);
    _toastTimer = Timer(const Duration(seconds: 2), () {
      if (_toastEntry == entry) _toastEntry = null;
      entry.remove();
    });
  }

  Future<void> _openQuickApi() async {
    final saved = await showQuickApiConnectionSheet(
      context: context,
      apiKeyService: widget.apiKeyService,
      settingsService: widget.settingsService,
      nanoGptService: widget.nanoGptService,
    );
    if (!mounted || saved != true) return;
    final model = await widget.settingsService.getModel();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Chat model switched to $model')),
    );
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
    final hasKey = await widget.apiKeyService.hasApiKey();
    final uiStyle = await widget.settingsService.getUiStyle();
    final persona = await widget.personaService.resolve(_session?.personaId);
    if (!mounted) return;
    setState(() {
      _hasApiKey = hasKey;
      _avatarStyle = uiStyle.avatarStyle;
      _persona = persona;
    });
  }

  Future<void> _openCreationCenter() async {
    if (_session == null) return;
    final wsId = _session!.sourceWorkshopId;
    if (wsId != null && wsId.isNotEmpty) {
      final workshop = await widget.worldWorkshopService.getById(wsId);
      if (workshop != null && mounted) {
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
        return;
      }
    }

    final builder = WorldWorkshopBuilder();
    final contextSettings =
        await widget.settingsService.getContextSettings();
    final source = builder.buildImportedChatSource(
      session: _session!,
      characters: _participants,
      persona: _persona,
      options: WorkshopChatImportOptions(
        keepRecent: contextSettings.summarizeKeepRecent,
        includeRecentMessages: true,
        includeMemorySummary: _session!.memorySummary.trim().isNotEmpty,
        includeCharacters: true,
        includePersona: _persona != null,
        includeGlobalLorebooks: false,
        includeEmbeddedCharacterLore: false,
        includeAuthorsNote: AuthorsNoteComposer.hasEffectiveNote(
          manualAuthorsNote: _session!.authorsNote,
          activeSceneMoodIds: _session!.activeSceneMoodIds,
        ),
      ),
    );
    if (!source.hasContent) {
      _showChatError('This chat has no content to import yet.');
      return;
    }
    final workshop = await widget.worldWorkshopService.upsert(
      WorldWorkshop.empty(title: 'From: ${_session!.title}').copyWith(
        importedSource: source,
      ),
    );
    if (!mounted) return;
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
  }

  Future<void> _pickPersona() async {
    if (_busy || _session == null) return;
    final chosen = await Navigator.of(context).push<Persona>(
      MaterialPageRoute(
        builder: (_) => PersonasScreen(
          personaService: widget.personaService,
          settingsService: widget.settingsService,
          nanoGptService: widget.nanoGptService,
          pickForChat: true,
          selectedPersonaId: _session?.personaId ?? _persona?.id,
        ),
      ),
    );
    if (chosen == null || !mounted) return;
    final updated = _session!.copyWith(
      personaId: chosen.sessionId,
      clearPersonaOverride: true,
    );
    await widget.chatService.saveChat(updated);
    if (!mounted) return;
    setState(() {
      _session = updated;
      _persona = chosen;
    });
  }

  /// Tap an AI avatar → edit that character card; changes apply on the next reply.
  Future<void> _editCharacterFromAvatar(ChatMessage message) async {
    if (_busy || message.isUser) return;

    Character? target;
    final speakerId = message.speakerId?.trim();
    if (speakerId != null && speakerId.isNotEmpty) {
      for (final c in _participants) {
        if (c.id == speakerId) {
          target = c;
          break;
        }
      }
      target ??= await widget.characterService.getById(speakerId);
    }
    target ??= _character;
    if (target == null || !mounted) return;

    final updated = await Navigator.of(context).push<Character>(
      MaterialPageRoute(
        builder: (_) => CharacterEditScreen(
          characterService: widget.characterService,
          settingsService: widget.settingsService,
          nanoGptService: widget.nanoGptService,
          existing: target,
          persistToLibrary: false,
          wandExternalSources: _chatWandSources(),
        ),
      ),
    );
    if (updated == null || !mounted) return;

    _setCharacterOverride(updated);
  }

  /// Tap your avatar → edit this chat’s persona copy.
  Future<void> _editPersonaFromAvatar() async {
    if (_busy) return;
    final persona = _persona;
    if (persona == null) return;

    final updated = await Navigator.of(context).push<Persona>(
      MaterialPageRoute(
        builder: (_) => PersonaEditScreen(
          personaService: widget.personaService,
          settingsService: widget.settingsService,
          nanoGptService: widget.nanoGptService,
          existing: persona,
          persistToLibrary: false,
          wandExternalSources: _chatWandSources(),
        ),
      ),
    );
    if (updated == null || !mounted) return;

    _setPersonaOverride(updated);
  }

  Future<void> _openCharacters() async {
    final previousId = _character?.id;
    final selected = await Navigator.of(context).push<Character>(
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

    final character = selected ?? await _resolveSelectedCharacter();
    if (!mounted) return;

    if (previousId == character.id && !_isGroup) {
      // Character may have been edited (greeting / prompt). Refresh object only.
      setState(() {
        _character = character;
        _participants = [character];
      });
      return;
    }

    final session = await widget.chatService.loadOrCreateActiveChat(
      character,
      userName: _userName,
      personaId: _persona?.sessionId,
    );
    final participants = await _resolveParticipants(session, character);
    if (!mounted) return;
    await _flushDraftNow();
    await _applySession(
      session,
      participants: participants,
      character: character,
    );
  }

  Future<void> _newChat() async {
    final character = _character;
    if (character == null || _busy) return;
    await _flushDraftNow();
    if (!mounted) return;
    if (_isGroup) {
      final greetingIndex = await pickGreetingIndex(
        context,
        character: _participants.isNotEmpty ? _participants.first : character,
        userName: _userName,
      );
      if (greetingIndex == null || !mounted) return;
      final session = await widget.chatService.startGroupChat(
        _participants,
        userName: _userName,
        personaId: _persona?.sessionId,
        authorsNote: _effectiveAuthorsNote(),
        activeSceneMoodIds: _session?.activeSceneMoodIds ?? const [],
        autoReply: _session?.autoReply ?? false,
        lorebookIds: _session?.lorebookIds,
        greetingIndex: greetingIndex,
      );
      if (!mounted) return;
      await _applySession(session, participants: _participants);
      return;
    }
    if (!mounted) return;
    final greetingIndex = await pickGreetingIndex(
      context,
      character: character,
      userName: _userName,
    );
    if (greetingIndex == null || !mounted) return;
    final session = await widget.chatService.startNewChat(
      character,
      userName: _userName,
      personaId: _persona?.sessionId,
      greetingIndex: greetingIndex,
    );
    if (!mounted) return;
    await _applySession(session, participants: [character]);
  }

  /// Swap to another saved chat (or a brand-new one) and restore its draft.
  Future<void> _applySession(
    ChatSession session, {
    List<Character>? participants,
    Character? character,
  }) async {
    await _flushDraftNow();
    if (!mounted) return;
    setState(() {
      _composerVoiceCharacterId = null;
      _composerVoiceGuideMode = false;
      if (character != null) _character = character;
      if (participants != null) _participants = participants;
      _session = session;
      _error = null;
    });
    final draft = await _draftService.loadDraft(session.id);
    if (!mounted) return;
    _inputController.text = draft;
    _inputController.selection = TextSelection.collapsed(offset: draft.length);
    _lastSavedDraft = draft;
    _scrollToBottom(jump: true);
    unawaited(_syncChatBackgroundPath());
  }

  Future<void> _exportChat() async {
    final session = _session;
    final character = _character;
    if (session == null || character == null || _busy) return;
    if (session.messages.isEmpty) {
      _showChatError('Nothing to export yet.');
      return;
    }

    final format = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: .min,
          children: [
            ListTile(
              title: const Text('Export as Anima JSON'),
              subtitle: const Text('Keeps swipes — best for re-import'),
              onTap: () => Navigator.pop(context, 'json'),
            ),
            ListTile(
              title: const Text('Export as plain text'),
              subtitle: const Text('Easy to read or share'),
              onTap: () => Navigator.pop(context, 'txt'),
            ),
          ],
        ),
      ),
    );
    if (format == null || !mounted) return;

    try {
      final userName = _userName;
      final body = format == 'txt'
          ? _transcriptCodec.toPlainText(
              session,
              character: character,
              userName: userName,
            )
          : _transcriptCodec.toJson(session, character: character);

      final dir = await getTemporaryDirectory();
      final safe = character.name
          .replaceAll(RegExp(r'[^\w\-]+'), '_')
          .replaceAll(RegExp(r'_+'), '_');
      final ext = format == 'txt' ? 'txt' : 'json';
      final file = File(
        '${dir.path}/${safe.isEmpty ? 'chat' : safe}_chat.$ext',
      );
      await file.writeAsString(body);

      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile(
              file.path,
              mimeType: format == 'txt' ? 'text/plain' : 'application/json',
            ),
          ],
          subject: '${character.name} chat',
          text: 'Anima chat transcript',
        ),
      );
    } catch (error) {
      _showChatError('Export failed: $error');
    }
  }

  Future<void> _importChat() async {
    final character = _character;
    if (character == null || _busy) return;

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json', 'txt'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      final bytes =
          file.bytes ??
          (file.path != null ? await File(file.path!).readAsBytes() : null);
      if (bytes == null) {
        _showChatError('Could not read that file.');
        return;
      }

      final userName = _userName;
      final imported = _transcriptCodec.parseBytes(
        bytes,
        characterId: character.id,
        characterName: character.name,
        userName: userName,
      );

      final withPersona = imported.copyWith(personaId: _persona?.sessionId);
      await widget.chatService.saveChat(withPersona);
      await widget.chatService.setActiveChatId(character.id, withPersona.id);
      if (!mounted) return;
      setState(() {
        _session = withPersona;
        _error = null;
      });
      _scrollToBottom(jump: true);
    } on FormatException catch (error) {
      _showChatError(error.message);
    } catch (error) {
      _showChatError('Import failed: $error');
    }
  }

  Future<void> _send() async {
    var text = normalizeEmDashes(_inputController.text.trim());
    if (text.isEmpty ||
        _busy ||
        _session == null ||
        _character == null) {
      return;
    }

    if (_autoWrapDialogueOnSend &&
        !_directorMode &&
        !(_composerVoiceCharacterId != null && _composerVoiceGuideMode)) {
      text = autoWrapDialogue(text);
    }

    if (_directorMode) {
      if (!_hasApiKey) {
        setState(() {
          _error = 'Add your NanoGPT API key in Settings before you can chat.';
        });
        return;
      }
      await _sendDirectorNote(text);
      return;
    }

    if (_composerVoiceCharacterId != null) {
      if (_composerVoiceGuideMode) {
        await _sendCharacterGuide(text);
      } else {
        await _sendManualCharacterLine(text);
      }
      return;
    }

    if (!_hasApiKey) {
      setState(() {
        _error = 'Add your NanoGPT API key in Settings before you can chat.';
      });
      return;
    }

    _inputController.clear();
    await _clearSavedDraft();
    _dismissComposerKeyboard();

    final autoReply = _session!.autoReply;
    final speaker = _resolvedGroupSpeaker();
    final userMessage = ChatMessage(
      id: ChatMessage.newId(),
      role: ChatRole.user,
      text: text,
    );

    setState(() {
      _error = null;
      var session = _session!;
      session.messages.add(userMessage);
      _session = session.copyWith(clearPendingDirector: true);
      if (autoReply) {
        _busy = true;
        _session!.messages.add(
          ChatMessage(
            id: ChatMessage.newId(),
            role: ChatRole.assistant,
            text: '',
            swipes: const [''],
            swipeIndex: 0,
            speakerId: speaker.id,
            speakerName: speaker.name,
          ),
        );
      }
    });
    _scrollToBottom(jump: true);
    await _persist();
    if (!autoReply) {
      _refocusComposer();
      return;
    }

    await _streamIntoLastAssistant(
      excludeLastAssistant: true,
      speakingAs: speaker,
      advanceGroupSpeaker: _shouldAdvanceGroupSpeaker,
    );
  }

  Future<void> _sendManualCharacterLine(String text) async {
    final speaker = _composerVoiceCharacter;
    if (speaker == null) {
      await _setComposerVoice(null);
      return;
    }

    _inputController.clear();
    await _clearSavedDraft();
    _dismissComposerKeyboard();

    final message = ChatMessage(
      id: ChatMessage.newId(),
      role: ChatRole.assistant,
      text: text,
      swipes: [text],
      swipeIndex: 0,
      speakerId: speaker.id,
      speakerName: speaker.name,
    );

    setState(() {
      _error = null;
      var session = _session!;
      session.messages.add(message);
      final speakerIndex =
          _participants.indexWhere((c) => c.id == speaker.id);
      _session = session.copyWith(
        clearPendingDirector: true,
        nextSpeakerIndex: speakerIndex >= 0
            ? speakerIndex
            : session.nextSpeakerIndex,
      );
    });
    _scrollToBottom(jump: true);
    await _persist();
    unawaited(_maybeAutoSummarize());
    _refocusComposer();
  }

  Future<void> _sendCharacterGuide(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    final speaker = _composerVoiceCharacter;
    if (speaker == null) {
      await _setComposerVoice(null);
      return;
    }

    if (!_hasApiKey) {
      setState(() {
        _error = 'Add your NanoGPT API key in Settings before you can chat.';
      });
      return;
    }

    _inputController.clear();
    await _clearSavedDraft();
    _dismissComposerKeyboard();

    final assistantId = ChatMessage.newId();
    setState(() {
      _error = null;
      _busy = true;
      var session = _session!;
      session.messages.add(
        ChatMessage(
          id: assistantId,
          role: ChatRole.assistant,
          text: '',
          swipes: const [''],
          swipeIndex: 0,
          speakerId: speaker.id,
          speakerName: speaker.name,
        ),
      );
      final speakerIndex =
          _participants.indexWhere((c) => c.id == speaker.id);
      _session = session.copyWith(
        clearPendingDirector: true,
        nextSpeakerIndex: speakerIndex >= 0
            ? speakerIndex
            : session.nextSpeakerIndex,
      );
    });
    _scrollToBottom(jump: true);
    await _persist();

    final guideMessages = _characterGuide.buildGuideMessages(
      instruction: trimmed,
      characterName: speaker.name,
      userName: _userName,
    );

    final assistantIndex =
        _session!.messages.indexWhere((m) => m.id == assistantId);
    if (assistantIndex < 0) {
      setState(() => _busy = false);
      return;
    }

    await _streamAssistantReply(
      assistantIndex: assistantIndex,
      excludeLastAssistant: true,
      allowGreetingNudge: false,
      speakingAs: speaker,
      advanceGroupSpeaker: false,
      rewriteMessages: guideMessages,
    );
  }

  Future<void> _sendDirectorNote(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    _inputController.clear();
    await _clearSavedDraft();
    _dismissComposerKeyboard();

    final autoReply = _session!.autoReply;
    final speaker = _resolvedGroupSpeaker();
    final directorId = ChatMessage.newId();
    final assistantId = ChatMessage.newId();
    final directorMessage = ChatMessage(
      id: directorId,
      role: ChatRole.director,
      text: trimmed,
    );

    setState(() {
      _error = null;
      var session = _session!;
      session.messages.add(directorMessage);
      _session = session.copyWith(
        pendingDirectorMessageId: directorId,
        pendingDirectorAssistantId: autoReply ? assistantId : null,
        clearPendingDirectorAssistant: !autoReply,
      );
      if (autoReply) {
        _busy = true;
        _session!.messages.add(
          ChatMessage(
            id: assistantId,
            role: ChatRole.assistant,
            text: '',
            swipes: const [''],
            swipeIndex: 0,
            speakerId: speaker.id,
            speakerName: speaker.name,
          ),
        );
      }
    });
    _scrollToBottom(jump: true);
    await _persist();
    if (!autoReply) {
      _refocusComposer();
      return;
    }

    await _streamIntoLastAssistant(
      excludeLastAssistant: true,
      speakingAs: speaker,
      advanceGroupSpeaker: _shouldAdvanceGroupSpeaker,
    );
  }

  ChatSession _sessionAfterMessageListChange(List<ChatMessage> messages) {
    final session = _session!;
    final pendingId = _director.reconcilePendingId(
      messages,
      session.pendingDirectorMessageId,
    );
    var assistantId = session.pendingDirectorAssistantId;
    if (assistantId != null &&
        !messages.any((message) => message.id == assistantId)) {
      assistantId = null;
    }
    if (pendingId == null) {
      return session.copyWith(
        messages: messages,
        clearPendingDirector: true,
      );
    }
    return session.copyWith(
      messages: messages,
      pendingDirectorMessageId: pendingId,
      pendingDirectorAssistantId: assistantId,
      clearPendingDirectorAssistant: assistantId == null,
    );
  }

  void _bindPendingDirectorToAssistant(String assistantId) {
    final session = _session;
    if (session == null) return;
    if (session.pendingDirectorMessageId == null) return;
    if (session.pendingDirectorAssistantId != null) return;
    _session = session.copyWith(pendingDirectorAssistantId: assistantId);
  }

  String? _directorBlockForGeneration({
    required Character character,
    required PromptMode mode,
    bool groupBeat = false,
    String? targetAssistantId,
  }) {
    if (mode == PromptMode.impersonate || _session == null) return null;
    final session = _session!;
    final text = _director.pendingText(session);
    if (text == null) return null;
    final bound = session.pendingDirectorAssistantId;
    if (bound != null &&
        targetAssistantId != null &&
        bound != targetAssistantId) {
      return null;
    }
    final sanitized = _presence.sanitizeStagingTextForCharacter(
      text: text,
      focusCharacterName: character.name,
      castNames: _participants.map((c) => c.name),
    );
    if (sanitized.trim().isEmpty) return null;
    return _director.formatActiveInstruction(
      text: sanitized,
      charName: character.name,
      userName: _userName,
      isGroup: _isGroup,
      groupBeat: groupBeat,
    );
  }

  String? _narratorActiveBlock({
    required String charName,
    required int endExclusive,
    String speakingAsName = '',
    int? excludeMessageIndex,
  }) {
    final activeId = _narrator.latestNarratorId(
      _messages,
      endExclusive: endExclusive,
    );
    final speaker = speakingAsName.isNotEmpty ? speakingAsName : charName;
    final sceneSnapshot = _isGroup
        ? _presence.sceneSnapshotFromLatestNarrator(
            messages: _messages,
            participants: _participants,
            userName: _userName,
            endExclusive: endExclusive,
          )
        : const NarratorSceneSnapshot(
            present: {},
            departed: {},
            arriving: {},
          );
    return _narrator.activeSceneLawBlock(
      messages: _messages,
      activeNarratorId: activeId,
      userName: _userName,
      charName: charName,
      isGroup: _isGroup,
      speakingAsName: speaker,
      physicallyPresent: sceneSnapshot.present,
      departedPresent: sceneSnapshot.departed,
      narratorBeatFor: sceneSnapshot.arriving,
      endExclusive: endExclusive,
      excludeMessageIndex: excludeMessageIndex,
      castNames: _participants.map((c) => c.name),
    );
  }

  void _appendNarratorHistoryBlock(
    List<Map<String, String>> msgs,
    ChatMessage message,
    String? activeNarratorId, {
    required String focusCharacterName,
  }) {
    final block = _narrator.historyBlockFor(
      message: message,
      activeNarratorId: activeNarratorId,
      focusCharacterName: focusCharacterName,
      castNames: _participants.map((c) => c.name),
    );
    if (block != null) msgs.add(block);
  }

  String _historyBodyForMessage({
    required ChatMessage message,
    required Character observer,
  }) {
    var body = stripLeadingSpeakerPrefix(
      message.text,
      message.speakerName,
    );
    if (_isGroup &&
        !message.isUser &&
        message.speakerName != null &&
        message.speakerName!.trim().isNotEmpty) {
      body = _presence.observableMessageTextForCharacter(
        text: body,
        messageSpeakerName: message.speakerName!,
        observerCharacterName: observer.name,
      );
    }
    return body;
  }

  Future<void> _openNarratorSheet({String initialText = ''}) async {
    if (_busy || _session == null || _character == null) return;
    if (!_hasApiKey) {
      setState(() {
        _error = 'Add your NanoGPT API key in Settings before using Narrator.';
      });
      return;
    }
    final charName = _character!.name.trim().isNotEmpty
        ? _character!.name.trim()
        : 'Character';
    final otherNames = _isGroup
        ? _participants
            .where((c) => c.id != _character!.id)
            .map((c) => c.name.trim())
            .where((n) => n.isNotEmpty)
            .toList()
        : const <String>[];
    final result = await showNarratorSheet(
      context: context,
      nanoGptService: widget.nanoGptService,
      settingsService: widget.settingsService,
      recentMessages: List<ChatMessage>.from(_messages),
      userName: _userName,
      characterName: charName,
      isGroup: _isGroup,
      otherCharacterNames: otherNames,
      initialText: initialText,
    );
    if (result == null || !mounted) return;
    await _postNarratorText(_narrator.cleanGeneratedOutput(result.text));
  }

  Future<void> _editDirectorAt(int index) async {
    if (_busy || _session == null) return;
    final message = _messages[index];
    if (!message.isDirector) return;
    final controller = TextEditingController(text: message.text);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit director note'),
        content: TextField(
          controller: controller,
          minLines: 3,
          maxLines: 10,
          autofocus: true,
          decoration: const InputDecoration(
            hintText:
                'How they should act, feel, or respond on the next generation…',
            border: OutlineInputBorder(),
          ),
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
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
    if (result == null || !mounted) return;
    final trimmed = normalizeEmDashes(result.trim());
    if (trimmed.isEmpty) return;
    setState(() {
      _session!.messages[index] = message.withEditedText(trimmed);
    });
    await _persist();
  }

  Future<void> _editNarratorAt(int index) async {
    if (_busy || _session == null) return;
    final message = _messages[index];
    if (!message.isNarrator) return;
    final charName = _character?.name.trim().isNotEmpty == true
        ? _character!.name.trim()
        : 'Character';
    final otherNames = _isGroup
        ? _participants
            .where((c) => c.id != _character?.id)
            .map((c) => c.name.trim())
            .where((n) => n.isNotEmpty)
            .toList()
        : const <String>[];
    final result = await showNarratorSheet(
      context: context,
      nanoGptService: widget.nanoGptService,
      settingsService: widget.settingsService,
      recentMessages: _messages.sublist(0, index),
      userName: _userName,
      characterName: charName,
      isGroup: _isGroup,
      otherCharacterNames: otherNames,
      initialText: message.text,
    );
    if (result == null || !mounted) return;
    final trimmed = _narrator.cleanGeneratedOutput(result.text);
    if (trimmed.isEmpty) return;
    setState(() {
      _session!.messages[index] = message.withEditedText(trimmed);
    });
    await _persist();
  }

  Future<void> _showSceneCardMenu({
    required int index,
    required bool isDirector,
  }) async {
    if (_busy || index < 0 || index >= _messages.length) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                isDirector
                    ? Icons.control_camera_outlined
                    : Icons.theater_comedy_outlined,
              ),
              title: Text(isDirector ? 'Director' : 'Narrator'),
              subtitle: Text(
                isDirector
                    ? 'Scene control for the next reply'
                    : 'Omniscient scene voice',
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit'),
              onTap: () => Navigator.pop(context, 'edit'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Delete'),
              subtitle: const Text('Remove this card from the chat'),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'edit') {
      if (isDirector) {
        await _editDirectorAt(index);
      } else {
        await _editNarratorAt(index);
      }
    }
    if (action == 'delete') {
      await _deleteMessage(index);
    }
  }

  Future<void> _postNarratorText(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _session == null || _character == null) return;

    final autoReply = _session!.autoReply;
    final speaker = _resolvedGroupSpeaker();
    final narratorMessage = ChatMessage(
      id: ChatMessage.newId(),
      role: ChatRole.narrator,
      text: trimmed,
    );

    setState(() {
      _error = null;
      var session = _session!;
      session.messages.add(narratorMessage);
      _session = session;
      if (autoReply) {
        _busy = true;
        _session!.messages.add(
          ChatMessage(
            id: ChatMessage.newId(),
            role: ChatRole.assistant,
            text: '',
            swipes: const [''],
            swipeIndex: 0,
            speakerId: speaker.id,
            speakerName: speaker.name,
          ),
        );
      }
    });
    _scrollToBottom(jump: true);
    await _persist();
    if (!autoReply) {
      _refocusComposer();
      return;
    }

    await _streamIntoLastAssistant(
      excludeLastAssistant: true,
      speakingAs: speaker,
      advanceGroupSpeaker: _shouldAdvanceGroupSpeaker,
    );
  }

  void _toggleDirectorMode() {
    setState(() {
      _directorMode = !_directorMode;
      if (_directorMode) {
        _composerVoiceCharacterId = null;
        _composerVoiceGuideMode = false;
      }
    });
  }

  void _setComposerVoiceGuideMode(bool guide) {
    if (_composerVoiceCharacterId == null) return;
    setState(() => _composerVoiceGuideMode = guide);
  }

  Future<void> _toggleAutoReply() async {
    if (_busy || _session == null) return;
    final next = !_session!.autoReply;
    setState(() {
      _session = _session!.copyWith(autoReply: next);
    });
    await _persist();
  }

  /// Pick who speaks next. In a group with auto-reply off, tapping a name
  /// generates that character's reply (even if they are already selected).
  Future<void> _selectSpeaker(int index) async {
    if (_busy || _session == null) return;
    if (index < 0 || index >= _participants.length) return;

    setState(() {
      _session = _session!.copyWith(nextSpeakerIndex: index);
    });
    await _persist();

    if (_session!.autoReply || _messages.isEmpty) return;

    if (!_hasApiKey) {
      setState(() {
        _error = 'Add your NanoGPT API key in Settings before you can chat.';
      });
      return;
    }

    final speaker = _participants[index];
    final assistantId = ChatMessage.newId();
    setState(() {
      _error = null;
      _busy = true;
      _session!.messages.add(
        ChatMessage(
          id: assistantId,
          role: ChatRole.assistant,
          text: '',
          swipes: const [''],
          swipeIndex: 0,
          speakerId: speaker.id,
          speakerName: speaker.name,
        ),
      );
    });
    await _persist();
    await _streamIntoLastAssistant(
      excludeLastAssistant: true,
      speakingAs: speaker,
      mode: _isGroup ? PromptMode.continueScene : PromptMode.normal,
      advanceGroupSpeaker: _shouldAdvanceGroupSpeaker,
    );
  }

  Future<void> _openGroupReplySheet() async {
    if (_busy || _session == null || !_isGroup) return;
    if (_participants.length < 2) {
      _showChatError('Need at least two characters in the cast.');
      return;
    }
    if (!_hasApiKey) {
      setState(() {
        _error = 'Add your NanoGPT API key in Settings before you can chat.';
      });
      return;
    }
    final result = await showGroupReplySheet(
      context: context,
      participants: _participants,
    );
    if (result == null || !mounted) return;
    await _generateGroupBeat(
      speakers: result.speakers,
      nudge: result.nudge,
    );
  }

  String _latestPriorGroupBeatText({required int beforeIndex}) {
    for (var i = beforeIndex - 1; i >= 0; i--) {
      final message = _messages[i];
      if (message.isGroupBeat && message.beatLines != null) {
        return GroupBeatCodec.flatten(message.beatLines!);
      }
    }
    return '';
  }

  Future<List<GroupBeatLine>> _completeGroupBeatLines({
    required List<Character> speakers,
    required List<Map<String, String>> apiMessages,
    required String model,
    required String baseUrl,
    required SamplingSettings sampling,
    bool freshVariant = false,
  }) async {
    final beatSampling = GroupReplyService.beatSampling(
      sampling,
      speakers.length,
      freshVariant: freshVariant,
    );
    final raw = await widget.nanoGptService.complete(
      model: model,
      messages: apiMessages,
      baseUrl: baseUrl,
      sampling: beatSampling,
    );

    var beats = _groupReply.parseBeatReply(raw, speakers);
    if (beats.length >= speakers.length) return beats;

    final missing = speakers
        .where((s) => !beats.any((b) => b.character.id == s.id))
        .map((c) => c.name.trim())
        .where((n) => n.isNotEmpty)
        .join(', ');
    if (missing.isEmpty) return beats;

    final retryRaw = await widget.nanoGptService.complete(
      model: model,
      messages: [
        ...apiMessages,
        {'role': 'assistant', 'content': raw},
        {
          'role': 'user',
          'content':
              'You skipped some characters. Reply again with ONLY the missing '
              'lines in the same Name: reaction format — one brief line each '
              'for: $missing. No preamble.',
        },
      ],
      baseUrl: baseUrl,
      sampling: beatSampling,
    );
    final retryBeats = _groupReply.parseBeatReply(retryRaw, speakers);
    final byId = {for (final b in beats) b.character.id: b};
    for (final beat in retryBeats) {
      byId.putIfAbsent(beat.character.id, () => beat);
    }
    return speakers
        .map((s) => byId[s.id])
        .whereType<GroupBeatLine>()
        .toList(growable: false);
  }

  Future<void> _generateGroupBeat({
    required List<Character> speakers,
    String nudge = '',
  }) async {
    if (_busy || _session == null) return;
    if (speakers.length < 2) return;
    if (!_hasApiKey) return;

    setState(() {
      _error = null;
      _busy = true;
    });

    try {
      final model = await widget.settingsService.getModel();
      final sampling = await widget.settingsService.getSampling();
      final baseUrl = await widget.settingsService.getApiBaseUrl();
      final priorBeat = _latestPriorGroupBeatText(
        beforeIndex: _messages.length,
      );
      final beatId = ChatMessage.newId();
      _bindPendingDirectorToAssistant(beatId);
      final apiMessages = await _buildGroupBeatApiMessages(
        speakers: speakers,
        nudge: nudge,
        priorBeatToAvoid: priorBeat,
        targetBeatMessageId: beatId,
      );
      if (apiMessages.isEmpty) {
        _showChatError('Could not build group beat prompt.');
        return;
      }

      final beats = await _completeGroupBeatLines(
        speakers: speakers,
        apiMessages: apiMessages,
        model: model,
        baseUrl: baseUrl,
        sampling: sampling,
        freshVariant: priorBeat.trim().isNotEmpty,
      );
      if (!mounted) return;

      if (beats.isEmpty) {
        _showChatError(
          'Group beat came back empty — try again or pick fewer characters.',
        );
        return;
      }

      setState(() {
        final parts = _partsFromBeatLines(beats);
        _session!.messages.add(
          ChatMessage.groupBeat(
            id: beatId,
            lines: parts,
          ),
        );
      });
      await _persist();
      _scrollToBottom(jump: true);

      unawaited(_maybeAutoSummarize());
    } on NanoGptCancelledException {
      // Ignore.
    } on NanoGptException catch (error) {
      _showChatError(error.message);
    } catch (error) {
      _showChatError('Group react failed: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _regenerateGroupBeatAt(
    int index, {
    required bool asNewSwipe,
    String nudge = '',
  }) async {
    if (_busy || _session == null) return;
    if (index < 0 || index >= _messages.length) return;
    final message = _messages[index];
    if (!message.isGroupBeat || message.beatLines == null) return;
    if (!_hasApiKey) {
      setState(() {
        _error = 'Add your NanoGPT API key in Settings before you can chat.';
      });
      return;
    }

    final priorBeat = GroupBeatCodec.flatten(message.beatLines!);
    final speakers = _resolveGroupBeatSpeakers(message.beatLines!);
    if (speakers.length < 2) {
      _showChatError(
        'Need at least two characters in this group chat to regenerate a group react.',
      );
      return;
    }

    var messages = List<ChatMessage>.from(_session!.messages);
    if (index < messages.length - 1) {
      messages = messages.sublist(0, index + 1);
    }
    messages[index] = messages[index].prepareEmptySwipe(asNewSwipe: asNewSwipe);

    setState(() {
      _error = null;
      _busy = true;
      _session = _session!.copyWith(messages: messages);
    });
    await _persist();

    try {
      final model = await widget.settingsService.getModel();
      final sampling = await widget.settingsService.getSampling();
      final baseUrl = await widget.settingsService.getApiBaseUrl();
      final beatMessageId = messages[index].id;
      final apiMessages = await _buildGroupBeatApiMessages(
        speakers: speakers,
        nudge: nudge,
        historyEndExclusive: index,
        priorBeatToAvoid: priorBeat,
        targetBeatMessageId: beatMessageId,
      );
      if (apiMessages.isEmpty) {
        _showChatError('Could not build group beat prompt.');
        return;
      }

      final beats = await _completeGroupBeatLines(
        speakers: speakers,
        apiMessages: apiMessages,
        model: model,
        baseUrl: baseUrl,
        sampling: sampling,
        freshVariant: true,
      );
      if (!mounted) return;

      if (beats.isEmpty) {
        _showChatError(
          'Group beat came back empty — try again or pick fewer characters.',
        );
        return;
      }

      final parts = _partsFromBeatLines(beats);
      setState(() {
        final working = _session!.messages[index];
        _session!.messages[index] = _applyGroupBeatParts(working, parts);
      });
      await _persist();
      _scrollToBottom(jump: true);
      unawaited(_maybeAutoSummarize());
    } on NanoGptCancelledException {
      // Ignore.
    } on NanoGptException catch (error) {
      _showChatError(error.message);
    } catch (error) {
      _showChatError('Group react failed: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<List<Map<String, String>>> _buildGroupBeatApiMessages({
    required List<Character> speakers,
    String nudge = '',
    int? historyEndExclusive,
    String priorBeatToAvoid = '',
    String? targetBeatMessageId,
  }) async {
    if (speakers.length < 2) return const [];

    final userName = _userName;
    final persona = _persona?.promptText ?? '';
    final loreSettings = await widget.settingsService.getLoreSettings();
    final extraBooks = await _lorebooksForSession(_session);

    final loreBefore = StringBuffer();
    final loreAfter = StringBuffer();
    for (final character in speakers) {
      final visibleForLore = _presence.filterHistoryForCharacter(
        history: _messages,
        allMessages: _messages,
        focusCharacter: character,
        participants: _participants,
        userName: userName,
      );
      final injection = _lorebookService.buildInjection(
        character: character,
        messages: visibleForLore,
        extraBooks: extraBooks,
        scanDepthOverride: loreSettings.scanDepth,
        tokenBudgetOverride: loreSettings.tokenBudget,
        recursiveScanningOverride: loreSettings.recursiveScanning,
        onTriggered: (labels) {
          if (labels.isEmpty) return;
          _showLocalToast('Lore Triggered: ${labels.join(', ')}');
        },
      );
      if (injection.beforeChar.trim().isNotEmpty) {
        loreBefore.writeln(injection.beforeChar.trim());
      }
      if (injection.afterChar.trim().isNotEmpty) {
        loreAfter.writeln(injection.afterChar.trim());
      }
    }

    final historyApi = <Map<String, String>>[];
    final contextSettings = await widget.settingsService.getContextSettings();
    final history = _contextService.selectHistory(
      messages: _messages,
      endExclusive: historyEndExclusive ?? _messages.length,
      memoryCoveredCount: _session?.memoryCoveredCount ?? 0,
      historyTokenBudget: contextSettings.historyTokenBudget,
      isGroup: true,
    );

    final visibleHistory = _presence.filterHistoryForSpeakers(
      history: history,
      allMessages: _messages,
      speakers: speakers,
      participants: _participants,
      userName: userName,
    );

    final pendingDirectorId = _session?.pendingDirectorMessageId;
    final activeNarratorId = _narrator.latestNarratorId(
      _messages,
      endExclusive: historyEndExclusive ?? _messages.length,
    );
    final primary = speakers.first;

    for (final message in visibleHistory) {
      if (message.isNarrator) {
        _appendNarratorHistoryBlock(
          historyApi,
          message,
          activeNarratorId,
          focusCharacterName: primary.name,
        );
        continue;
      }
      final directorHistory = _director.historyBlockFor(
        message: message,
        pendingDirectorId: pendingDirectorId,
      );
      if (directorHistory != null) {
        historyApi.add(directorHistory);
        continue;
      }
      if (message.isDirector) continue;
      if (message.isGroupBeat) {
        // Prior group reacts are omitted — they tempt verbatim copy-paste.
        continue;
      }
      if (!message.isUser &&
          message.speakerName != null &&
          message.speakerName!.trim().isNotEmpty) {
        final body = _historyBodyForMessage(
          message: message,
          observer: primary,
        );
        historyApi.add({
          'role': 'assistant',
          'content': '${message.speakerName}: $body',
        });
      } else {
        historyApi.add(message.toApiMap());
      }
    }

    _ensureApiHasInteractiveTurn(
      historyApi,
      characterName: speakers.map((c) => c.name).join(', '),
    );

    final globalPrompts =
        await widget.settingsService.getGlobalChatPromptSettings();

    var memoryBlock = '';
    final memory = (_session?.memorySummary ?? '').trim();
    if (memory.isNotEmpty) {
      final filtered = _presence.filterMemoryForSpeakers(
        memory: memory,
        speakers: speakers,
        userName: userName,
        castNames: _participants.map((c) => c.name),
      );
      memoryBlock = _presence.formatFilteredMemoryForPrompt(
        filteredMemory: filtered,
        charName: primary.name,
      );
    }

    final postHistory = _promptBuilder.buildPostHistory(
      character: primary,
      userName: userName,
      authorsNote: _effectiveAuthorsNote(),
      globalPostHistory: globalPrompts.postHistoryInstructions,
    );

    return _groupReply.buildBeatMessages(
      speakers: speakers,
      allInChat: _participants,
      historyApiMessages: historyApi,
      userName: userName,
      userPersona: persona,
      loreBefore: loreBefore.toString(),
      loreAfter: loreAfter.toString(),
      memoryBlock: memoryBlock,
      nudge: nudge,
      globalSystemPrompt: globalPrompts.systemPrompt,
      postHistory: postHistory,
      narratorBlock: _narratorActiveBlock(
            charName: primary.name,
            endExclusive: historyEndExclusive ?? _messages.length,
          ) ??
          '',
      directorBlock: _directorBlockForGeneration(
            character: primary,
            mode: PromptMode.normal,
            groupBeat: true,
            targetAssistantId: targetBeatMessageId,
          ) ??
          '',
      priorBeatToAvoid: priorBeatToAvoid,
    );
  }

  Future<void> _continueScene() async {
    if (_busy || _session == null || _character == null) return;
    if (!_hasApiKey) {
      setState(() {
        _error = 'Add your NanoGPT API key in Settings before you can chat.';
      });
      return;
    }
    final speaker = _resolvedGroupSpeaker();
    setState(() {
      _error = null;
      _busy = true;
      _session!.messages.add(
        ChatMessage(
          id: ChatMessage.newId(),
          role: ChatRole.assistant,
          text: '',
          swipes: const [''],
          swipeIndex: 0,
          speakerId: speaker.id,
          speakerName: speaker.name,
        ),
      );
    });
    await _persist();
    await _streamIntoLastAssistant(
      excludeLastAssistant: true,
      mode: PromptMode.continueScene,
      speakingAs: speaker,
      advanceGroupSpeaker: _shouldAdvanceGroupSpeaker,
    );
  }

  void _openComposerToolsSheet() {
    if (_busy) return;
    unawaited(
      showChatComposerToolsSheet(
        context: context,
        activeMoodCount: _activeSceneMoodCount,
        showGroupReact: _isGroup && _participants.length >= 2,
        actions: ChatComposerToolsActions(
          onSceneMoods: _pickSceneMoods,
          onNarrator: _openNarratorSheet,
          onGroupReact: _openGroupReplySheet,
        ),
      ),
    );
  }

  Future<void> _showPathsSheet() async {
    if (!mounted || _session == null) return;
    if (!_hasApiKey) {
      setState(() {
        _error =
            'Add your NanoGPT API key in Settings before you can use Paths.';
      });
      return;
    }
    if (_messages.isEmpty) {
      _showChatError('Need a bit of chat first.');
      return;
    }

    final charName = _character?.name.trim().isNotEmpty == true
        ? _character!.name.trim()
        : 'Character';
    final chosen = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => _PathsSheet(
        chatId: _session!.id,
        nanoGptService: widget.nanoGptService,
        settingsService: widget.settingsService,
        recentMessages: List<ChatMessage>.from(_messages),
        userName: _userName,
        characterName: charName,
        generationBlocked: _busy,
      ),
    );
    if (chosen == null || !mounted) return;
    _inputController.text = chosen;
    _inputController.selection = TextSelection.collapsed(offset: chosen.length);
  }

  Future<void> _impersonate() async {
    if (_busy || _session == null || _character == null) return;
    if (!_hasApiKey) {
      setState(() {
        _error = 'Add your NanoGPT API key in Settings before you can chat.';
      });
      return;
    }
    setState(() {
      _error = null;
      _busy = true;
      _session!.messages.add(
        ChatMessage(
          id: ChatMessage.newId(),
          role: ChatRole.user,
          text: '',
          swipes: const [''],
          swipeIndex: 0,
        ),
      );
    });
    await _persist();
    await _streamIntoLastAssistant(
      excludeLastAssistant: true,
      mode: PromptMode.impersonate,
    );
  }

  String _effectiveAuthorsNote() {
    return AuthorsNoteComposer.effectiveNote(
      manualAuthorsNote: _session?.authorsNote ?? '',
      activeSceneMoodIds: _session?.activeSceneMoodIds ?? const [],
    );
  }

  bool get _hasEffectiveAuthorsNote {
    return AuthorsNoteComposer.hasEffectiveNote(
      manualAuthorsNote: _session?.authorsNote ?? '',
      activeSceneMoodIds: _session?.activeSceneMoodIds ?? const [],
    );
  }

  int get _activeSceneMoodCount => _session?.activeSceneMoodIds.length ?? 0;

  Future<void> _pickSceneMoods() async {
    final session = _session;
    if (session == null || _busy) return;
    final result = await showSceneMoodSheet(
      context: context,
      activeIds: session.activeSceneMoodIds,
    );
    if (result == null || !mounted) return;
    setState(() {
      _session = session.copyWith(activeSceneMoodIds: result);
    });
    await _persist();
  }

  Future<void> _editAuthorsNote() async {
    final session = _session;
    if (session == null || _busy) return;
    final controller = TextEditingController(text: session.authorsNote);
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Author's Note"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Extra instructions for this chat only (injected each turn). '
                  'Use a preset, toggle Scene moods from the mood icon or + menu, '
                  'or write your own.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                PresetButton(
                  label: 'Author’s Note presets',
                  onPressed: () async {
                    final preset = await pickTextPreset(
                      context: context,
                      title: "Author's Note presets",
                      presets: AnimaPresets.authorsNotes,
                    );
                    if (preset == null) return;
                    controller.text = preset.text;
                  },
                ),
                TextField(
                  controller: controller,
                  minLines: 4,
                  maxLines: 10,
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: 'Extra instructions for this chat only…',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                ),
              ],
            ),
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
        );
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
    if (result == null || !mounted) return;
    setState(() {
      _session = session.copyWith(authorsNote: result.trim());
    });
    await _persist();
  }

  Future<void> _pickChatLorebooks() async {
    final session = _session;
    if (session == null || _busy) return;
    final books = await widget.worldInfoService.loadBooks();
    if (!mounted) return;
    final result = await pickChatLorebooks(
      context,
      allBooks: books,
      chatLorebookIds: session.lorebookIds,
    );
    if (result == null || !mounted) return;
    setState(() {
      _session = result.useAppDefault
          ? session.copyWith(clearLorebookIds: true)
          : session.copyWith(lorebookIds: result.selectedIds);
    });
    await _persist();
  }

  Future<void> _editMemorySummary() async {
    final session = _session;
    if (session == null || _busy) return;
    final result = await showMemorySummarySheet(
      context: context,
      initialText: session.memorySummary,
      memoryCoveredCount: session.memoryCoveredCount,
    );
    if (result == null || !mounted) return;
    final trimmed = normalizeEmDashes(result.trim());
    setState(() {
      _session = session.copyWith(
        memorySummary: trimmed,
        memoryCoveredCount: trimmed.isEmpty ? 0 : session.memoryCoveredCount,
      );
    });
    await _persist();
  }

  Future<ChatPromptBreakdown> _buildChatPromptBreakdown() async {
    final session = _session!;
    final speaker = _resolvedGroupSpeaker();
    final userName = _userName;
    final persona = _persona?.promptText ?? '';
    final end = _messages.length;

    final historyForScan = _presence.filterHistoryForCharacter(
      history: _messages.sublist(0, end),
      allMessages: _messages,
      focusCharacter: speaker,
      participants: _participants,
      userName: userName,
    );
    final loreSettings = await widget.settingsService.getLoreSettings();
    final extraBooks = await _lorebooksForSession(session);
    final lore = _lorebookService.buildInjection(
      character: speaker,
      messages: historyForScan,
      extraBooks: extraBooks,
      scanDepthOverride: loreSettings.scanDepth,
      tokenBudgetOverride: loreSettings.tokenBudget,
      recursiveScanningOverride: loreSettings.recursiveScanning,
    );
    final loreTokens = _contextService.estimateTokens(
      '${lore.beforeChar}\n${lore.afterChar}',
    );

    final others = _participants.where((c) => c.id != speaker.id).toList();
    final globalPrompts =
        await widget.settingsService.getGlobalChatPromptSettings();

    final systemBase = _promptBuilder.buildSystemPrompt(
      character: speaker,
      userName: userName,
      userPersona: '',
      lore: const LorebookInjection(),
      others: const [],
      globalSystemPrompt: '',
    );
    final systemWithPersona = _promptBuilder.buildSystemPrompt(
      character: speaker,
      userName: userName,
      userPersona: persona,
      lore: const LorebookInjection(),
      others: const [],
      globalSystemPrompt: '',
    );
    final systemWithGlobal = _promptBuilder.buildSystemPrompt(
      character: speaker,
      userName: userName,
      userPersona: '',
      lore: const LorebookInjection(),
      others: const [],
      globalSystemPrompt: globalPrompts.systemPrompt,
    );
    final speakerCardTokens = _contextService.estimateTokens(systemBase);
    final personaOnlyTokens = _contextService.estimateTokens(systemWithPersona) -
        speakerCardTokens;
    final globalPromptTokens = _contextService.estimateTokens(systemWithGlobal) -
        speakerCardTokens;
    final castSummaries = <({String name, int tokens})>[
      for (final other in others)
        (
          name: other.name.trim().isEmpty ? 'Character' : other.name.trim(),
          tokens: _tokenService.breakdown(other).groupSummaryTokens,
        ),
    ];
    final castSummaryTokens =
        castSummaries.fold<int>(0, (sum, row) => sum + row.tokens);

    final postHistory = _promptBuilder.buildPostHistory(
      character: speaker,
      userName: userName,
      authorsNote: _effectiveAuthorsNote(),
      globalPostHistory: globalPrompts.postHistoryInstructions,
    );
    final postHistoryTokens = _contextService.estimateTokens(postHistory);

    var memoryTokens = 0;
    final memory = session.memorySummary.trim();
    if (memory.isNotEmpty) {
      final filtered = _presence.filterMemoryForCharacter(
        memory: memory,
        characterName: speaker.name,
        userName: userName,
        castNames: _participants.map((c) => c.name),
      );
      final block = _presence.formatFilteredMemoryForPrompt(
        filteredMemory: filtered,
        charName: speaker.name,
      );
      memoryTokens = _contextService.estimateTokens(block);
    }

    final contextSettings = await widget.settingsService.getContextSettings();
    final history = _contextService.selectHistory(
      messages: _messages,
      endExclusive: end,
      memoryCoveredCount: session.memoryCoveredCount,
      historyTokenBudget: contextSettings.historyTokenBudget,
      isGroup: _isGroup,
    );
    final visibleHistory = _presence.ensureLastUserMessageIncluded(
      visibleHistory: _presence.filterHistoryForCharacter(
        history: history,
        allMessages: _messages,
        focusCharacter: speaker,
        participants: _participants,
        userName: userName,
      ),
      allMessages: _messages,
      endExclusive: end,
    );
    final historyTokens = _contextService.estimateConversationTokens(
      visibleHistory,
      isGroup: _isGroup,
    );

    final personaTokens = personaOnlyTokens + globalPromptTokens;
    final estimatedSent = speakerCardTokens +
        castSummaryTokens +
        personaOnlyTokens +
        globalPromptTokens +
        loreTokens +
        memoryTokens +
        historyTokens +
        postHistoryTokens;

    return ChatPromptBreakdown(
      speakerName: speaker.name.trim().isEmpty ? 'Character' : speaker.name.trim(),
      speakerCardTokens: speakerCardTokens,
      castSummaries: castSummaries,
      loreTokens: loreTokens,
      loreMatchedCount: lore.matchedCount,
      personaTokens: personaTokens,
      memoryTokens: memoryTokens,
      historyTokens: historyTokens,
      postHistoryTokens: postHistoryTokens,
      estimatedSentTokens: estimatedSent,
    );
  }

  Future<void> _showContextEstimate() async {
    final session = _session;
    if (session == null) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Expanded(child: Text('Estimating context…')),
          ],
        ),
      ),
    );

    try {
      final contextSettings = await widget.settingsService.getContextSettings();
      final breakdown = await _buildChatPromptBreakdown();
      final modelId = await widget.settingsService.getModel();
      final baseUrl = await widget.settingsService.getApiBaseUrl();
      int? modelContext;
      try {
        final models = await widget.nanoGptService.listModels(baseUrl: baseUrl);
        for (final model in models) {
          if (model.id == modelId) {
            modelContext = model.contextLength;
            break;
          }
        }
      } catch (_) {}

      final estimate = _contextService.estimateChat(
        messages: _messages,
        memoryCoveredCount: session.memoryCoveredCount,
        historyTokenBudget: contextSettings.historyTokenBudget,
        memorySummary: session.memorySummary,
        systemPrompt: '',
        postHistory: '',
        isGroup: session.isGroup,
        modelContextLength: modelContext,
      );

      if (!mounted) return;
      Navigator.of(context).pop(); // loading dialog

      final ratio = modelContext == null || modelContext <= 0
          ? null
          : (breakdown.estimatedSentTokens / modelContext).clamp(0.0, 2.0);
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
                  'This is a gauge, not an exact NanoGPT meter.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                Text('Messages in chat: ${estimate.messageCount}'),
                Text(
                  'Full transcript: ~${ContextEstimate.formatTokenCount(estimate.fullTranscriptTokens)} tokens',
                ),
                Text(
                  'Likely sent next reply: ~${ContextEstimate.formatTokenCount(breakdown.estimatedSentTokens)} tokens',
                ),
                const SizedBox(height: 12),
                Text(
                  'Next reply breakdown',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 6),
                Text(
                  'Speaking as ${breakdown.speakerName}: ~${ContextEstimate.formatTokenCount(breakdown.speakerCardTokens)} tokens (full card)',
                ),
                if (breakdown.castSummaries.isNotEmpty)
                  for (final row in breakdown.castSummaries)
                    Text(
                      '  ${row.name} (group snippet): ~${ContextEstimate.formatTokenCount(row.tokens)}',
                    ),
                if (breakdown.loreTokens > 0)
                  Text(
                    'World Info (this turn): ~${ContextEstimate.formatTokenCount(breakdown.loreTokens)} tokens'
                    '${breakdown.loreMatchedCount > 0 ? ' (${breakdown.loreMatchedCount} entries)' : ''}',
                  )
                else
                  const Text('World Info (this turn): none matched'),
                if (breakdown.personaTokens > 0)
                  Text(
                    'Persona + global prompts: ~${ContextEstimate.formatTokenCount(breakdown.personaTokens)} tokens',
                  ),
                if (breakdown.memoryTokens > 0)
                  Text(
                    'Memory summary: ~${ContextEstimate.formatTokenCount(breakdown.memoryTokens)} tokens',
                  ),
                Text(
                  'Message history: ~${ContextEstimate.formatTokenCount(breakdown.historyTokens)} tokens'
                  '${estimate.messagesInPrompt != null ? ' (${estimate.messagesInPrompt} messages' : ''}'
                  '${estimate.messagesTrimmedAway > 0 ? ', ${estimate.messagesTrimmedAway} older trimmed' : ''}'
                  '${estimate.messagesInPrompt != null ? ')' : ''}',
                ),
                if (breakdown.postHistoryTokens > 0)
                  Text(
                    'Post-history / Author\'s note: ~${ContextEstimate.formatTokenCount(breakdown.postHistoryTokens)} tokens',
                  ),
                if (estimate.historyBudgetTokens != null)
                  Text(
                    'History budget (Settings): ${ContextEstimate.formatTokenCount(estimate.historyBudgetTokens!)} tokens',
                  ),
                const SizedBox(height: 8),
                Text('Current model: $modelId'),
                if (modelContext != null)
                  Text(
                    'Model context: ${ContextEstimate.formatTokenCount(modelContext)} tokens'
                    '${ratio == null ? '' : ' (~${(ratio * 100).round()}% of window vs send size)'}',
                  )
                else
                  const Text(
                    'Model context: unknown — open API & connection, refresh the catalog, and pick a listed model.',
                  ),
                if (estimate.notes.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(estimate.notes),
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
    } catch (error) {
      if (!mounted) return;
      Navigator.of(context).pop(); // loading dialog
      _showChatError('Could not estimate context: $error');
    }
  }

  Future<void> _summarizeNow({
    bool quiet = false,
    int extraKeepRecent = 0,
  }) async {
    final session = _session;
    if (session == null || _character == null) return;
    if (_summarizing) return;
    if (_busy && !quiet) return;
    if (!_hasApiKey) {
      setState(() {
        _error = 'Add your NanoGPT API key in Settings before summarizing.';
      });
      return;
    }

    final contextSettings = await widget.settingsService.getContextSettings();
    final snapshotMessageCount = _messages.length;
    final snapshotSessionId = session.id;
    final priorCovered = session.memoryCoveredCount;
    final cut = _contextService.summarizeCutIndex(
      messageCount: snapshotMessageCount,
      memoryCoveredCount: priorCovered,
      summarizeKeepRecent: contextSettings.summarizeKeepRecent,
      extraKeepRecent: extraKeepRecent,
    );
    if (cut <= priorCovered) {
      if (!quiet) {
        _showChatError(
          'Not enough older messages to summarize yet. Chat more, or lower '
          '“Keep recent” in Generation parameters.',
        );
      }
      return;
    }

    final chunk = _messages.sublist(priorCovered, cut);
    final generation = ++_summarizeGeneration;
    setState(() {
      _summarizing = true;
      _error = null;
    });

    try {
      final model = await widget.settingsService.getModel();
      final sampling = await widget.settingsService.getSampling();
      final baseUrl = await widget.settingsService.getApiBaseUrl();
      final updated = await widget.nanoGptService.complete(
        model: model,
        messages: _contextService.buildSummarizeMessages(
          chunk: chunk,
          existingSummary: session.memorySummary,
          userName: _userName,
          charName: _character!.name,
          coveredMessageCount: cut,
        ),
        baseUrl: baseUrl,
        sampling: ChatContextService.summarizeSampling(sampling),
      );
      if (!mounted) return;
      if (generation != _summarizeGeneration) return;
      final current = _session;
      if (current == null || current.id != snapshotSessionId) {
        setState(() => _summarizing = false);
        return;
      }
      final merged = normalizeEmDashes(
        ChatContextService.finalizeSummarizeOutput(
          existingSummary: current.memorySummary,
          generated: updated,
        ),
      );
      if (merged.isEmpty) {
        setState(() {
          _summarizing = false;
          _error =
              'Summarize returned no facts. Nothing was folded — try again.';
        });
        return;
      }
      // Never fold through the latest message that existed when summarize
      // started — keeps the newest reply out of memory even if settings are low.
      final safeCut = cut.clamp(
        priorCovered,
        snapshotMessageCount > 0 ? snapshotMessageCount - 1 : 0,
      );
      if (safeCut <= current.memoryCoveredCount) {
        setState(() => _summarizing = false);
        return;
      }
      setState(() {
        _session = current.copyWith(
          memorySummary: merged,
          memoryCoveredCount: safeCut,
        );
        _summarizing = false;
      });
      await _persist();
    } on NanoGptException catch (error) {
      if (!mounted) return;
      if (generation != _summarizeGeneration) return;
      setState(() {
        _summarizing = false;
        _error = error.message;
      });
    } catch (error) {
      if (!mounted) return;
      if (generation != _summarizeGeneration) return;
      setState(() {
        _summarizing = false;
        _error = 'Summarize failed: $error';
      });
    }
  }

  Future<void> _maybeAutoSummarize() async {
    final session = _session;
    if (session == null || _summarizing) return;
    final contextSettings = await widget.settingsService.getContextSettings();
    if (!_contextService.shouldAutoSummarize(
      messageCount: _messages.length,
      memoryCoveredCount: session.memoryCoveredCount,
      context: contextSettings,
    )) {
      return;
    }
    await _summarizeNow(quiet: true, extraKeepRecent: 1);
  }

  Future<void> _manageCast() async {
    if (_busy || _session == null) return;
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
          existingSession: _session,
          preselectedIds: _session!.effectiveParticipantIds.toSet(),
        ),
      ),
    );
    if (session == null || !mounted) return;
    await _flushDraftNow();
    final fallback =
        _character ?? Character(id: session.characterId, name: 'Character');
    final participants = await _resolveParticipants(session, fallback);
    await _applySession(
      session,
      participants: participants,
      character: participants.isNotEmpty ? participants.first : fallback,
    );
  }

  Future<void> _updateCharacterFromChat() async {
    if (_busy || _session == null) return;
    final result = await showUpdateCharacterFromChatSheet(
      context: context,
      session: _session!,
      participants: _participants,
      persona: _persona,
      characterService: widget.characterService,
      settingsService: widget.settingsService,
      nanoGptService: widget.nanoGptService,
      worldInfoService: widget.worldInfoService,
    );
    if (result == null || !mounted) return;

    if (result.chatOnly) {
      _setCharacterOverride(result.character);
      return;
    }

    final updated = result.character;
    final overrides = Map<String, Character>.from(_session!.characterOverrides)
      ..remove(updated.id);
    final session = _session!.copyWith(
      characterOverrides: overrides,
      clearCharacterOverrides: overrides.isEmpty,
    );
    await widget.chatService.saveChat(session);
    await _refreshCastFromSession(session);
  }

  Future<void> _openChatLorebook() async {
    final session = _session;
    if (session == null || _busy) return;
    final initial = session.chatLorebook ??
        const Lorebook(
          name: 'Chat story lore',
          description: 'Facts and relationships for this thread only.',
        );
    final book = await Navigator.of(context).push<Lorebook>(
      MaterialPageRoute(
        builder: (_) => LorebookEditScreen(
          initial: initial,
          settingsService: widget.settingsService,
          nanoGptService: widget.nanoGptService,
          characterName: _isGroup
              ? _participants.map((c) => c.name).join(', ')
              : (_character?.name ?? ''),
        ),
      ),
    );
    if (book == null || !mounted) return;
    final updated = session.copyWith(
      chatLorebook: book.isEmpty ? null : book,
      clearChatLorebook: book.isEmpty,
    );
    await _persistSessionAndRefreshCast(updated);
  }

  Future<void> _openChatOverrides() async {
    final session = _session;
    if (session == null || _busy) return;
    await showChatOverridesSheet(
      context: context,
      session: session,
      participants: _participants,
      persona: _persona,
      onChanged: (next) async {
        await _persistSessionAndRefreshCast(next);
      },
    );
  }

  Future<void> _createCharacterForChat() async {
    if (_busy || _session == null) return;
    final created = await showCreateCharacterFromChatSheet(
      context: context,
      session: _session!,
      participants: _participants,
      persona: _persona,
      characterService: widget.characterService,
      settingsService: widget.settingsService,
      nanoGptService: widget.nanoGptService,
      worldInfoService: widget.worldInfoService,
    );
    if (created == null || !mounted || _session == null) return;

    final currentIds = _session!.effectiveParticipantIds;
    if (currentIds.contains(created.id)) {
      _showChatError('${created.name} is already in this chat.');
      return;
    }

    final byId = {
      for (final c in _participants) c.id: c,
      created.id: created,
    };
    final ordered = [
      for (final id in currentIds)
        if (byId.containsKey(id)) byId[id]!,
      created,
    ];

    try {
      final updated = await widget.chatService.updateSessionCast(
        _session!,
        ordered,
      );
      if (!mounted) return;
      await _applySession(
        updated,
        participants: ordered,
        character: ordered.first,
      );
    } catch (error) {
      _showChatError('Could not add character: $error');
    }
  }

  Future<void> _addTemporaryCharacterToChat() async {
    if (_busy || _session == null) return;
    final created = await showTemporaryCharacterSheet(
      context: context,
      characterService: widget.characterService,
    );
    if (created == null || !mounted || _session == null) return;

    final currentIds = _session!.effectiveParticipantIds;
    if (currentIds.contains(created.id)) {
      _showChatError('${created.name} is already in this chat.');
      return;
    }

    final byId = {
      for (final c in _participants) c.id: c,
      created.id: created,
    };
    final ordered = [
      for (final id in currentIds)
        if (byId.containsKey(id)) byId[id]!,
      created,
    ];

    try {
      final updated = await widget.chatService.updateSessionCast(
        _session!,
        ordered,
      );
      if (!mounted) return;
      await _applySession(
        updated,
        participants: ordered,
        character: ordered.first,
      );
    } catch (error) {
      _showChatError('Could not add character: $error');
    }
  }

  Future<void> _regenerateOrSwipe({required bool asNewSwipe}) async {
    if (_messages.isEmpty) return;
    final lastIndex = _messages.length - 1;
    await _regenerateMessageAt(lastIndex, asNewSwipe: asNewSwipe);
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
        speakerId: message.speakerId,
        speakerName: message.speakerName,
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
      speakerId: message.speakerId,
      speakerName: message.speakerName,
    );
  }

  Future<void> _rewriteMessageAt(int index) async {
    if (_busy || _session == null || _character == null) return;
    final message = _messages[index];
    if (message.isUser) return;
    if (message.isGroupBeat) {
      _showChatError(
        'Rewrite is not available for group react — edit lines or regenerate.',
      );
      return;
    }
    final choice = await showReplyRewriteSheet(context);
    if (!mounted || choice == null) return;
    await _regenerateMessageAt(
      index,
      asNewSwipe: true,
      rewrite: choice,
    );
  }

  Future<void> _regenerateMessageAt(
    int index, {
    required bool asNewSwipe,
    ReplyRewriteChoice? rewrite,
  }) async {
    if (_busy || _session == null) return;
    if (index < 0 || index >= _messages.length) return;
    final message = _messages[index];
    if (message.isUser) {
      setState(() {
        _error = 'Send a message first so there is an AI reply to regenerate.';
      });
      return;
    }
    if (message.isGroupBeat) {
      if (rewrite != null) {
        _showChatError('Rewrite is not available for group react.');
        return;
      }
      await _regenerateGroupBeatAt(index, asNewSwipe: asNewSwipe);
      return;
    }
    if (_character == null) return;
    if (!_hasApiKey) {
      setState(() {
        _error = 'Add your NanoGPT API key in Settings before you can chat.';
      });
      return;
    }

    final originalText = message.text;
    final speaker = _participants.firstWhere(
      (c) => c.id == message.speakerId,
      orElse: () => _character!,
    );

    var messages = List<ChatMessage>.from(_session!.messages);
    if (index < messages.length - 1) {
      messages = messages.sublist(0, index + 1);
    }
    messages[index] = _prepareAssistantForRegeneration(
      messages[index],
      asNewSwipe: asNewSwipe,
    );

    List<Map<String, String>>? rewriteMessages;
    if (rewrite != null) {
      rewriteMessages = _replyRewrite.buildRewriteMessages(
        mode: rewrite.mode,
        originalReply: originalText,
        characterName: speaker.name,
        contextMessages: messages.sublist(0, index),
        customInstruction: rewrite.customInstruction,
      );
    }

    setState(() {
      _error = null;
      _busy = true;
      _session = _session!.copyWith(messages: messages);
    });
    await _persist();

    await _streamAssistantReply(
      assistantIndex: index,
      allowGreetingNudge: rewrite == null,
      speakingAs: speaker,
      advanceGroupSpeaker: false,
      rewriteMessages: rewriteMessages,
    );
  }

  /// NanoGPT rejects requests with only system-role messages.
  /// Never leaks filtered-out history — uses a minimal continue nudge instead.
  void _ensureApiHasInteractiveTurn(
    List<Map<String, String>> msgs, {
    required String characterName,
  }) {
    final hasTurn = msgs.any(
      (m) => m['role'] == 'user' || m['role'] == 'assistant',
    );
    if (hasTurn) return;

    final char =
        characterName.trim().isEmpty ? 'Character' : characterName.trim();
    msgs.add({
      'role': 'user',
      'content':
          '(Continue. Write only the next reply as $char from what $char already knows in this scene.)',
    });
  }

  Future<List<Map<String, String>>> _buildApiMessages({
    required bool excludeLastAssistant,
    bool allowGreetingNudge = false,
    PromptMode mode = PromptMode.normal,
    Character? speakingAs,
    int? historyEndExclusive,
    List<Map<String, String>>? rewriteMessages,
    String? targetAssistantId,
  }) async {
    final character = speakingAs ?? _resolvedGroupSpeaker();
    final userName = _userName;
    final persona = _persona?.promptText ?? '';

    final end = historyEndExclusive ??
        (excludeLastAssistant ? _messages.length - 1 : _messages.length);
    final rawHistoryForScan = _messages.sublist(0, end);
    final historyForScan = _presence.ensureLastUserMessageIncluded(
      visibleHistory: _presence.filterHistoryForCharacter(
        history: rawHistoryForScan,
        allMessages: _messages,
        focusCharacter: character,
        participants: _participants,
        userName: userName,
      ),
      allMessages: _messages,
      endExclusive: end,
    );
    final loreSettings = await widget.settingsService.getLoreSettings();
    final extraBooks = await _lorebooksForSession(_session);
    final lore = _lorebookService.buildInjection(
      character: character,
      messages: historyForScan,
      extraBooks: extraBooks,
      scanDepthOverride: loreSettings.scanDepth,
      tokenBudgetOverride: loreSettings.tokenBudget,
      recursiveScanningOverride: loreSettings.recursiveScanning,
      onTriggered: (labels) {
        if (labels.isEmpty) return;
        _showLocalToast('Lore Triggered: ${labels.join(', ')}');
      },
    );

    final others = _participants.where((c) => c.id != character.id).toList();
    final globalPrompts =
        await widget.settingsService.getGlobalChatPromptSettings();
    final system = _promptBuilder.buildSystemPrompt(
      character: character,
      userName: userName,
      userPersona: persona,
      lore: lore,
      others: others,
      mode: mode,
      globalSystemPrompt: globalPrompts.systemPrompt,
    );
    final postHistory = _promptBuilder.buildPostHistory(
      character: character,
      userName: userName,
      authorsNote: _effectiveAuthorsNote(),
      globalPostHistory: globalPrompts.postHistoryInstructions,
    );

    final msgs = <Map<String, String>>[
      {'role': 'system', 'content': system},
    ];

    final memory = (_session?.memorySummary ?? '').trim();
    if (memory.isNotEmpty) {
      final filtered = _presence.filterMemoryForCharacter(
        memory: memory,
        characterName: character.name,
        userName: userName,
        castNames: _participants.map((c) => c.name),
      );
      final block = _presence.formatFilteredMemoryForPrompt(
        filteredMemory: filtered,
        charName: character.name,
      );
      if (block.isNotEmpty) {
        msgs.add({'role': 'system', 'content': block});
      }
    }

    final contextSettings = await widget.settingsService.getContextSettings();
    final history = _contextService.selectHistory(
      messages: _messages,
      endExclusive: end,
      memoryCoveredCount: _session?.memoryCoveredCount ?? 0,
      historyTokenBudget: contextSettings.historyTokenBudget,
      isGroup: _isGroup,
    );

    final visibleHistory = _presence.ensureLastUserMessageIncluded(
      visibleHistory: _presence.filterHistoryForCharacter(
        history: history,
        allMessages: _messages,
        focusCharacter: character,
        participants: _participants,
        userName: userName,
      ),
      allMessages: _messages,
      endExclusive: end,
    );

    final pendingDirectorId = _session?.pendingDirectorMessageId;
    final activeNarratorId = _narrator.latestNarratorId(
      _messages,
      endExclusive: end,
    );

    for (final message in visibleHistory) {
      if (message.isNarrator) {
        _appendNarratorHistoryBlock(
          msgs,
          message,
          activeNarratorId,
          focusCharacterName: character.name,
        );
        continue;
      }
      final directorHistory = _director.historyBlockFor(
        message: message,
        pendingDirectorId: pendingDirectorId,
      );
      if (directorHistory != null) {
        msgs.add(directorHistory);
        continue;
      }
      if (message.isDirector) continue;
      if (message.isGroupBeat && message.beatLines != null) {
        final block = GroupBeatCodec.formatForPrompt(message.beatLines!);
        if (block.isNotEmpty) {
          msgs.add({'role': 'system', 'content': block});
        }
        continue;
      }
      // Prefixed speaker names help group chats stay clear in the history.
      // Strip any name the model already put in the body so we don't send
      // "Name: Name: …" and teach the habit again.
      if (!message.isUser &&
          message.speakerName != null &&
          message.speakerName!.trim().isNotEmpty &&
          _isGroup) {
        final body = _historyBodyForMessage(
          message: message,
          observer: character,
        );
        msgs.add({
          'role': 'assistant',
          'content': '${message.speakerName}: $body',
        });
      } else {
        msgs.add(message.toApiMap());
      }
    }

    _ensureApiHasInteractiveTurn(msgs, characterName: character.name);

    if (rewriteMessages != null && rewriteMessages.isNotEmpty) {
      msgs.addAll(rewriteMessages);
    } else {
      if (allowGreetingNudge && msgs.length <= 1) {
        msgs.add({
          'role': 'user',
          'content':
              '(Write an alternate opening greeting in character. Stay in first person as the character.)',
        });
      }

      if (mode == PromptMode.continueScene) {
        msgs.add({
          'role': 'user',
          'content':
              '(Continue. Write only the next reply as ${character.name}.)',
        });
      }
      if (mode == PromptMode.impersonate) {
        msgs.add({
          'role': 'user',
          'content':
              '(Write only $userName\'s next message. Do not write ${character.name}\'s lines.)',
        });
      }
    }

    if (postHistory.isNotEmpty) {
      msgs.add({'role': 'system', 'content': postHistory});
    }

    int? excludeMessageIndex;
    if (targetAssistantId != null) {
      final idx = _messages.indexWhere((m) => m.id == targetAssistantId);
      if (idx >= 0) excludeMessageIndex = idx;
    }

    final narratorBlock = _narratorActiveBlock(
      charName: character.name,
      endExclusive: end,
      speakingAsName: character.name,
      excludeMessageIndex: excludeMessageIndex,
    );
    if (narratorBlock != null && narratorBlock.trim().isNotEmpty) {
      msgs.add({'role': 'system', 'content': narratorBlock.trim()});
    }

    final directorBlock = _directorBlockForGeneration(
      character: character,
      mode: mode,
      targetAssistantId: targetAssistantId,
    );
    if (directorBlock != null && directorBlock.trim().isNotEmpty) {
      msgs.add({'role': 'system', 'content': directorBlock.trim()});
    }

    // Scene law + director are injected late (mandatory). If the player just
    // spoke after a narrator card, their line sits above this stack and the
    // model no longer has a user turn to answer — add one last.
    _appendPostSceneLawReplyNudge(
      msgs,
      messages: _messages,
      endExclusive: end,
      characterName: character.name,
      userName: userName,
    );

    if (rewriteMessages == null && others.isNotEmpty) {
      final handoff = _groupSpeakerInference.buildHandoffNudge(
        messages: _messages,
        endExclusive: end,
        target: character,
      );
      if (handoff != null) {
        msgs.add(handoff);
      }
    }

    return msgs;
  }

  /// When the latest chat line is the player's, ensure the API ends on a user
  /// turn after late system blocks (narrator scene law, director).
  void _appendPostSceneLawReplyNudge(
    List<Map<String, String>> msgs, {
    required List<ChatMessage> messages,
    required int endExclusive,
    required String characterName,
    required String userName,
  }) {
    if (endExclusive <= 0 || endExclusive > messages.length) return;
    final last = messages[endExclusive - 1];
    if (!last.isUser || last.text.trim().isEmpty) return;

    final char =
        characterName.trim().isEmpty ? 'Character' : characterName.trim();
    final user = userName.trim().isEmpty ? 'User' : userName.trim();
    msgs.add({
      'role': 'user',
      'content':
          '(Write only $char\'s next reply to $user\'s last message. Stay in character.)',
    });
  }

  Future<void> _streamIntoLastAssistant({
    required bool excludeLastAssistant,
    bool allowGreetingNudge = false,
    PromptMode mode = PromptMode.normal,
    Character? speakingAs,
    bool advanceGroupSpeaker = false,
  }) async {
    if (_messages.isEmpty) return;
    await _streamAssistantReply(
      assistantIndex: _messages.length - 1,
      excludeLastAssistant: excludeLastAssistant,
      allowGreetingNudge: allowGreetingNudge,
      mode: mode,
      speakingAs: speakingAs,
      advanceGroupSpeaker: advanceGroupSpeaker,
    );
  }

  Future<void> _streamAssistantReply({
    required int assistantIndex,
    bool excludeLastAssistant = true,
    bool allowGreetingNudge = false,
    PromptMode mode = PromptMode.normal,
    Character? speakingAs,
    bool advanceGroupSpeaker = false,
    List<Map<String, String>>? rewriteMessages,
  }) async {
    if (assistantIndex < 0 || assistantIndex >= _messages.length) return;
    try {
      final model = await widget.settingsService.getModel();
      final sampling = await widget.settingsService.getSampling();
      final baseUrl = await widget.settingsService.getApiBaseUrl();
      final speaker = speakingAs ?? _resolvedGroupSpeaker();
      final assistantId = _messages[assistantIndex].id;
      _bindPendingDirectorToAssistant(assistantId);
      final messages = await _buildApiMessages(
        excludeLastAssistant: excludeLastAssistant,
        allowGreetingNudge: allowGreetingNudge,
        mode: mode,
        speakingAs: speaker,
        historyEndExclusive: rewriteMessages != null ? assistantIndex : null,
        rewriteMessages: rewriteMessages,
        targetAssistantId: assistantId,
      );
      final buffer = StringBuffer();
      await for (final chunk in widget.nanoGptService.streamCompletion(
        model: model,
        messages: messages,
        baseUrl: baseUrl,
        sampling: sampling,
      )) {
        if (!mounted) return;
        buffer.write(chunk);
        final speakerLabel = speaker.name;
        final text = stripLeadingSpeakerPrefix(buffer.toString(), speakerLabel);
        setState(() {
          final updated = List<ChatMessage>.from(_session!.messages);
          final index = updated.indexWhere((m) => m.id == assistantId);
          if (index < 0) return;
          final current = updated[index];
          final swipes = List<String>.from(current.swipes);
          final swipeIndex = current.swipeIndex.clamp(
            0,
            (swipes.length - 1).clamp(0, 9999),
          );
          if (swipes.isEmpty) {
            swipes.add(text);
          } else {
            swipes[swipeIndex] = text;
          }
          updated[index] = ChatMessage(
            id: current.id,
            role: current.role,
            text: text,
            swipes: swipes,
            swipeIndex: swipeIndex,
            speakerId: current.speakerId ?? speaker.id,
            speakerName: current.speakerName ?? speaker.name,
          );
          _session = _session!.copyWith(messages: updated);
        });
      }

      if (!mounted) return;
      final updated = List<ChatMessage>.from(_session!.messages);
      final index = updated.indexWhere((m) => m.id == assistantId);
      if (index < 0) return;
      final current = updated[index];
      final cleaned = stripLeadingSpeakerPrefix(
        current.text.trim(),
        current.speakerName ?? speaker.name,
      );
      if (cleaned != current.text) {
        setState(() {
          final swipes = List<String>.from(current.swipes);
          final swipeIndex = current.swipeIndex.clamp(
            0,
            (swipes.length - 1).clamp(0, 9999),
          );
          if (swipes.isNotEmpty) {
            swipes[swipeIndex] = cleaned;
          }
          updated[index] = ChatMessage(
            id: current.id,
            role: current.role,
            text: cleaned,
            swipes: swipes.isEmpty ? [cleaned] : swipes,
            swipeIndex: swipeIndex,
            speakerId: current.speakerId ?? speaker.id,
            speakerName: current.speakerName ?? speaker.name,
          );
          _session = _session!.copyWith(messages: updated);
        });
      }
      final finalText = _session!.messages
          .firstWhere((m) => m.id == assistantId)
          .text
          .trim();
      if (finalText.isEmpty) {
        throw NanoGptException('NanoGPT returned an empty reply. Try again.');
      }
      if (advanceGroupSpeaker) {
        _advanceGroupSpeaker();
      }
      setState(() => _busy = false);
      await _persist();
      unawaited(_maybeAutoSummarize());
      _refocusComposer();
    } on NanoGptCancelledException {
      if (!mounted) return;
      await _finishStoppedGeneration(advanceGroupSpeaker: advanceGroupSpeaker);
    } on NanoGptException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error.message;
        _clearEmptyAssistantAt(assistantIndex);
      });
      await _persist();
      _refocusComposer();
    } catch (error) {
      if (!mounted) return;
      if (_looksLikeCancel(error)) {
        await _finishStoppedGeneration(
          advanceGroupSpeaker: advanceGroupSpeaker,
        );
        return;
      }
      setState(() {
        _busy = false;
        _error = 'Something unexpected went wrong: $error';
      });
      await _persist();
      _refocusComposer();
    }
  }

  void _clearEmptyAssistantAt(int assistantIndex) {
    if (_session == null) return;
    if (assistantIndex < 0 || assistantIndex >= _session!.messages.length) {
      return;
    }
    final message = _session!.messages[assistantIndex];
    if (message.isUser || message.text.trim().isNotEmpty) return;
    final updated = List<ChatMessage>.from(_session!.messages);
    if (message.swipes.length > 1 &&
        message.swipeIndex == message.swipes.length - 1) {
      final previous = List<String>.from(message.swipes)..removeLast();
      updated[assistantIndex] = ChatMessage(
        id: message.id,
        role: message.role,
        text: previous.last,
        swipes: previous,
        swipeIndex: previous.length - 1,
        speakerId: message.speakerId,
        speakerName: message.speakerName,
      );
    } else {
      updated.removeAt(assistantIndex);
    }
    _session = _session!.copyWith(messages: updated);
  }

  bool _looksLikeCancel(Object error) {
    final text = '$error'.toLowerCase();
    return text.contains('cancel') ||
        text.contains('closed') ||
        text.contains('connection abort') ||
        text.contains('client is already closed');
  }

  /// Keep any partial reply the user already saw; clear empty placeholders.
  Future<void> _finishStoppedGeneration({
    required bool advanceGroupSpeaker,
  }) async {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = null;
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
            speakerId: last.speakerId,
            speakerName: last.speakerName,
          );
        } else {
          _session!.messages.removeLast();
        }
      } else if (advanceGroupSpeaker &&
          _messages.isNotEmpty &&
          !_messages.last.isUser &&
          _messages.last.text.trim().isNotEmpty) {
        _advanceGroupSpeaker();
      }
    });
    await _persist();
    _refocusComposer();
  }

  void _stopGeneration() {
    if (!_busy) return;
    widget.nanoGptService.cancelActiveStream();
  }

  Future<void> _editMessage(int index) async {
    if (_busy || _session == null) return;
    final message = _messages[index];
    if (message.isGroupBeat) {
      await _editGroupBeatAt(index);
      return;
    }
    final controller = TextEditingController(text: message.text);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          message.isDirector
              ? 'Edit director note'
              : message.isUser
                  ? 'Edit your message'
                  : 'Edit reply',
        ),
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
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
    if (result == null || !mounted) return;
    final trimmed = normalizeEmDashes(result.trim());
    if (trimmed.isEmpty) return;
    setState(() {
      _session!.messages[index] = message.withEditedText(trimmed);
    });
    await _persist();
  }

  Future<void> _editGroupBeatAt(int index) async {
    if (_busy || _session == null) return;
    final message = _messages[index];
    if (!message.isGroupBeat || message.beatLines == null) return;
    final result = await showGroupBeatEditSheet(
      context: context,
      lines: message.beatLines!,
      participants: _participants,
    );
    if (result == null || !mounted) return;
    setState(() {
      _session!.messages[index] = message.withEditedBeatLines(result);
    });
    await _persist();
  }

  Future<void> _deleteMessage(int index) async {
    if (_busy || _session == null) return;
    if (index < 0 || index >= _messages.length) return;
    final clearMemory = index < _session!.memoryCoveredCount;
    setState(() {
      final messages = List<ChatMessage>.from(_session!.messages)
        ..removeAt(index);
      _session = _sessionAfterMessageListChange(messages).copyWith(
        memorySummary: clearMemory ? '' : _session!.memorySummary,
        memoryCoveredCount: clearMemory ? 0 : _session!.memoryCoveredCount,
      );
    });
    await _persist();
  }

  /// Keep messages through [index]; delete everything after.
  Future<void> _rewindToMessage(int index) async {
    if (_busy || _session == null) return;
    if (index < 0 || index >= _messages.length) return;
    if (index >= _messages.length - 1) return;
    final clearMemory = index + 1 < _session!.memoryCoveredCount;
    setState(() {
      final messages = _session!.messages.sublist(0, index + 1);
      _session = _sessionAfterMessageListChange(messages).copyWith(
        memorySummary: clearMemory ? '' : _session!.memorySummary,
        memoryCoveredCount: clearMemory ? 0 : _session!.memoryCoveredCount,
      );
    });
    await _persist();
  }

  /// Copy this chat through [index] into a new saved chat and switch to it.
  Future<void> _branchFromMessage(int index) async {
    if (_busy || _session == null) return;
    if (index < 0 || index >= _messages.length) return;

    final source = _session!;
    final copied = <ChatMessage>[];
    for (var i = 0; i <= index; i++) {
      final json = Map<String, dynamic>.from(source.messages[i].toJson());
      json['id'] = 'msg_${DateTime.now().microsecondsSinceEpoch}_$i';
      copied.add(ChatMessage.fromJson(json));
    }

    final baseTitle = source.title.trim().isEmpty
        ? 'Chat'
        : source.title.trim();
    final branchTitle = baseTitle.toLowerCase().contains('branch')
        ? baseTitle
        : '$baseTitle (branch)';

    final branched = ChatSession(
      id: ChatSession.newId(),
      characterId: source.characterId,
      title: branchTitle,
      updatedAt: DateTime.now(),
      messages: copied,
      authorsNote: source.authorsNote,
      participantIds: List<String>.from(source.participantIds),
      nextSpeakerIndex: source.nextSpeakerIndex,
      personaId: source.personaId,
      autoReply: source.autoReply,
      lorebookIds: source.lorebookIds == null
          ? null
          : List<String>.from(source.lorebookIds!),
      pendingDirectorMessageId: _director.reconcilePendingId(
        copied,
        source.pendingDirectorMessageId,
      ),
      pendingDirectorAssistantId: () {
        final id = source.pendingDirectorAssistantId;
        if (id == null || id.isEmpty) return null;
        return copied.any((m) => m.id == id) ? id : null;
      }(),
    );

    await widget.chatService.saveChat(branched);
    await widget.chatService.setActiveChatId(branched.characterId, branched.id);
    if (!mounted) return;
    setState(() => _session = branched);
    _scrollToBottom(jump: true);
  }

  void _shiftSwipe(int index, int delta) {
    if (_busy || _session == null) return;
    if (index < 0 || index >= _messages.length) return;
    final message = _messages[index];
    if (message.isUser || message.swipes.length < 2) return;
    final next = message.withSwipeIndex(message.swipeIndex + delta);
    if (next.swipeIndex == message.swipeIndex) return;
    setState(() => _session!.messages[index] = next);
    _persist();
  }

  void _scrollToBottom({bool jump = false}) {
    scrollListToEnd(_scrollController, jump: jump);
  }

  String _composerHintText(String characterName) {
    if (_directorMode) {
      return 'Direct the scene — how they act, feel, respond…';
    }
    final voice = _composerVoiceCharacter;
    if (voice != null) {
      final name = voice.name.trim().isEmpty ? 'Character' : voice.name.trim();
      if (_composerVoiceGuideMode) {
        return 'Guide $name — what they do, feel, or say…';
      }
      return 'Write as $name…';
    }
    if (_isGroup) {
      return 'Message the group…';
    }
    if (_session?.autoReply ?? false) {
      return 'Message $characterName…';
    }
    return 'Send only — tap Continue for a reply';
  }

  Color _composerBorderColor(ColorScheme colorScheme) {
    if (_directorMode) return colorScheme.primary;
    if (_composerVoiceCharacterId != null) {
      return _composerVoiceGuideMode
          ? colorScheme.secondary
          : colorScheme.tertiary;
    }
    return colorScheme.outline;
  }

  Widget _buildComposerVoiceModeToggle(ColorScheme colorScheme) {
    return Row(
      children: [
        Expanded(
          child: _composerVoiceGuideMode
              ? OutlinedButton.icon(
                  onPressed: _busy ? null : () => _setComposerVoiceGuideMode(false),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Write line'),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                )
              : FilledButton.tonalIcon(
                  onPressed: _busy ? null : () => _setComposerVoiceGuideMode(false),
                  icon: const Icon(Icons.edit, size: 18),
                  label: const Text('Write line'),
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _composerVoiceGuideMode
              ? FilledButton.tonalIcon(
                  onPressed: _busy ? null : () => _setComposerVoiceGuideMode(true),
                  icon: const Icon(Icons.auto_awesome, size: 18),
                  label: const Text('Guide AI'),
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                )
              : OutlinedButton.icon(
                  onPressed: _busy ? null : () => _setComposerVoiceGuideMode(true),
                  icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                  label: const Text('Guide AI'),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildComposerVoiceRow(ColorScheme colorScheme) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          Tooltip(
            message: 'Write as $_userName',
            child: InputChip(
              avatar: const Icon(Icons.person_outline, size: 18),
              label: Text(
                _userName.length > 14 ? 'You' : _userName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              selected: _composerVoiceCharacterId == null,
              onPressed: _busy
                  ? null
                  : () {
                      if (_composerVoiceCharacterId == null) {
                        _composerFocusNode?.requestFocus();
                        return;
                      }
                      _setComposerVoice(null);
                    },
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              labelPadding: const EdgeInsets.symmetric(horizontal: 8),
            ),
          ),
          for (var i = 0; i < _participants.length; i++) ...[
            const SizedBox(width: 6),
            Tooltip(
              message:
                  'Tap: AI reply · Long-press: write as ${_participants[i].name.trim().isEmpty ? 'character' : _participants[i].name.trim()}',
              child: GestureDetector(
                onLongPress: _busy
                    ? null
                    : () => _setComposerVoice(_participants[i].id),
                child: InputChip(
                  label: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 140),
                    child: Text(
                      _participants[i].name.trim().isEmpty
                          ? 'Character ${i + 1}'
                          : _participants[i].name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  selected: _composerVoiceCharacterId == _participants[i].id,
                  onPressed: _busy
                      ? null
                      : () {
                          if (_composerVoiceCharacterId ==
                              _participants[i].id) {
                            _composerFocusNode?.requestFocus();
                            return;
                          }
                          _selectSpeaker(i);
                        },
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  labelPadding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
            ),
          ],
          if (_isGroup && _participants.length >= 2) ...[
            const SizedBox(width: 6),
            InputChip(
              avatar: const Icon(Icons.groups_outlined, size: 18),
              label: const Text('Group react'),
              onPressed: _busy ? null : _openGroupReplySheet,
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              labelPadding: const EdgeInsets.symmetric(horizontal: 6),
            ),
          ],
        ],
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.nanoGptService.cancelActiveStream();
    _draftSaveTimer?.cancel();
    _toastTimer?.cancel();
    _toastEntry?.remove();
    _toastEntry = null;
    // Fire-and-forget final draft flush (async dispose is not allowed).
    final session = _session;
    final text = _inputController.text;
    if (session != null && text != _lastSavedDraft) {
      unawaited(_draftService.saveDraft(_composerDraftKey(session.id), text));
    }
    _inputController.removeListener(_onComposerChanged);
    _inputController.dispose();
    _composerFocusNode?.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final session = _session;
    final characterName = _isGroup
        ? ChatService.displayTitle(session!)
        : (_character?.name ?? 'Anima');
    final titleName = characterName;
    final groupSubtitle = _isGroup && session != null
        ? '${session.effectiveParticipantIds.length} characters'
        : null;
    final ui = AnimaUiTheme.of(context);
    final showChatBackground = ui.chatExperience.backgroundEnabled &&
        _chatBackgroundPath != null;
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 24;
    final compactComposer = !isDesktopPlatform;
    final hasMemory =
        (_session?.memorySummary.trim().isNotEmpty ?? false);
    final hasAuthorsNote = _hasEffectiveAuthorsNote;
    final activeMoodCount = _activeSceneMoodCount;
    return Scaffold(
      // We lift the body ourselves via [KeyboardInset] so the composer stays
      // above the keyboard even with a transparent glass scaffold.
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Close chat',
          icon: const Icon(Icons.close),
          onPressed: _loading || _busy
              ? null
              : () => Navigator.of(context).pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titleName),
            if (groupSubtitle != null)
              Text(
                groupSubtitle,
                style: Theme.of(context).textTheme.bodySmall,
              )
            else if (_session != null && !_isGroup)
              Text(
                _session!.title,
                style: Theme.of(context).textTheme.bodySmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'More',
            enabled: !_loading && !_busy,
            onSelected: (value) {
              if (value == 'persona') _pickPersona();
              if (value == 'authors_note') _editAuthorsNote();
              if (value == 'lorebooks') _pickChatLorebooks();
              if (value == 'chat_lore') _openChatLorebook();
              if (value == 'chat_copies') _openChatOverrides();
              if (value == 'memory') _editMemorySummary();
              if (value == 'summarize') _summarizeNow();
              if (value == 'context') _showContextEstimate();
              if (value == 'characters') _openCharacters();
              if (value == 'manage_cast') _manageCast();
              if (value == 'new_character') _createCharacterForChat();
              if (value == 'new_temp_character') _addTemporaryCharacterToChat();
              if (value == 'update_character') _updateCharacterFromChat();
              if (value == 'creation_center') _openCreationCenter();
              if (value == 'export') _exportChat();
              if (value == 'import') _importChat();
              if (value == 'api') _openQuickApi();
              if (value == 'settings') _openSettings();
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'persona',
                child: Text(
                  _persona == null
                      ? 'Switch persona'
                      : 'Persona: ${_persona!.name}',
                ),
              ),
              const PopupMenuItem(
                value: "authors_note",
                child: Text("Author's Note"),
              ),
              PopupMenuItem(
                value: 'lorebooks',
                child: Text(chatLorebookMenuLabel(_session?.lorebookIds)),
              ),
              PopupMenuItem(
                value: 'chat_lore',
                child: Text(
                  (_session?.chatLorebook != null &&
                          !_session!.chatLorebook!.isEmpty)
                      ? 'Chat lore (${_session!.chatLorebook!.entries.length})'
                      : 'Chat lore (this thread)',
                ),
              ),
              if (_session != null &&
                  _sessionResolver.hasChatOverrides(_session!))
                const PopupMenuItem(
                  value: 'chat_copies',
                  child: Text('Chat copies…'),
                ),
              PopupMenuItem(
                value: 'memory',
                child: Text(
                  (_session?.memorySummary.trim().isNotEmpty ?? false)
                      ? 'Memory summary (set)'
                      : 'Memory summary',
                ),
              ),
              const PopupMenuItem(
                value: 'summarize',
                child: Text('Summarize now'),
              ),
              const PopupMenuItem(
                value: 'context',
                child: Text('Context estimate'),
              ),
              const PopupMenuItem(
                value: 'characters',
                child: Text('Characters'),
              ),
              const PopupMenuItem(
                value: 'manage_cast',
                child: Text('Manage cast'),
              ),
              const PopupMenuItem(
                value: 'new_character',
                child: Text('New character'),
              ),
              const PopupMenuItem(
                value: 'new_temp_character',
                child: Text('Add temporary character'),
              ),
              const PopupMenuItem(
                value: 'update_character',
                child: Text('Update character from chat'),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'creation_center',
                child: Text('Open in Creation Center'),
              ),
              const PopupMenuItem(value: 'export', child: Text('Export chat')),
              const PopupMenuItem(value: 'import', child: Text('Import chat')),
              const PopupMenuItem(
                value: 'api',
                child: Text('API & model'),
              ),
              const PopupMenuItem(value: 'settings', child: Text('Settings')),
            ],
          ),
        ],
      ),
      body: KeyboardInset(
        child: Column(
          children: [
            if (_loading)
              const LinearProgressIndicator(minHeight: 2)
            else if (!_hasApiKey)
              Material(
                color: colorScheme.errorContainer,
                child: ListTile(
                  leading: Icon(
                    Icons.key_off,
                    color: colorScheme.onErrorContainer,
                  ),
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
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (showChatBackground)
                    ChatImageBackground(
                      key: ValueKey(
                        '${_chatBackgroundPath!}|${ui.chatExperience.backgroundBlur}',
                      ),
                      imagePath: _chatBackgroundPath!,
                      blurSigma: ui.chatExperience.backgroundBlur,
                    ),
                  _messages.isEmpty && !_busy
                      ? _EmptyChat(
                          hasApiKey: _hasApiKey,
                          characterName: characterName,
                          onOpenSettings: _openSettings,
                          onOpenCharacters: _openCharacters,
                          onNewChat: _newChat,
                        )
                      : CustomScrollView(
                      controller: _scrollController,
                      slivers: [
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                          sliver: SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                        final message = _messages[index];
                        if (message.isNarrator) {
                          return Padding(
                            padding: EdgeInsets.symmetric(
                              vertical:
                                  AnimaUiTheme.of(context).messageSpacing / 2,
                            ),
                            child: NarratorBubble(
                              label: 'Narrator',
                              icon: Icons.theater_comedy_outlined,
                              text: message.text,
                              onTap: _busy
                                  ? null
                                  : () => _editNarratorAt(index),
                              onLongPress: _busy
                                  ? null
                                  : () => _showSceneCardMenu(
                                        index: index,
                                        isDirector: false,
                                      ),
                            ),
                          );
                        }
                        if (message.isDirector) {
                          final pending = message.id ==
                              (_session?.pendingDirectorMessageId ?? '');
                          return Padding(
                            padding: EdgeInsets.symmetric(
                              vertical:
                                  AnimaUiTheme.of(context).messageSpacing / 2,
                            ),
                            child: NarratorBubble(
                              label: 'Director',
                              icon: Icons.control_camera_outlined,
                              text: message.text,
                              injecting: pending,
                              onTap: _busy
                                  ? null
                                  : () => _editDirectorAt(index),
                              onLongPress: _busy
                                  ? null
                                  : () => _showSceneCardMenu(
                                        index: index,
                                        isDirector: true,
                                      ),
                            ),
                          );
                        }
                        if (message.isGroupBeat) {
                          final isLast = index == _messages.length - 1;
                          final lines = message.beatLines ?? const [];
                          final thinking = _busy &&
                              isLast &&
                              lines.every((l) => l.text.trim().isEmpty);
                          final isLastAi = isLast;
                          final canGoPrev =
                              message.swipes.length > 1 &&
                              message.swipeIndex > 0;
                          final canGoNextExisting =
                              message.swipes.length > 1 &&
                              message.swipeIndex < message.swipes.length - 1;
                          final canQuickSwipe =
                              isLastAi &&
                              !thinking &&
                              !_busy &&
                              message.swipeIndex >= message.swipes.length - 1;
                          return Padding(
                            padding: EdgeInsets.symmetric(
                              vertical:
                                  AnimaUiTheme.of(context).messageSpacing / 2,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (thinking)
                                  Material(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .surfaceContainerHighest
                                        .withValues(alpha: 0.72),
                                    borderRadius: BorderRadius.circular(
                                      AnimaUiTheme.of(context).chatBubbleRadius,
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .primary,
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Text(
                                            'Group react…',
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodyMedium,
                                          ),
                                        ],
                                      ),
                                    ),
                                  )
                                else
                                  GroupBeatBubble(
                                    lines: lines,
                                    avatarForSpeakerId: _avatarForParticipantId,
                                    avatarStyle: _avatarStyle,
                                    onTap: (_busy || thinking)
                                        ? null
                                        : () => _editGroupBeatAt(index),
                                    onLongPress: (_busy || thinking)
                                        ? null
                                        : () => _showMessageMenu(index),
                                  ),
                                if (!thinking &&
                                    (message.canSwipe || isLastAi))
                                  _SwipePager(
                                    index: message.swipeIndex,
                                    total: message.swipes.length,
                                    onPrev: (!_busy && canGoPrev)
                                        ? () => _shiftSwipe(index, -1)
                                        : null,
                                    onNext: (!_busy && canGoNextExisting)
                                        ? () => _shiftSwipe(index, 1)
                                        : (canQuickSwipe
                                              ? () => _regenerateOrSwipe(
                                                    asNewSwipe: true,
                                                  )
                                            : null),
                                    nextGeneratesSwipe: canQuickSwipe,
                                  ),
                              ],
                            ),
                          );
                        }
                        final isLast = index == _messages.length - 1;
                        final thinking =
                            _busy && isLast && message.text.isEmpty;
                        final isLastAi = isLast && !message.isUser;
                        final canGoPrev =
                            !message.isUser &&
                            message.swipes.length > 1 &&
                            message.swipeIndex > 0;
                        final canGoNextExisting =
                            !message.isUser &&
                            message.swipes.length > 1 &&
                            message.swipeIndex < message.swipes.length - 1;
                        // On the latest AI bubble, ▶ past the last swipe = new generation.
                        final canQuickSwipe =
                            isLastAi &&
                            !thinking &&
                            !_busy &&
                            message.swipeIndex >= message.swipes.length - 1;
                        return Padding(
                          padding: EdgeInsets.symmetric(
                            vertical:
                                AnimaUiTheme.of(context).messageSpacing / 2,
                          ),
                          child: _MessageBubble(
                            message: message,
                            showThinking: thinking,
                            showSwipePager:
                                !message.isUser &&
                                !thinking &&
                                (message.canSwipe || isLastAi),
                            avatarFileName: _avatarForMessage(message),
                            avatarLabel: message.isUser
                                ? _userName
                                : (message.speakerName ??
                                      _character?.name ??
                                      'AI'),
                            avatarStyle: _avatarStyle,
                            onTap: (_busy || thinking)
                                ? null
                                : () => _editMessage(index),
                            onAvatarLongPress: _busy
                                ? null
                                : () {
                                    if (message.isUser) {
                                      _editPersonaFromAvatar();
                                    } else {
                                      _editCharacterFromAvatar(message);
                                    }
                                  },
                            onLongPress: _busy
                                ? null
                                : () => _showMessageMenu(index),
                            onSwipePrev: (!_busy && !thinking && canGoPrev)
                                ? () => _shiftSwipe(index, -1)
                                : null,
                            onSwipeNext:
                                (!_busy && !thinking && canGoNextExisting)
                                ? () => _shiftSwipe(index, 1)
                                : (canQuickSwipe
                                      ? () =>
                                            _regenerateOrSwipe(asNewSwipe: true)
                                      : null),
                            nextGeneratesSwipe: canQuickSwipe,
                          ),
                        );
                              },
                              childCount: _messages.length,
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            if (_summarizing)
              Material(
                color: colorScheme.surfaceContainerHigh,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Optimizing memory summary in the background…',
                          style: TextStyle(color: colorScheme.onSurface),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (_error != null)
              Material(
                color: colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.error_outline,
                        color: colorScheme.onErrorContainer,
                      ),
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
                padding: EdgeInsets.fromLTRB(
                  12,
                  keyboardOpen && compactComposer ? 4 : 8,
                  12,
                  keyboardOpen && compactComposer ? 8 : 12,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!keyboardOpen && (hasMemory || hasAuthorsNote || activeMoodCount > 0))
                      MinimalChipRow(
                        children: [
                          if (hasMemory)
                            MinimalChipButton(
                              label: 'Memory',
                              icon: Icons.psychology_outlined,
                              onPressed: _busy ? null : _editMemorySummary,
                            ),
                          if (hasMemory &&
                              ((_session?.authorsNote.trim().isNotEmpty ??
                                      false) ||
                                  activeMoodCount > 0))
                            const SizedBox(width: 8),
                          if (_session?.authorsNote.trim().isNotEmpty ?? false)
                            MinimalChipButton(
                              label: 'Note',
                              icon: Icons.edit_note,
                              onPressed: _busy ? null : _editAuthorsNote,
                            ),
                          if (activeMoodCount > 0) ...[
                            if (_session?.authorsNote.trim().isNotEmpty ?? false)
                              const SizedBox(width: 8),
                            MinimalChipButton(
                              label: 'Moods ($activeMoodCount)',
                              icon: Icons.mood_outlined,
                              onPressed: _busy ? null : _pickSceneMoods,
                            ),
                          ],
                        ],
                      ),
                    if (!keyboardOpen && !_directorMode)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _buildComposerVoiceRow(colorScheme),
                      ),
                    if (_composerVoiceCharacterId != null && !_directorMode)
                      Padding(
                        padding: EdgeInsets.only(
                          bottom: keyboardOpen ? 4 : 8,
                        ),
                        child: _buildComposerVoiceModeToggle(colorScheme),
                      ),
                    if (compactComposer)
                      Padding(
                        padding: EdgeInsets.only(
                          bottom: keyboardOpen ? 4 : 8,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: _directorMode
                                  ? FilledButton.tonalIcon(
                                      onPressed: _busy
                                          ? null
                                          : _toggleDirectorMode,
                                      icon: const Icon(
                                        Icons.control_camera,
                                        size: 18,
                                      ),
                                      label: const Text('Director on'),
                                      style: FilledButton.styleFrom(
                                        visualDensity: VisualDensity.compact,
                                      ),
                                    )
                                  : OutlinedButton.icon(
                                      onPressed: _busy
                                          ? null
                                          : _toggleDirectorMode,
                                      icon: const Icon(
                                        Icons.control_camera_outlined,
                                        size: 18,
                                      ),
                                      label: const Text('Director'),
                                      style: OutlinedButton.styleFrom(
                                        visualDensity: VisualDensity.compact,
                                        foregroundColor:
                                            colorScheme.onSurface,
                                        side: BorderSide(
                                          color: colorScheme.outline,
                                        ),
                                      ),
                                    ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: FilledButton.tonalIcon(
                                onPressed:
                                    _busy ? null : _continueScene,
                                icon: const Icon(
                                  Icons.play_arrow,
                                  size: 18,
                                ),
                                label: const Text('Continue'),
                                style: FilledButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (compactComposer)
                          IconButton(
                            tooltip: 'Composer tools',
                            onPressed: _busy
                                ? null
                                : _openComposerToolsSheet,
                            visualDensity: VisualDensity.compact,
                            color: activeMoodCount > 0
                                ? colorScheme.tertiary
                                : colorScheme.outline,
                            icon: const Icon(Icons.add_circle_outline),
                          )
                        else ...[
                          IconButton(
                            tooltip: activeMoodCount > 0
                                ? 'Scene moods ($activeMoodCount on)'
                                : 'Scene moods — steer tone for this chat',
                            onPressed:
                                _busy ? null : _pickSceneMoods,
                            visualDensity: VisualDensity.compact,
                            color: activeMoodCount > 0
                                ? colorScheme.tertiary
                                : colorScheme.outline,
                            icon: Icon(
                              activeMoodCount > 0
                                  ? Icons.mood
                                  : Icons.mood_outlined,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Narrator — scene voice & direction',
                            onPressed: _busy
                                ? null
                                : _openNarratorSheet,
                            visualDensity: VisualDensity.compact,
                            color: colorScheme.tertiary,
                            icon: const Icon(Icons.theater_comedy_outlined),
                          ),
                          _directorMode
                              ? IconButton.filledTonal(
                                  tooltip:
                                      'Director on — your note commands the next reply',
                                  onPressed: _busy
                                      ? null
                                      : _toggleDirectorMode,
                                  visualDensity: VisualDensity.compact,
                                  icon: const Icon(Icons.control_camera),
                                )
                              : IconButton(
                                  tooltip:
                                      'Director off — normal roleplay send',
                                  onPressed: _busy
                                      ? null
                                      : _toggleDirectorMode,
                                  visualDensity: VisualDensity.compact,
                                  color: colorScheme.outline,
                                  icon: const Icon(
                                    Icons.control_camera_outlined,
                                  ),
                                ),
                        ],
                        Expanded(
                          child: ChatComposerField(
                            key: const ValueKey('chat_composer'),
                            controller: _inputController,
                            focusNode: _composerFocusNode,
                            enabled: !_busy,
                            enterToSend: _enterToSend,
                            minLines: compactComposer && keyboardOpen ? 2 : 1,
                            maxLines: compactComposer && keyboardOpen ? 8 : 5,
                            decoration: InputDecoration(
                              hintText: _composerHintText(characterName),
                              filled: true,
                              border: OutlineInputBorder(
                                borderSide: BorderSide(
                                  color: _composerBorderColor(colorScheme),
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderSide: BorderSide(
                                  color: _composerBorderColor(colorScheme),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderSide: BorderSide(
                                  color: _composerVoiceCharacterId != null
                                      ? (_composerVoiceGuideMode
                                          ? colorScheme.secondary
                                          : colorScheme.tertiary)
                                      : colorScheme.primary,
                                  width: (_directorMode ||
                                          _composerVoiceCharacterId != null)
                                      ? 2
                                      : 1,
                                ),
                              ),
                              isDense: true,
                            ),
                            onSend: _send,
                            onContinue: isDesktopPlatform && _enterToSend
                                ? _onComposerContinue
                                : null,
                          ),
                        ),
                        const SizedBox(width: 2),
                        if (_busy)
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
                        else if (compactComposer)
                          FilledButton(
                            onPressed: _send,
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.all(14),
                              minimumSize: const Size(48, 48),
                            ),
                            child: const Icon(Icons.send),
                          )
                        else ...[
                          IconButton(
                            tooltip: 'Continue',
                            visualDensity: VisualDensity.compact,
                            onPressed: _continueScene,
                            icon: const Icon(Icons.play_arrow),
                          ),
                          FilledButton(
                            onPressed: _send,
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.all(14),
                              minimumSize: const Size(48, 48),
                            ),
                            child: const Icon(Icons.send),
                          ),
                        ],
                      ],
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

  Future<void> _showMessageMenu(int index) async {
    if (_busy || index < 0 || index >= _messages.length) return;
    final message = _messages[index];
    final canRewind = index < _messages.length - 1;
    final isLast = index == _messages.length - 1;
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
                ListTile(
                  leading: const Icon(Icons.alt_route),
                  title: const Text('Paths'),
                  subtitle: const Text(
                    'Brainstorm what you could do or say next',
                  ),
                  onTap: () => Navigator.pop(context, 'paths'),
                ),
                if (!message.isUser && !message.isNarrator) ...[
                  ListTile(
                    leading: const Icon(Icons.refresh),
                    title: Text(
                      message.isGroupBeat
                          ? 'Regenerate group react'
                          : 'Regenerate',
                    ),
                    subtitle: Text(
                      isLast
                          ? message.isGroupBeat
                              ? 'Generate this group react again'
                              : 'Generate this reply again'
                          : 'Removes later messages, then regenerates',
                    ),
                    onTap: () => Navigator.pop(context, 'regen'),
                  ),
                  if (!message.isGroupBeat)
                    ListTile(
                      leading: const Icon(Icons.tune),
                      title: const Text('Rewrite reply…'),
                      subtitle: const Text(
                        'Shorten, expand, change mood, or custom',
                      ),
                      onTap: () => Navigator.pop(context, 'rewrite'),
                    ),
                ],
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.call_split_outlined),
                  title: const Text('Branch from here'),
                  subtitle: const Text(
                    'New chat with history up to this message',
                  ),
                  onTap: () => Navigator.pop(context, 'branch'),
                ),
                ListTile(
                  leading: const Icon(Icons.theater_comedy_outlined),
                  title: const Text('Narrator'),
                  subtitle: const Text(
                    'Omniscient scene voice — edit or nudge before posting',
                  ),
                  onTap: () => Navigator.pop(context, 'narrator'),
                ),
                ListTile(
                  leading: const Icon(Icons.play_arrow),
                  title: const Text('Continue'),
                  subtitle: const Text('Generate the next reply'),
                  onTap: () => Navigator.pop(context, 'continue'),
                ),
                ListTile(
                  leading: const Icon(Icons.record_voice_over_outlined),
                  title: const Text('Impersonate'),
                  subtitle: const Text('Write your next line as you'),
                  onTap: () => Navigator.pop(context, 'impersonate'),
                ),
                if (_isGroup && _participants.length >= 2)
                  ListTile(
                    leading: const Icon(Icons.groups_outlined),
                    title: const Text('Group react…'),
                    subtitle: const Text(
                      'Brief simultaneous reactions from several characters',
                    ),
                    onTap: () => Navigator.pop(context, 'group_react'),
                  ),
                ListTile(
                  leading: Icon(
                    (_session?.autoReply ?? false)
                        ? Icons.forum_outlined
                        : Icons.chat_bubble_outline,
                  ),
                  title: Text(
                    (_session?.autoReply ?? false)
                        ? 'Auto-reply: on'
                        : 'Auto-reply: off',
                  ),
                  subtitle: Text(
                    (_session?.autoReply ?? false)
                        ? 'Tap to turn off — send without an AI reply'
                        : 'Tap to turn on — characters answer when you send',
                  ),
                  onTap: () => Navigator.pop(context, 'auto_reply'),
                ),
                if (!message.isUser && !message.isNarrator)
                  ListTile(
                    leading: const Icon(Icons.auto_awesome),
                    title: Text(
                      message.isGroupBeat ? 'New group react swipe' : 'New swipe',
                    ),
                    subtitle: Text(
                      message.isGroupBeat
                          ? 'Generate another alternate group react'
                          : 'Generate another alternate reply',
                    ),
                    onTap: () => Navigator.pop(context, 'swipe'),
                  ),
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

    if (action == 'delete') await _deleteMessage(index);
    if (action == 'rewind') await _rewindToMessage(index);
    if (action == 'branch') await _branchFromMessage(index);
    if (action == 'narrator') await _openNarratorSheet();
    if (action == 'continue') await _continueScene();
    if (action == 'impersonate') await _impersonate();
    if (action == 'paths') await _showPathsSheet();
    if (action == 'group_react') await _openGroupReplySheet();
    if (action == 'auto_reply') await _toggleAutoReply();
    if (action == 'regen') {
      await _regenerateMessageAt(index, asNewSwipe: false);
    }
    if (action == 'swipe') {
      await _regenerateMessageAt(index, asNewSwipe: true);
    }
    if (action == 'rewrite') await _rewriteMessageAt(index);
    if (action == 'swipe_prev') _shiftSwipe(index, -1);
    if (action == 'swipe_next') _shiftSwipe(index, 1);
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
    this.showSwipePager = false,
    this.avatarFileName,
    this.avatarLabel = '',
    this.avatarStyle = const AvatarStyleSettings(),
    this.onTap,
    this.onAvatarLongPress,
    this.onLongPress,
    this.onSwipePrev,
    this.onSwipeNext,
    this.nextGeneratesSwipe = false,
  });

  final ChatMessage message;
  final bool showThinking;
  final bool showSwipePager;
  final String? avatarFileName;
  final String avatarLabel;
  final AvatarStyleSettings avatarStyle;
  final VoidCallback? onTap;
  final VoidCallback? onAvatarLongPress;
  final VoidCallback? onLongPress;
  final VoidCallback? onSwipePrev;
  final VoidCallback? onSwipeNext;
  final bool nextGeneratesSwipe;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final ui = AnimaUiTheme.of(context);
    final exp = ui.chatExperience;
    final storybook = exp.isStorybook;
    final showHeader = exp.showSpeakerHeader;
    final showHero = storybook && exp.showSideHeroPortrait;
    final isUser = message.isUser;
    final alignment = isUser ? Alignment.centerRight : Alignment.centerLeft;
    final background = exp.bubbleFill(
      isUser ? ui.userBubbleColor : ui.aiBubbleColor,
    );
    final foreground = isUser ? ui.userBubbleForeground : ui.aiBubbleForeground;
    final bubbleRadius = BorderRadius.circular(ui.chatBubbleRadius);
    final chatFontSize =
        (Theme.of(context).textTheme.bodyLarge?.fontSize ?? 16) *
        ui.chatFontScale;
    final maxBubbleWidth = storybook ? 0.88 : 0.68;
    final borderColor = isUser
        ? colorScheme.primary.withValues(alpha: 0.55)
        : colorScheme.primary.withValues(alpha: 0.18);
    final boxShadow = [
      BoxShadow(
        color: isUser
            ? colorScheme.primary.withValues(alpha: 0.22)
            : ui.bubbleShadowColor,
        blurRadius: isUser ? 14 : 10,
        offset: const Offset(0, 3),
      ),
    ];

    final messageContent = showThinking
        ? Row(
            mainAxisSize: MainAxisSize.min,
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
                message.speakerName?.trim().isNotEmpty == true
                    ? '${message.speakerName} is typing…'
                    : 'Thinking…',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          )
        : RpRichText(
            text: !isUser
                ? stripLeadingSpeakerPrefix(
                    message.text,
                    message.speakerName,
                  )
                : message.text,
            isUser: isUser,
            baseStyle: Theme.of(context).textTheme.bodyLarge!.copyWith(
                  color: foreground,
                  height: storybook ? 1.55 : 1.4,
                  fontSize: chatFontSize,
                ),
          );

    final speakerName = isUser
        ? avatarLabel
        : (message.speakerName?.trim().isNotEmpty == true
            ? message.speakerName!.trim()
            : avatarLabel);

    final avatarWidget = AnimaAvatar(
      fileName: avatarFileName,
      label: avatarLabel,
      style: storybook
          ? AvatarStyleSettings(
              shape: avatarStyle.shape,
              sizeTier: AvatarSizeTier.small,
              scale: 0.85,
            )
          : avatarStyle,
      icon: isUser ? Icons.person : Icons.smart_toy_outlined,
      onLongPress: onAvatarLongPress,
    );
    final avatar = onAvatarLongPress == null
        ? avatarWidget
        : Tooltip(
            message: isUser
                ? 'Tap portrait · long-press to edit persona'
                : 'Tap portrait · long-press to edit character',
            child: avatarWidget,
          );

    final textPad = showHero
        ? EdgeInsets.fromLTRB(isUser ? 6 : 14, 10, isUser ? 14 : 6, 10)
        : const EdgeInsets.symmetric(horizontal: 14, vertical: 10);

    final Widget bubble;
    if (showHero) {
      final heroStrip = ChatHeroPortraitStrip(
        fileName: avatarFileName,
        label: avatarLabel,
        portraitOnStart: isUser,
        icon: isUser ? Icons.person : Icons.smart_toy_outlined,
        onLongPress: onAvatarLongPress,
      );

      bubble = ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * maxBubbleWidth,
        ),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            color: background,
            borderRadius: bubbleRadius,
            border: Border.all(color: borderColor),
            boxShadow: boxShadow,
          ),
          clipBehavior: Clip.antiAlias,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: isUser
                ? [
                    heroStrip,
                    Flexible(
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: showThinking ? null : onTap,
                          onLongPress: showThinking ? null : onLongPress,
                          borderRadius: BorderRadius.horizontal(
                            right: Radius.circular(ui.chatBubbleRadius),
                          ),
                          child: Padding(
                            padding: textPad,
                            child: messageContent,
                          ),
                        ),
                      ),
                    ),
                  ]
                : [
                    Flexible(
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: showThinking ? null : onTap,
                          onLongPress: showThinking ? null : onLongPress,
                          borderRadius: BorderRadius.horizontal(
                            left: Radius.circular(ui.chatBubbleRadius),
                          ),
                          child: Padding(
                            padding: textPad,
                            child: messageContent,
                          ),
                        ),
                      ),
                    ),
                    heroStrip,
                  ],
          ),
        ),
      );
    } else {
      bubble = ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * maxBubbleWidth,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: showThinking ? null : onTap,
            onLongPress: showThinking ? null : onLongPress,
            borderRadius: bubbleRadius,
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 4),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: background,
                borderRadius: bubbleRadius,
                border: Border.all(color: borderColor),
                boxShadow: boxShadow,
              ),
              child: messageContent,
            ),
          ),
        ),
      );
    }

    final column = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: isUser
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        if (showHeader) ...[
          Padding(
            padding: const EdgeInsets.only(left: 2, right: 2, bottom: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                avatar,
                const SizedBox(width: 8),
                Text(
                  speakerName,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
          ),
        ],
        bubble,
        if (showSwipePager)
          _SwipePager(
            index: message.swipeIndex,
            total: message.swipes.length,
            onPrev: onSwipePrev,
            onNext: onSwipeNext,
            nextGeneratesSwipe: nextGeneratesSwipe,
          ),
      ],
    );

    if (storybook) {
      return Align(
        alignment: alignment,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: column,
        ),
      );
    }

    return Align(
      alignment: alignment,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: isUser
              ? [column, if (!showHeader) ...[const SizedBox(width: 8), avatar]]
              : [if (!showHeader) ...[avatar, const SizedBox(width: 8)], column],
        ),
      ),
    );
  }
}

/// Compact swipe picker: ◀ 1/3 ▶
///
/// On the latest AI message, ▶ past the last version generates a new swipe.
class _SwipePager extends StatelessWidget {
  const _SwipePager({
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

/// Self-contained Paths sheet — owns its own loading/options so generating
/// never calls setState on the chat screen under an open modal (that caused
/// `_dependents.isEmpty` crashes).
///
/// Generated options are cached per chat (and scene) so closing the sheet and
/// reopening it does not force another NanoGPT call.
class _PathsSheet extends StatefulWidget {
  const _PathsSheet({
    required this.chatId,
    required this.nanoGptService,
    required this.settingsService,
    required this.recentMessages,
    required this.userName,
    required this.characterName,
    required this.generationBlocked,
  });

  final String chatId;
  final NanoGptService nanoGptService;
  final SettingsService settingsService;
  final List<ChatMessage> recentMessages;
  final String userName;
  final String characterName;
  final bool generationBlocked;

  @override
  State<_PathsSheet> createState() => _PathsSheetState();
}

class _PathsSheetState extends State<_PathsSheet> {
  static const _roadway = RoadwayService();
  final _cache = RoadwayCacheService();

  bool _loading = false;
  bool _combining = false;
  bool _restoring = true;
  List<String> _options = const [];
  final Set<int> _selected = <int>{};

  String get _anchorMessageId {
    if (widget.recentMessages.isEmpty) return '';
    return widget.recentMessages.last.id;
  }

  bool get _busy => _loading || _combining || _restoring;

  List<String> get _selectedOptions {
    final out = <String>[];
    for (final i in _selected.toList()..sort()) {
      if (i < 0 || i >= _options.length) continue;
      final text = _options[i].trim();
      if (text.isNotEmpty) out.add(text);
    }
    return out;
  }

  @override
  void initState() {
    super.initState();
    _restoreCached();
  }

  Future<void> _restoreCached() async {
    final cached = await _cache.loadOptions(
      widget.chatId,
      anchorMessageId: _anchorMessageId,
    );
    if (!mounted) return;
    setState(() {
      if (cached != null && cached.isNotEmpty) {
        _options = cached;
      }
      _selected.clear();
      _restoring = false;
    });
  }

  Future<void> _persistOptions(List<String> options) async {
    await _cache.saveOptions(
      widget.chatId,
      options: options,
      anchorMessageId: _anchorMessageId,
    );
  }

  Future<void> _clearOptions() async {
    setState(() {
      _options = const [];
      _selected.clear();
    });
    await _cache.clearOptions(widget.chatId);
  }

  void _toggleSelected(int index) {
    if (_busy || index < 0 || index >= _options.length) return;
    setState(() {
      if (_selected.contains(index)) {
        _selected.remove(index);
      } else {
        _selected.add(index);
      }
    });
  }

  Future<void> _generate() async {
    if (_busy || widget.generationBlocked) return;
    setState(() {
      _loading = true;
      _selected.clear();
    });
    try {
      final collaborator = await widget.settingsService
          .getCollaboratorSettings();
      final model = await widget.settingsService.getModel();
      final sampling = RoadwayService.generateSampling(
        await widget.settingsService.getSampling(),
      );
      final baseUrl = await widget.settingsService.getApiBaseUrl();
      final messages = _roadway.buildMessages(
        userName: widget.userName,
        characterName: widget.characterName,
        recentMessages: widget.recentMessages,
        roadwayNote: collaborator.roadwayNote,
      );
      final raw = await widget.nanoGptService.complete(
        model: model,
        messages: messages,
        baseUrl: baseUrl,
        sampling: sampling,
      );
      if (!mounted) return;
      final options = _roadway.parseOptions(
        raw,
        userName: widget.userName,
      );
      if (options.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Paths came back empty — try again.')),
        );
        setState(() {
          _options = const [];
          _selected.clear();
        });
        await _cache.clearOptions(widget.chatId);
        return;
      }
      setState(() {
        _options = options;
        _selected.clear();
      });
      await _persistOptions(options);
    } on NanoGptCancelledException {
      // Ignore.
    } on NanoGptException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Paths failed: $error')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _combineSelected() async {
    if (_busy || widget.generationBlocked) return;
    final selected = _selectedOptions;
    if (selected.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Check at least two paths to combine.')),
      );
      return;
    }

    setState(() => _combining = true);
    try {
      final collaborator = await widget.settingsService
          .getCollaboratorSettings();
      final model = await widget.settingsService.getModel();
      final sampling = RoadwayService.generateSampling(
        await widget.settingsService.getSampling(),
      );
      final baseUrl = await widget.settingsService.getApiBaseUrl();
      final messages = _roadway.buildCombineMessages(
        userName: widget.userName,
        characterName: widget.characterName,
        recentMessages: widget.recentMessages,
        selectedOptions: selected,
        roadwayNote: collaborator.roadwayNote,
      );
      if (messages.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Check at least two paths to combine.')),
        );
        return;
      }
      final raw = await widget.nanoGptService.complete(
        model: model,
        messages: messages,
        baseUrl: baseUrl,
        sampling: sampling,
      );
      if (!mounted) return;
      final combined = _roadway.parseCombinedMessage(
        raw,
        userName: widget.userName,
      );
      if (combined.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Combine came back empty — try again.')),
        );
        return;
      }
      Navigator.pop(context, combined);
    } on NanoGptCancelledException {
      // Ignore.
    } on NanoGptException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Combine failed: $error')));
    } finally {
      if (mounted) setState(() => _combining = false);
    }
  }

  Future<void> _editOption(int index) async {
    if (_busy || index < 0 || index >= _options.length) return;
    final controller = TextEditingController(text: _options[index]);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit path'),
        content: TextField(
          controller: controller,
          maxLines: 5,
          autofocus: true,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: 'What you might say or do…',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Use in composer'),
          ),
        ],
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
    if (result == null || !mounted || result.isEmpty) return;
    final next = List<String>.from(_options);
    next[index] = result;
    setState(() => _options = next);
    await _persistOptions(next);
    if (!mounted) return;
    Navigator.pop(context, result);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final height = MediaQuery.sizeOf(context).height * 0.7;
    final canCombine =
        _selectedOptions.length >= 2 && !_busy && !widget.generationBlocked;

    return SafeArea(
      child: SizedBox(
        height: height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Paths',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  if (_busy)
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  else
                    IconButton(
                      tooltip: _options.isEmpty
                          ? 'Generate story paths'
                          : 'Refresh paths',
                      onPressed: widget.generationBlocked ? null : _generate,
                      icon: Icon(
                        _options.isEmpty ? Icons.auto_awesome : Icons.refresh,
                      ),
                    ),
                  if (_options.isNotEmpty)
                    IconButton(
                      tooltip: 'Clear paths',
                      onPressed: _busy ? null : _clearOptions,
                      icon: const Icon(Icons.close),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'AI “what next?” options. Tap a path to use it, or check '
                'two or more and tap Combine. Closing this sheet keeps them '
                'until the chat moves on or you clear / refresh.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Expanded(
              child: _options.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _loading
                              ? 'Brainstorming paths…'
                              : _combining
                              ? 'Combining selected paths…'
                              : _restoring
                              ? 'Loading saved paths…'
                              : 'Tap ✨ to generate paths for this scene.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                      itemCount: _options.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, i) {
                        final selected = _selected.contains(i);
                        return Material(
                          color: colorScheme.surfaceContainerHighest.withValues(
                            alpha: 0.55,
                          ),
                          borderRadius: BorderRadius.circular(10),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: _busy
                                ? null
                                : () => Navigator.pop(context, _options[i]),
                            onLongPress: _busy ? null : () => _editOption(i),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Checkbox(
                                    value: selected,
                                    onChanged: _busy
                                        ? null
                                        : (_) => _toggleSelected(i),
                                  ),
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.only(top: 12),
                                      child: Text(_options[i]),
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Edit path',
                                    onPressed: _busy
                                        ? null
                                        : () => _editOption(i),
                                    icon: const Icon(
                                      Icons.edit_outlined,
                                      size: 18,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            if (_options.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: FilledButton.icon(
                  onPressed: canCombine ? _combineSelected : null,
                  icon: _combining
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.merge_type),
                  label: Text(
                    _combining
                        ? 'Combining…'
                        : _selected.isEmpty
                        ? 'Combine selected'
                        : 'Combine selected (${_selected.length})',
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
