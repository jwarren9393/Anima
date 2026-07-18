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
import '../models/ui_style_settings.dart';
import '../services/api_key_service.dart';
import '../services/character_category_service.dart';
import '../services/character_service.dart';
import '../services/chat_context_service.dart';
import '../services/chat_service.dart';
import '../services/chat_transcript_codec.dart';
import '../services/composer_draft_service.dart';
import '../services/lorebook_service.dart';
import '../services/message_formatter.dart';
import '../services/nanogpt_service.dart';
import '../services/persona_service.dart';
import '../services/prompt_builder.dart';
import '../services/roadway_cache_service.dart';
import '../services/roadway_service.dart';
import '../services/settings_service.dart';
import '../services/world_info_service.dart';
import '../services/world_workshop_service.dart';
import '../widgets/anima_avatar.dart';
import '../widgets/greeting_picker.dart';
import '../widgets/keyboard_inset.dart';
import '../widgets/preset_picker.dart';
import '../widgets/rp_rich_text.dart';
import 'characters_screen.dart';
import 'character_edit_screen.dart';
import 'group_chat_setup_screen.dart';
import 'persona_edit_screen.dart';
import 'personas_screen.dart';
import 'settings_screen.dart';

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
  final ChatSession initialSession;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  final _promptBuilder = const PromptBuilder();
  final _lorebookService = const LorebookService();
  final _contextService = const ChatContextService();
  final _transcriptCodec = ChatTranscriptCodec();
  final _draftService = ComposerDraftService();
  static const _formatter = MessageFormatter();

  bool _hasApiKey = false;
  bool _loading = true;
  bool _busy = false;
  bool _formatting = false;
  /// When on, Send wraps the message as `(OOC: …)` for out-of-character talk.
  bool _oocMode = false;
  AvatarStyleSettings _avatarStyle = const AvatarStyleSettings();
  String? _error;
  Character? _character;
  List<Character> _participants = const [];
  ChatSession? _session;
  Persona? _persona;
  double _keyboardInset = 0;
  Timer? _draftSaveTimer;
  String _lastSavedDraft = '';

  List<ChatMessage> get _messages => _session?.messages ?? const [];
  bool get _isGroup => _session?.isGroup == true;
  String get _userName =>
      _persona?.name.trim().isNotEmpty == true
          ? _persona!.name.trim()
          : SettingsService.defaultUserName;
  String? get _personaAvatarFileName => _persona?.avatarFileName;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _inputController.addListener(_onComposerChanged);
    _bootstrap();
  }

  @override
  void didChangeMetrics() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final inset = MediaQuery.viewInsetsOf(context).bottom;
      // Keyboard opening — keep the latest messages and composer in view.
      if (inset > _keyboardInset + 8) {
        _scrollToBottom();
      }
      _keyboardInset = inset;
    });
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
    await _draftService.saveDraft(session.id, text);
  }

  Future<void> _clearSavedDraft() async {
    _draftSaveTimer?.cancel();
    _draftSaveTimer = null;
    _lastSavedDraft = '';
    final session = _session;
    if (session == null) return;
    await _draftService.clearDraft(session.id);
  }

  Future<void> _bootstrap() async {
    final hasKey = await widget.apiKeyService.hasApiKey();
    var session = widget.initialSession;
    await widget.chatService.setActiveChatId(session.characterId, session.id);
    final character = await _resolveCharacterForSession(session);
    final uiStyle = await widget.settingsService.getUiStyle();
    var persona = await widget.personaService.resolve(session.personaId);
    // Bind persona onto older chats that never stored one.
    if (session.personaId == null || session.personaId != persona.id) {
      session = session.copyWith(personaId: persona.id);
      await widget.chatService.saveChat(session);
    }
    final participants = await _resolveParticipants(session, character);
    final draft = await _draftService.loadDraft(session.id);
    if (!mounted) return;
    if (draft.isNotEmpty) {
      _inputController.text = draft;
      _inputController.selection = TextSelection.collapsed(offset: draft.length);
      _lastSavedDraft = draft;
    }
    setState(() {
      _hasApiKey = hasKey;
      _character = character;
      _participants = participants;
      _session = session;
      _avatarStyle = uiStyle.avatarStyle;
      _persona = persona;
      _loading = false;
    });
    _scrollToBottom(jump: true);
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
    if (!session.isGroup) return [fallback];
    final all = await widget.characterService.loadCharacters();
    final byId = {for (final c in all) c.id: c};
    final resolved = <Character>[];
    for (final id in session.effectiveParticipantIds) {
      final c = byId[id];
      if (c != null) resolved.add(c);
    }
    return resolved.isEmpty ? [fallback] : resolved;
  }

  Character _speakerForTurn() {
    final session = _session;
    if (session == null || !_isGroup || _participants.isEmpty) {
      return _character!;
    }
    final index =
        session.nextSpeakerIndex.clamp(0, _participants.length - 1);
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

  Future<void> _persist() async {
    final session = _session;
    if (session == null) return;
    await widget.chatService.saveChat(session);
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
    final hasKey = await widget.apiKeyService.hasApiKey();
    final uiStyle = await widget.settingsService.getUiStyle();
    final persona =
        await widget.personaService.resolve(_session?.personaId);
    if (!mounted) return;
    setState(() {
      _hasApiKey = hasKey;
      _avatarStyle = uiStyle.avatarStyle;
      _persona = persona;
    });
  }

  Future<void> _pickPersona() async {
    if (_busy || _session == null) return;
    final chosen = await Navigator.of(context).push<Persona>(
      MaterialPageRoute(
        builder: (_) => PersonasScreen(
          personaService: widget.personaService,
          pickForChat: true,
          selectedPersonaId: _session?.personaId ?? _persona?.id,
        ),
      ),
    );
    if (chosen == null || !mounted) return;
    final updated = _session!.copyWith(personaId: chosen.id);
    await widget.chatService.saveChat(updated);
    if (!mounted) return;
    setState(() {
      _session = updated;
      _persona = chosen;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('This chat now uses “${chosen.name}”.')),
    );
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
        ),
      ),
    );
    if (updated == null || !mounted) return;

    setState(() {
      if (_character?.id == updated.id) {
        _character = updated;
      }
      _participants = [
        for (final c in _participants) c.id == updated.id ? updated : c,
      ];
      // Solo chats always keep the edited card as primary.
      if (!_isGroup) {
        _character = updated;
        _participants = [updated];
      }
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Updated “${updated.name}” — next replies use the new card.',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// Tap your avatar → edit this chat’s persona.
  Future<void> _editPersonaFromAvatar() async {
    if (_busy) return;
    final persona = _persona;
    if (persona == null) return;

    final updated = await Navigator.of(context).push<Persona>(
      MaterialPageRoute(
        builder: (_) => PersonaEditScreen(
          personaService: widget.personaService,
          existing: persona,
        ),
      ),
    );
    if (updated == null || !mounted) return;

    setState(() => _persona = updated);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Updated persona “${updated.name}” — next replies use it.',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
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
      personaId: _persona?.id ??
          (await widget.personaService.getActivePersona()).id,
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
        personaId: _persona?.id,
        authorsNote: _session?.authorsNote ?? '',
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
      personaId: _persona?.id,
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
    final draft = await _draftService.loadDraft(session.id);
    if (!mounted) return;
    _inputController.text = draft;
    _inputController.selection = TextSelection.collapsed(offset: draft.length);
    _lastSavedDraft = draft;
    setState(() {
      if (character != null) _character = character;
      if (participants != null) _participants = participants;
      _session = session;
      _error = null;
    });
    _scrollToBottom(jump: true);
  }

  Future<void> _pickChat() async {
    final character = _character;
    if (character == null || _busy) return;
    final solo = await widget.chatService.listChats(character.id);
    final groups = await widget.chatService.listGroupChats();
    final chats = [...groups, ...solo];
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
            final prefix = chat.isGroup ? 'Group · ' : '';
            return ListTile(
              selected: selected,
              title: Text('$prefix${chat.title}'),
              subtitle: Text(
                '${chat.messages.length} messages · ${_shortDate(chat.updatedAt)}'
                '${chat.authorsNote.trim().isEmpty ? '' : ' · Note'}',
              ),
              trailing: selected ? const Icon(Icons.check) : null,
              onTap: () => Navigator.pop(context, chat),
            );
          },
        );
      },
    );

    if (chosen == null || !mounted) return;
    await _flushDraftNow();
    await widget.chatService.setActiveChatId(chosen.characterId, chosen.id);
    final fallback = _character!;
    final participants = await _resolveParticipants(chosen, fallback);
    final primary = chosen.isGroup
        ? (participants.isNotEmpty ? participants.first : fallback)
        : (await widget.characterService.getById(chosen.characterId)) ??
            fallback;
    if (!mounted) return;
    await _applySession(
      chosen,
      participants: participants,
      character: primary,
    );
  }

  Future<void> _exportChat() async {
    final session = _session;
    final character = _character;
    if (session == null || character == null || _busy) return;
    if (session.messages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nothing to export yet.')),
      );
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
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: $error')),
      );
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
      final bytes = file.bytes ??
          (file.path != null ? await File(file.path!).readAsBytes() : null);
      if (bytes == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not read that file.')),
        );
        return;
      }

      final userName = _userName;
      final imported = _transcriptCodec.parseBytes(
        bytes,
        characterId: character.id,
        characterName: character.name,
        userName: userName,
      );

      final withPersona = imported.copyWith(personaId: _persona?.id);
      await widget.chatService.saveChat(withPersona);
      await widget.chatService.setActiveChatId(character.id, withPersona.id);
      if (!mounted) return;
      setState(() {
        _session = withPersona;
        _error = null;
      });
      _scrollToBottom(jump: true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Imported “${withPersona.title}” (${withPersona.messages.length} messages).',
          ),
        ),
      );
    } on FormatException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Import failed: $error')),
      );
    }
  }

  String _shortDate(DateTime value) {
    final local = value.toLocal();
    return '${local.month}/${local.day} ${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _send() async {
    var text = _inputController.text.trim();
    if (text.isEmpty ||
        _busy ||
        _formatting ||
        _session == null ||
        _character == null) {
      return;
    }

    if (!_hasApiKey) {
      setState(() {
        _error = 'Add your NanoGPT API key in Settings before you can chat.';
      });
      return;
    }

    if (_oocMode) {
      text = _wrapOoc(text);
    }

    FocusScope.of(context).unfocus();
    _inputController.clear();
    await _clearSavedDraft();

    final autoReply = _session!.autoReply;
    final speaker = _speakerForTurn();
    final userMessage = ChatMessage(
      id: ChatMessage.newId(),
      role: ChatRole.user,
      text: text,
    );

    setState(() {
      _error = null;
      _session!.messages.add(userMessage);
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
    _scrollToBottom();
    await _persist();
    if (!autoReply) return;

    await _streamIntoLastAssistant(
      excludeLastAssistant: true,
      speakingAs: speaker,
      advanceGroupSpeaker: _isGroup,
    );
  }

  /// Wraps plain text as out-of-character. Skips if already tagged.
  String _wrapOoc(String text) {
    final trimmed = text.trim();
    final lower = trimmed.toLowerCase();
    if (lower.startsWith('(ooc:') ||
        lower.startsWith('(ooc ') ||
        lower.startsWith('ooc:')) {
      return trimmed;
    }
    return '(OOC: $trimmed)';
  }

  void _toggleOocMode() {
    setState(() => _oocMode = !_oocMode);
  }

  Future<void> _toggleAutoReply() async {
    if (_busy || _session == null) return;
    final next = !_session!.autoReply;
    setState(() {
      _session = _session!.copyWith(autoReply: next);
    });
    await _persist();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          next
              ? 'Auto-reply on — characters answer when you send.'
              : 'Auto-reply off — send only; tap a name or Continue for a reply.',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// Pick who speaks next. In a group with auto-reply off, tapping a name
  /// after your message also generates that character's reply.
  Future<void> _selectSpeaker(int index) async {
    if (_busy || _session == null) return;
    if (index < 0 || index >= _participants.length) return;

    setState(() {
      _session = _session!.copyWith(nextSpeakerIndex: index);
    });
    await _persist();

    final waitingForReply =
        !_session!.autoReply &&
        _messages.isNotEmpty &&
        _messages.last.isUser;
    if (!waitingForReply) return;

    if (!_hasApiKey) {
      setState(() {
        _error = 'Add your NanoGPT API key in Settings before you can chat.';
      });
      return;
    }

    final speaker = _participants[index];
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
    _scrollToBottom();
    await _persist();
    await _streamIntoLastAssistant(
      excludeLastAssistant: true,
      speakingAs: speaker,
      advanceGroupSpeaker: true,
    );
  }

  Future<void> _continueScene() async {
    if (_busy || _formatting || _session == null || _character == null) return;
    if (!_hasApiKey) {
      setState(() {
        _error = 'Add your NanoGPT API key in Settings before you can chat.';
      });
      return;
    }
    final speaker = _speakerForTurn();
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
    _scrollToBottom();
    await _persist();
    await _streamIntoLastAssistant(
      excludeLastAssistant: true,
      mode: PromptMode.continueScene,
      speakingAs: speaker,
      advanceGroupSpeaker: _isGroup,
    );
  }

  /// AI-formats the composer draft with *actions* and "dialogue".
  Future<void> _formatDraft() async {
    if (_busy || _formatting || _session == null) return;
    final draft = _inputController.text.trim();
    if (draft.isEmpty) return;
    if (!_hasApiKey) {
      setState(() {
        _error = 'Add your NanoGPT API key in Settings before you can format.';
      });
      return;
    }

    setState(() {
      _formatting = true;
      _error = null;
    });
    try {
      final collaborator =
          await widget.settingsService.getCollaboratorSettings();
      final model = await widget.settingsService.getModel();
      final sampling = await widget.settingsService.getSampling();
      // Cooler sampling = less “creative rewrite,” closer to the draft.
      final formatSampling = sampling.copyWith(
        temperature: sampling.temperature > 0.35 ? 0.35 : sampling.temperature,
      );
      final baseUrl = await widget.settingsService.getApiBaseUrl();
      final charName = _character?.name.trim().isNotEmpty == true
          ? _character!.name.trim()
          : 'Character';
      final messages = _formatter.buildMessages(
        draft: draft,
        userName: _userName,
        characterName: charName,
        recentMessages: _messages,
        formatNote: collaborator.composerFormatNote,
      );
      final formatted = await widget.nanoGptService.complete(
        model: model,
        messages: messages,
        baseUrl: baseUrl,
        sampling: formatSampling,
      );
      if (!mounted) return;
      _inputController.text = formatted.trim();
      _inputController.selection = TextSelection.collapsed(
        offset: _inputController.text.length,
      );
    } on NanoGptCancelledException {
      // Ignore.
    } on NanoGptException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Format failed: $error')),
      );
    } finally {
      if (mounted) setState(() => _formatting = false);
    }
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Need a bit of chat first.')),
      );
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
        generationBlocked: _busy || _formatting,
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
    _scrollToBottom();
    await _persist();
    await _streamIntoLastAssistant(
      excludeLastAssistant: true,
      mode: PromptMode.impersonate,
    );
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
                  'Use a preset or write your own.',
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
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.trim().isEmpty
              ? "Author's Note cleared."
              : "Author's Note saved for this chat.",
        ),
      ),
    );
  }

  Future<void> _editMemorySummary() async {
    final session = _session;
    if (session == null || _busy) return;
    final controller = TextEditingController(text: session.memorySummary);
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Memory summary'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Older story beats the AI should remember. Sent with each '
                  'reply. Covered messages: ${session.memoryCoveredCount}. '
                  'Edit anytime, or clear to start fresh.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  minLines: 6,
                  maxLines: 14,
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: 'Story so far…',
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
            TextButton(
              onPressed: () => Navigator.pop(context, ''),
              child: const Text('Clear'),
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
    final trimmed = result.trim();
    setState(() {
      _session = session.copyWith(
        memorySummary: trimmed,
        memoryCoveredCount: trimmed.isEmpty ? 0 : session.memoryCoveredCount,
      );
    });
    await _persist();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          trimmed.isEmpty ? 'Memory summary cleared.' : 'Memory summary saved.',
        ),
      ),
    );
  }

  Future<void> _summarizeNow({bool quiet = false}) async {
    final session = _session;
    if (session == null || _character == null) return;
    if (_busy) return;
    if (!_hasApiKey) {
      setState(() {
        _error = 'Add your NanoGPT API key in Settings before summarizing.';
      });
      return;
    }

    final contextSettings = await widget.settingsService.getContextSettings();
    final cut = _contextService.summarizeCutIndex(
      messageCount: _messages.length,
      memoryCoveredCount: session.memoryCoveredCount,
      summarizeKeepRecent: contextSettings.summarizeKeepRecent,
    );
    if (cut <= session.memoryCoveredCount) {
      if (!quiet && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Not enough older messages to summarize yet. Chat more, or lower '
              '“Keep recent” in Generation parameters.',
            ),
          ),
        );
      }
      return;
    }

    final chunk = _messages.sublist(session.memoryCoveredCount, cut);
    setState(() {
      _busy = true;
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
        ),
        baseUrl: baseUrl,
        sampling: sampling,
      );
      if (!mounted) return;
      setState(() {
        _session = session.copyWith(
          memorySummary: updated.trim(),
          memoryCoveredCount: cut,
        );
        _busy = false;
      });
      await _persist();
      if (!quiet && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Memory updated (folded $cut messages). Edit via ⋮ → Memory summary.',
            ),
          ),
        );
      }
    } on NanoGptException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error.message;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Summarize failed: $error';
      });
    }
  }

  Future<void> _maybeAutoSummarize() async {
    final session = _session;
    if (session == null || _busy) return;
    final contextSettings = await widget.settingsService.getContextSettings();
    if (!_contextService.shouldAutoSummarize(
      messageCount: _messages.length,
      memoryCoveredCount: session.memoryCoveredCount,
      context: contextSettings,
    )) {
      return;
    }
    await _summarizeNow(quiet: true);
  }

  Future<void> _startGroupChat() async {
    if (_busy) return;
    final session = await Navigator.of(context).push<ChatSession>(
      MaterialPageRoute(
        builder: (_) => GroupChatSetupScreen(
          characterService: widget.characterService,
          categoryService: widget.characterCategoryService,
          chatService: widget.chatService,
          personaService: widget.personaService,
          worldInfoService: widget.worldInfoService,
          preselectedIds: {
            if (_character != null) _character!.id,
          },
        ),
      ),
    );
    if (session == null || !mounted) return;
    await _flushDraftNow();
    final fallback = _character ??
        Character(id: session.characterId, name: 'Character');
    final participants = await _resolveParticipants(session, fallback);
    await _applySession(
      session,
      participants: participants,
      character: participants.isNotEmpty ? participants.first : fallback,
    );
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
          speakerId: last.speakerId,
          speakerName: last.speakerName,
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
          speakerId: last.speakerId,
          speakerName: last.speakerName,
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
    PromptMode mode = PromptMode.normal,
    Character? speakingAs,
  }) async {
    final character = speakingAs ?? _speakerForTurn();
    final userName = _userName;
    final persona = _persona?.description ?? '';

    final end = excludeLastAssistant ? _messages.length - 1 : _messages.length;
    final historyForScan = _messages.sublist(0, end);
    final loreSettings = await widget.settingsService.getLoreSettings();
    final extraBooks = await widget.worldInfoService.booksForChat(
      chatLorebookIds: _session?.lorebookIds,
    );
    final lore = _lorebookService.buildInjection(
      character: character,
      messages: historyForScan,
      extraBooks: extraBooks,
      scanDepthOverride: loreSettings.scanDepth,
      tokenBudgetOverride: loreSettings.tokenBudget,
    );

    final others = _participants.where((c) => c.id != character.id).toList();
    final system = _promptBuilder.buildSystemPrompt(
      character: character,
      userName: userName,
      userPersona: persona,
      lore: lore,
      others: others,
      mode: mode,
    );
    final postHistory = _promptBuilder.buildPostHistory(
      character: character,
      userName: userName,
      authorsNote: _session?.authorsNote ?? '',
    );

    final msgs = <Map<String, String>>[
      {'role': 'system', 'content': system},
    ];

    final memory = (_session?.memorySummary ?? '').trim();
    if (memory.isNotEmpty) {
      msgs.add({
        'role': 'system',
        'content': 'Memory summary (older story):\n$memory',
      });
    }

    final contextSettings = await widget.settingsService.getContextSettings();
    final history = _contextService.selectHistory(
      messages: _messages,
      endExclusive: end,
      memoryCoveredCount: _session?.memoryCoveredCount ?? 0,
      historyTokenBudget: contextSettings.historyTokenBudget,
      isGroup: _isGroup,
    );

    for (final message in history) {
      // Prefixed speaker names help group chats stay clear in the history.
      if (!message.isUser &&
          message.speakerName != null &&
          message.speakerName!.trim().isNotEmpty &&
          _isGroup) {
        msgs.add({
          'role': 'assistant',
          'content': '${message.speakerName}: ${message.text}',
        });
      } else {
        msgs.add(message.toApiMap());
      }
    }

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

    if (postHistory.isNotEmpty) {
      msgs.add({'role': 'system', 'content': postHistory});
    }
    return msgs;
  }

  Future<void> _streamIntoLastAssistant({
    required bool excludeLastAssistant,
    bool allowGreetingNudge = false,
    PromptMode mode = PromptMode.normal,
    Character? speakingAs,
    bool advanceGroupSpeaker = false,
  }) async {
    try {
      final model = await widget.settingsService.getModel();
      final sampling = await widget.settingsService.getSampling();
      final baseUrl = await widget.settingsService.getApiBaseUrl();
      final speaker = speakingAs ?? _speakerForTurn();
      final messages = await _buildApiMessages(
        excludeLastAssistant: excludeLastAssistant,
        allowGreetingNudge: allowGreetingNudge,
        mode: mode,
        speakingAs: speaker,
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
            role: last.role,
            text: text,
            swipes: swipes,
            swipeIndex: index,
            speakerId: last.speakerId ?? speaker.id,
            speakerName: last.speakerName ?? speaker.name,
          );
        });
        _scrollToBottom();
      }

      if (!mounted) return;
      final finalText = _messages.last.text.trim();
      if (finalText.isEmpty) {
        throw NanoGptException('NanoGPT returned an empty reply. Try again.');
      }
      if (advanceGroupSpeaker) {
        _advanceGroupSpeaker();
      }
      setState(() => _busy = false);
      await _persist();
      await _maybeAutoSummarize();
    } on NanoGptCancelledException {
      if (!mounted) return;
      await _finishStoppedGeneration(advanceGroupSpeaker: advanceGroupSpeaker);
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
      // Closing the HTTP client on Stop can surface as a network error.
      if (_looksLikeCancel(error)) {
        await _finishStoppedGeneration(advanceGroupSpeaker: advanceGroupSpeaker);
        return;
      }
      setState(() {
        _busy = false;
        _error = 'Something unexpected went wrong: $error';
      });
      await _persist();
    }
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
  }

  void _stopGeneration() {
    if (!_busy) return;
    widget.nanoGptService.cancelActiveStream();
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
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
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
    if (index < 0 || index >= _messages.length) return;
    setState(() => _session!.messages.removeAt(index));
    await _persist();
  }

  /// Keep messages through [index]; delete everything after.
  Future<void> _rewindToMessage(int index) async {
    if (_busy || _session == null) return;
    if (index < 0 || index >= _messages.length) return;
    if (index >= _messages.length - 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nothing after this message to remove.')),
      );
      return;
    }
    setState(() {
      _session!.messages.removeRange(index + 1, _session!.messages.length);
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

    final baseTitle = source.title.trim().isEmpty ? 'Chat' : source.title.trim();
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
    );

    await widget.chatService.saveChat(branched);
    await widget.chatService.setActiveChatId(branched.characterId, branched.id);
    if (!mounted) return;
    setState(() => _session = branched);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Branched to “${branched.title}”.')),
    );
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
    WidgetsBinding.instance.removeObserver(this);
    widget.nanoGptService.cancelActiveStream();
    _draftSaveTimer?.cancel();
    // Fire-and-forget final draft flush (async dispose is not allowed).
    final session = _session;
    final text = _inputController.text;
    if (session != null && text != _lastSavedDraft) {
      unawaited(_draftService.saveDraft(session.id, text));
    }
    _inputController.removeListener(_onComposerChanged);
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final characterName = _isGroup
        ? (_participants.map((c) => c.name).where((n) => n.isNotEmpty).join(', '))
        : (_character?.name ?? 'Anima');
    final titleName = _isGroup
        ? 'Group'
        : (_character?.name ?? 'Anima');
    return Scaffold(
      // We lift the body ourselves via [KeyboardInset] so the composer stays
      // above the keyboard even with a transparent glass scaffold.
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Close chat',
          icon: const Icon(Icons.close),
          onPressed: _loading || _busy ? null : () => Navigator.of(context).pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titleName),
            if (_session != null)
              Text(
                _isGroup ? characterName : _session!.title,
                style: Theme.of(context).textTheme.bodySmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
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
          PopupMenuButton<String>(
            tooltip: 'More',
            enabled: !_loading && !_busy,
            onSelected: (value) {
              if (value == 'persona') _pickPersona();
              if (value == 'authors_note') _editAuthorsNote();
              if (value == 'memory') _editMemorySummary();
              if (value == 'summarize') _summarizeNow();
              if (value == 'characters') _openCharacters();
              if (value == 'group') _startGroupChat();
              if (value == 'export') _exportChat();
              if (value == 'import') _importChat();
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
                value: 'characters',
                child: Text('Characters'),
              ),
              const PopupMenuItem(
                value: 'group',
                child: Text('Start group chat'),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'export',
                child: Text('Export chat'),
              ),
              const PopupMenuItem(
                value: 'import',
                child: Text('Import chat'),
              ),
              const PopupMenuItem(
                value: 'settings',
                child: Text('Settings'),
              ),
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
                      final thinking =
                          _busy && isLast && message.text.isEmpty;
                      final isLastAi = isLast && !message.isUser;
                      final canGoPrev = !message.isUser &&
                          message.swipes.length > 1 &&
                          message.swipeIndex > 0;
                      final canGoNextExisting = !message.isUser &&
                          message.swipes.length > 1 &&
                          message.swipeIndex < message.swipes.length - 1;
                      // On the latest AI bubble, ▶ past the last swipe = new generation.
                      final canQuickSwipe = isLastAi &&
                          !thinking &&
                          !_busy &&
                          message.swipeIndex >=
                              message.swipes.length - 1;
                      return Padding(
                        padding: EdgeInsets.symmetric(
                          vertical: AnimaUiTheme.of(context).messageSpacing / 2,
                        ),
                        child: _MessageBubble(
                        message: message,
                        showThinking: thinking,
                        showSwipePager: !message.isUser &&
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
                        onAvatarTap: _busy
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
                        onSwipeNext: (!_busy && !thinking && canGoNextExisting)
                            ? () => _shiftSwipe(index, 1)
                            : (canQuickSwipe
                                ? () => _regenerateOrSwipe(asNewSwipe: true)
                                : null),
                        nextGeneratesSwipe: canQuickSwipe,
                      ),
                      );
                    },
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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_isGroup)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (var i = 0; i < _participants.length; i++) ...[
                              if (i > 0) const SizedBox(width: 6),
                              InputChip(
                                label: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 140,
                                  ),
                                  child: Text(
                                    _participants[i].name.trim().isEmpty
                                        ? 'Character ${i + 1}'
                                        : _participants[i].name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                selected: (_session?.nextSpeakerIndex ?? 0)
                                        .clamp(0, _participants.length - 1) ==
                                    i,
                                onPressed:
                                    _busy ? null : () => _selectSpeaker(i),
                                visualDensity: VisualDensity.compact,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                labelPadding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Tooltip(
                        message: _oocMode
                            ? 'OOC on — message will send as (OOC: …)'
                            : 'OOC off — tap for out-of-character',
                        child: TextButton(
                          onPressed:
                              _busy || _formatting ? null : _toggleOocMode,
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 12,
                            ),
                            minimumSize: const Size(40, 48),
                            foregroundColor: _oocMode
                                ? colorScheme.primary
                                : colorScheme.outline,
                          ),
                          child: Text(
                            'OOC',
                            style: TextStyle(
                              fontWeight:
                                  _oocMode ? FontWeight.w700 : FontWeight.w500,
                              fontSize: 12,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: TextField(
                          controller: _inputController,
                          enabled: !_busy && !_formatting,
                          minLines: 1,
                          maxLines: 5,
                          textInputAction: .newline,
                          decoration: InputDecoration(
                            hintText: _oocMode
                                ? 'Out-of-character note…'
                                : _isGroup
                                    ? ((_session?.autoReply ?? false)
                                        ? 'Message the group…'
                                        : 'Send only — tap a name to reply…')
                                    : ((_session?.autoReply ?? false)
                                        ? 'Message $characterName…'
                                        : 'Send only — tap Continue or long-press…'),
                            filled: true,
                            border: const OutlineInputBorder(),
                            isDense: true,
                          ),
                          onSubmitted: (_) {
                            if (!_busy && !_formatting) _send();
                          },
                        ),
                      ),
                      const SizedBox(width: 4),
                      if (_busy)
                        FilledButton(
                          onPressed: _stopGeneration,
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.all(14),
                            minimumSize: const Size(48, 48),
                            backgroundColor:
                                Theme.of(context).colorScheme.error,
                            foregroundColor:
                                Theme.of(context).colorScheme.onError,
                          ),
                          child: const Icon(Icons.stop),
                        )
                      else ...[
                        IconButton(
                          tooltip: 'Format draft (*actions* and "dialogue")',
                          onPressed: _formatting ? null : _formatDraft,
                          icon: _formatting
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.auto_awesome),
                        ),
                        IconButton(
                          tooltip: 'Continue',
                          onPressed: _formatting ? null : _continueScene,
                          icon: const Icon(Icons.play_arrow),
                        ),
                        FilledButton(
                          onPressed: _formatting ? null : _send,
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
                  leading: const Icon(Icons.call_split_outlined),
                  title: const Text('Branch from here'),
                  subtitle: const Text(
                    'New chat with history up to this message',
                  ),
                  onTap: () => Navigator.pop(context, 'branch'),
                ),
                const Divider(),
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
                ListTile(
                  leading: const Icon(Icons.alt_route),
                  title: const Text('Paths'),
                  subtitle: const Text(
                    'Brainstorm what you could do or say next',
                  ),
                  onTap: () => Navigator.pop(context, 'paths'),
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
                if (!message.isUser && isLast) ...[
                  ListTile(
                    leading: const Icon(Icons.refresh),
                    title: const Text('Regenerate'),
                    onTap: () => Navigator.pop(context, 'regen'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.auto_awesome),
                    title: const Text('New swipe'),
                    subtitle: const Text('Generate another alternate reply'),
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

    if (action == 'delete') await _deleteMessage(index);
    if (action == 'rewind') await _rewindToMessage(index);
    if (action == 'branch') await _branchFromMessage(index);
    if (action == 'continue') await _continueScene();
    if (action == 'impersonate') await _impersonate();
    if (action == 'paths') await _showPathsSheet();
    if (action == 'auto_reply') await _toggleAutoReply();
    if (action == 'regen') await _regenerateOrSwipe(asNewSwipe: false);
    if (action == 'swipe') await _regenerateOrSwipe(asNewSwipe: true);
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
    this.onAvatarTap,
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
  final VoidCallback? onAvatarTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onSwipePrev;
  final VoidCallback? onSwipeNext;
  final bool nextGeneratesSwipe;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final ui = AnimaUiTheme.of(context);
    final isUser = message.isUser;
    final alignment = isUser ? Alignment.centerRight : Alignment.centerLeft;
    final background = isUser ? ui.userBubbleColor : ui.aiBubbleColor;
    final foreground =
        isUser ? colorScheme.onPrimary : colorScheme.onSurface;
    final bubbleRadius = BorderRadius.circular(ui.chatBubbleRadius);
    final chatFontSize =
        (Theme.of(context).textTheme.bodyLarge?.fontSize ?? 16) *
            ui.chatFontScale;

    final avatarCore = AnimaAvatar(
      fileName: avatarFileName,
      label: avatarLabel,
      style: avatarStyle,
      icon: isUser ? Icons.person : Icons.smart_toy_outlined,
    );
    final avatar = onAvatarTap == null
        ? avatarCore
        : Tooltip(
            message: isUser ? 'Edit persona' : 'Edit character card',
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onAvatarTap,
                customBorder: avatarStyle.shape == AvatarShape.circle
                    ? const CircleBorder()
                    : RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          avatarStyle.shape == AvatarShape.square ? 8 : 12,
                        ),
                      ),
                child: avatarCore,
              ),
            ),
          );

    final bubble = ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * 0.68,
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
              border: Border.all(
                color: isUser
                    ? colorScheme.primary.withValues(alpha: 0.55)
                    : colorScheme.primary.withValues(alpha: 0.18),
              ),
              boxShadow: [
                BoxShadow(
                  color: isUser
                      ? colorScheme.primary.withValues(alpha: 0.22)
                      : Colors.black.withValues(alpha: 0.35),
                  blurRadius: isUser ? 14 : 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: showThinking
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
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!isUser &&
                          message.speakerName != null &&
                          message.speakerName!.trim().isNotEmpty) ...[
                      Text(
                        message.speakerName!,
                        style: Theme.of(context)
                            .textTheme
                            .labelMedium
                            ?.copyWith(
                              color: colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      const SizedBox(height: 4),
                    ],
                    RpRichText(
                      text: message.text,
                      isUser: isUser,
                      baseStyle:
                          Theme.of(context).textTheme.bodyLarge!.copyWith(
                                color: foreground,
                                height: 1.4,
                                fontSize: chatFontSize,
                              ),
                    ),
                  ],
                ),
          ),
        ),
      ),
    );

    final column = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment:
          isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
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

    return Align(
      alignment: alignment,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: isUser
              ? [column, const SizedBox(width: 8), avatar]
              : [avatar, const SizedBox(width: 8), column],
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
      final collaborator =
          await widget.settingsService.getCollaboratorSettings();
      final model = await widget.settingsService.getModel();
      final sampling = await widget.settingsService.getSampling();
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
      final options = _roadway.parseOptions(raw);
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Paths failed: $error')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _combineSelected() async {
    if (_busy || widget.generationBlocked) return;
    final selected = _selectedOptions;
    if (selected.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Check at least two paths to combine.'),
        ),
      );
      return;
    }

    setState(() => _combining = true);
    try {
      final collaborator =
          await widget.settingsService.getCollaboratorSettings();
      final model = await widget.settingsService.getModel();
      final sampling = await widget.settingsService.getSampling();
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
          const SnackBar(
            content: Text('Check at least two paths to combine.'),
          ),
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
      final combined = _roadway.parseCombinedMessage(raw);
      if (combined.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Combine came back empty — try again.'),
          ),
        );
        return;
      }
      Navigator.pop(context, combined);
    } on NanoGptCancelledException {
      // Ignore.
    } on NanoGptException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Combine failed: $error')),
      );
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
    final canCombine = _selectedOptions.length >= 2 &&
        !_busy &&
        !widget.generationBlocked;

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
                      onPressed:
                          widget.generationBlocked ? null : _generate,
                      icon: Icon(
                        _options.isEmpty
                            ? Icons.auto_awesome
                            : Icons.refresh,
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
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
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
                          color: colorScheme.surfaceContainerHighest
                              .withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(10),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: _busy
                                ? null
                                : () => Navigator.pop(context, _options[i]),
                            onLongPress:
                                _busy ? null : () => _editOption(i),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(
                                4,
                                8,
                                4,
                                8,
                              ),
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
                                    onPressed:
                                        _busy ? null : () => _editOption(i),
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
