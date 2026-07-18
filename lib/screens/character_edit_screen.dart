import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/character.dart';
import '../models/lorebook.dart';
import '../services/avatar_prompt_builder.dart';
import '../services/avatar_service.dart';
import '../services/character_collaborator.dart';
import '../services/character_service.dart';
import '../services/nanogpt_service.dart';
import '../services/settings_service.dart';
import '../widgets/anima_avatar.dart';
import '../widgets/generate_avatar_sheet.dart';
import '../widgets/keyboard_inset.dart';
import '../widgets/preset_picker.dart';
import '../models/anima_presets.dart';
import 'lorebook_edit_screen.dart';

/// Form to create/edit a SillyTavern-style character card.
class CharacterEditScreen extends StatefulWidget {
  const CharacterEditScreen({
    super.key,
    required this.characterService,
    required this.settingsService,
    required this.nanoGptService,
    this.existing,
    this.generatedDraft = false,
    this.updatingExisting = false,
  });

  final CharacterService characterService;
  final SettingsService settingsService;
  final NanoGptService nanoGptService;
  final Character? existing;

  /// True when opened from Creation Center (or similar) with AI-filled fields
  /// that are not saved until the user taps Save.
  final bool generatedDraft;

  /// True when reviewing a Creation Center update to an already-saved card.
  /// Save overwrites that same character id after review.
  final bool updatingExisting;

  @override
  State<CharacterEditScreen> createState() => _CharacterEditScreenState();
}

class _CharacterEditScreenState extends State<CharacterEditScreen> {
  static const _collaborator = CharacterCollaborator();
  static const _avatarPromptBuilder = AvatarPromptBuilder();

  final _avatarService = AvatarService();
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _personality = TextEditingController();
  final _scenario = TextEditingController();
  final _firstMes = TextEditingController();
  final _alternateGreetings = TextEditingController();
  final _mesExample = TextEditingController();
  final _systemPrompt = TextEditingController();
  final _postHistory = TextEditingController();
  bool _saving = false;
  bool _consistencyBusy = false;
  bool _avatarBusy = false;
  CharacterCollaboratorField? _wandBusy;
  Lorebook? _lorebook;
  Map<String, dynamic> _extensions = const {};
  String? _avatarFileName;
  late final String _characterId;

  /// Kept from import / prior saves — not shown in the editor UI.
  /// (Named distinctly from the old TextEditingControllers to avoid hot-reload
  /// type crashes after the UI fields were removed.)
  String _preservedCreatorNotes = '';
  String _preservedCreator = '';
  String _preservedCharacterVersion = '';
  List<String> _preservedTags = const [];

  bool get _isEditing =>
      widget.existing != null &&
      !widget.generatedDraft &&
      !widget.updatingExisting;

  bool get _isGeneratedDraft => widget.generatedDraft || widget.updatingExisting;

  bool get _isUpdatingExisting => widget.updatingExisting;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _characterId = existing?.id ?? widget.characterService.newId();
    if (existing != null) {
      _name.text = existing.name;
      _description.text = existing.description;
      _personality.text = existing.personality;
      _scenario.text = existing.scenario;
      _firstMes.text = existing.firstMes;
      _alternateGreetings.text = existing.alternateGreetings.join('\n');
      _mesExample.text = existing.mesExample;
      _systemPrompt.text = existing.systemPrompt;
      _postHistory.text = existing.postHistoryInstructions;
      _preservedCreatorNotes = existing.creatorNotes;
      _preservedCreator = existing.creator;
      _preservedCharacterVersion = existing.characterVersion;
      _preservedTags = List<String>.from(existing.tags);
      _lorebook = existing.lorebook;
      _extensions = Map<String, dynamic>.from(existing.extensions);
      _avatarFileName = existing.avatarFileName;
    }
  }

  List<String> _lines(String raw) => raw
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();

  CharacterDraftContext _draftContext() {
    return CharacterDraftContext(
      name: _name.text,
      description: _description.text,
      personality: _personality.text,
      scenario: _scenario.text,
      firstMes: _firstMes.text,
      alternateGreetings: _alternateGreetings.text,
      mesExample: _mesExample.text,
      systemPrompt: _systemPrompt.text,
      postHistoryInstructions: _postHistory.text,
      creatorNotes: _preservedCreatorNotes,
      creator: _preservedCreator,
      tags: _preservedTags.join(', '),
    );
  }

  TextEditingController _controllerFor(CharacterCollaboratorField field) {
    switch (field) {
      case CharacterCollaboratorField.description:
        return _description;
      case CharacterCollaboratorField.personality:
        return _personality;
      case CharacterCollaboratorField.scenario:
        return _scenario;
      case CharacterCollaboratorField.firstMes:
        return _firstMes;
      case CharacterCollaboratorField.alternateGreetings:
        return _alternateGreetings;
      case CharacterCollaboratorField.mesExample:
        return _mesExample;
      case CharacterCollaboratorField.systemPrompt:
        return _systemPrompt;
      case CharacterCollaboratorField.postHistoryInstructions:
        return _postHistory;
    }
  }

  Future<void> _runWand(CharacterCollaboratorField field) async {
    if (_wandBusy != null || _consistencyBusy) return;

    setState(() => _wandBusy = field);
    try {
      final collaborator =
          await widget.settingsService.getCollaboratorSettings();
      final messages = _collaborator.buildMessages(
        field: field,
        draft: _draftContext(),
        guidanceNote: collaborator.guidanceNote,
      );
      final model = await widget.settingsService.getModel();
      final sampling = await widget.settingsService.getSampling();
      final baseUrl = await widget.settingsService.getApiBaseUrl();
      final generated = await widget.nanoGptService.complete(
        model: model,
        messages: messages,
        baseUrl: baseUrl,
        sampling: sampling,
      );
      if (!mounted) return;
      final controller = _controllerFor(field);
      controller.text =
          _collaborator.appendGenerated(controller.text, generated);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Appended AI text to ${_collaborator.fieldLabel(field)}.',
          ),
        ),
      );
    } on NanoGptCancelledException {
      // User shouldn't hit Stop here; ignore.
    } on NanoGptException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Wand failed: $error')),
      );
    } finally {
      if (mounted) setState(() => _wandBusy = null);
    }
  }

  Future<void> _runConsistencyCheck() async {
    if (_wandBusy != null || _consistencyBusy) return;
    setState(() => _consistencyBusy = true);
    try {
      final collaborator =
          await widget.settingsService.getCollaboratorSettings();
      final messages = _collaborator.buildConsistencyCheckMessages(
        draft: _draftContext(),
        guidanceNote: collaborator.guidanceNote,
      );
      final model = await widget.settingsService.getModel();
      final sampling = await widget.settingsService.getSampling();
      final baseUrl = await widget.settingsService.getApiBaseUrl();
      final report = await widget.nanoGptService.complete(
        model: model,
        messages: messages,
        baseUrl: baseUrl,
        sampling: sampling,
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Consistency check'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: SelectableText(report.trim()),
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
        SnackBar(content: Text('Consistency check failed: $error')),
      );
    } finally {
      if (mounted) setState(() => _consistencyBusy = false);
    }
  }

  Future<void> _pickAvatar() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    Uint8List? bytes = file.bytes;
    if (bytes == null && file.path != null) {
      bytes = await File(file.path!).readAsBytes();
    }
    if (bytes == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not read that image.')),
      );
      return;
    }

    final id = _characterId;
    var ext = '.png';
    final name = file.name.toLowerCase();
    if (name.endsWith('.jpg') || name.endsWith('.jpeg')) {
      ext = '.jpg';
    } else if (name.endsWith('.webp')) {
      ext = '.webp';
    } else if (name.endsWith('.gif')) {
      ext = '.gif';
    }

    final previous = _avatarFileName;
    final saved = await _avatarService.saveBytes(
      stem: id,
      bytes: bytes,
      extension: ext,
    );
    if (previous != null && previous != saved) {
      await _avatarService.delete(previous);
    }
    if (!mounted) return;
    setState(() => _avatarFileName = saved);
  }

  Future<void> _clearAvatar() async {
    final previous = _avatarFileName;
    if (previous != null) {
      await _avatarService.delete(previous);
    }
    if (!mounted) return;
    setState(() => _avatarFileName = null);
  }

  Future<void> _generateAvatar() async {
    if (_avatarBusy || _saving || _wandBusy != null) return;

    final promptController = TextEditingController(
      text: _avatarPromptBuilder.buildPrompt(
        name: _name.text,
        description: _description.text,
        personality: _personality.text,
        scenario: _scenario.text,
        tags: _preservedTags,
      ),
    );

    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (sheetContext) {
          return GenerateAvatarSheet(
            promptController: promptController,
            settingsService: widget.settingsService,
            nanoGptService: widget.nanoGptService,
            onAccepted: (image) async {
              setState(() => _avatarBusy = true);
              try {
                final previous = _avatarFileName;
                final saved = await _avatarService.saveBytes(
                  stem: _characterId,
                  bytes: image.bytes,
                  extension: image.fileExtension,
                );
                if (previous != null && previous != saved) {
                  await _avatarService.delete(previous);
                }
                if (!mounted) return;
                setState(() => _avatarFileName = saved);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Avatar updated from NanoGPT.')),
                );
              } finally {
                if (mounted) setState(() => _avatarBusy = false);
              }
            },
          );
        },
      );
    } finally {
      promptController.dispose();
    }
  }

  Future<void> _openLorebook() async {
    final initial = _lorebook ??
        Lorebook.empty(
          name: _name.text.trim().isEmpty
              ? 'Character lore'
              : '${_name.text.trim()} lore',
        );
    final result = await Navigator.of(context).push<Lorebook>(
      MaterialPageRoute(
        builder: (_) => LorebookEditScreen(
          initial: initial,
          characterName: _name.text.trim(),
          settingsService: widget.settingsService,
          nanoGptService: widget.nanoGptService,
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _lorebook = result.entries.isEmpty &&
              result.name.isEmpty &&
              result.description.isEmpty
          ? null
          : result;
    });
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Give your character a name.')),
      );
      return;
    }

    setState(() => _saving = true);
    final book = _lorebook;
    final character = Character(
      id: _characterId,
      name: name,
      description: _description.text.trim(),
      personality: _personality.text.trim(),
      scenario: _scenario.text.trim(),
      firstMes: _firstMes.text.trim(),
      alternateGreetings: _lines(_alternateGreetings.text),
      mesExample: _mesExample.text.trim(),
      systemPrompt: _systemPrompt.text.trim(),
      postHistoryInstructions: _postHistory.text.trim(),
      creatorNotes: _preservedCreatorNotes.trim(),
      creator: _preservedCreator.trim(),
      characterVersion: _preservedCharacterVersion.trim(),
      tags: List<String>.from(_preservedTags),
      characterBook: book?.toJson(),
      extensions: _extensions,
      avatarFileName: _avatarFileName,
    );
    await widget.characterService.upsert(character);
    if (!mounted) return;
    Navigator.of(context).pop(character);
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _personality.dispose();
    _scenario.dispose();
    _firstMes.dispose();
    _alternateGreetings.dispose();
    _mesExample.dispose();
    _systemPrompt.dispose();
    _postHistory.dispose();
    super.dispose();
  }

  Widget _field(
    TextEditingController controller, {
    required String label,
    String? hint,
    String? help,
    int minLines = 1,
    int maxLines = 1,
    CharacterCollaboratorField? wandField,
    String? presetLabel,
    List<TextPreset>? presetList,
  }) {
    final wandBusy = wandField != null && _wandBusy == wandField;
    final anyWandBusy = _wandBusy != null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (presetLabel != null && presetList != null)
            PresetButton(
              label: presetLabel,
              onPressed: () async {
                final preset = await pickTextPreset(
                  context: context,
                  title: presetLabel,
                  presets: presetList,
                );
                if (preset == null) return;
                setState(() => controller.text = preset.text);
              },
            ),
          TextField(
            controller: controller,
            minLines: minLines,
            maxLines: maxLines,
            scrollPadding: kAnimaKeyboardScrollPadding,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: label,
              hintText: hint,
              alignLabelWithHint: minLines > 1,
              border: const OutlineInputBorder(),
              suffixIcon: wandField == null
                  ? null
                  : IconButton(
                      tooltip: 'AI wand — expand this field',
                      onPressed:
                          anyWandBusy ? null : () => _runWand(wandField),
                      icon: wandBusy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.auto_awesome),
                    ),
            ),
          ),
          if (help != null) ...[
            const SizedBox(height: 6),
            Text(help, style: Theme.of(context).textTheme.bodySmall),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loreCount = _lorebook?.entries.length ?? 0;
    final loreEnabled =
        _lorebook?.entries.where((e) => e.enabled).length ?? 0;

    final title = _isUpdatingExisting
        ? 'Review character update'
        : (_isGeneratedDraft
            ? 'Review generated character'
            : (_isEditing ? 'Edit character card' : 'New character card'));
    final intro = _isUpdatingExisting
        ? 'Review this AI update from Creation Center. Established facts were '
            'kept where possible; edit anything you like, then Save to update '
            'the original character — or go back to leave it unchanged. '
            'You can use {{char}} and {{user}} in the text.'
        : (_isGeneratedDraft
            ? 'Review this AI draft from Creation Center. Edit anything you like, '
                'then Save to add it to Characters — or go back to skip it. '
                'You can use {{char}} and {{user}} in the text.'
            : 'Fields match SillyTavern Character Cards (V2/V3). '
                'You can use {{char}} and {{user}} in the text. '
                'Tap the wand on a creative field to append AI text '
                '(uses your NanoGPT model + Settings → AI collaborator). '
                'Use the checklist icon for a read-only consistency report.');

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            tooltip: 'Consistency check (read-only report)',
            onPressed: (_wandBusy != null || _consistencyBusy || _saving)
                ? null
                : _runConsistencyCheck,
            icon: _consistencyBusy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.fact_check_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            intro,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 20),
          Center(
            child: Column(
              children: [
                AnimaAvatar(
                  fileName: _avatarFileName,
                  label: _name.text,
                  radius: 48,
                  avatarService: _avatarService,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      onPressed: (_avatarBusy || _saving) ? null : _pickAvatar,
                      icon: const Icon(Icons.photo),
                      label: Text(
                        _avatarFileName == null
                            ? 'Add avatar'
                            : 'Change avatar',
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed:
                          (_avatarBusy || _saving) ? null : _generateAvatar,
                      icon: _avatarBusy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.auto_awesome),
                      label: const Text('Generate avatar'),
                    ),
                    if (_avatarFileName != null)
                      TextButton(
                        onPressed:
                            (_avatarBusy || _saving) ? null : _clearAvatar,
                        child: const Text('Remove'),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Pick a photo or generate one with NanoGPT from the card text. '
                  'PNG card imports use the card image automatically.',
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _field(_name, label: 'Name', hint: 'e.g. Luna'),
          _field(
            _description,
            label: 'Description',
            hint: 'Appearance, background, important facts…',
            help: 'Usually included in every prompt (ST Description).',
            minLines: 4,
            maxLines: 10,
            wandField: CharacterCollaboratorField.description,
          ),
          _field(
            _personality,
            label: 'Personality',
            hint: 'Short personality summary…',
            minLines: 2,
            maxLines: 6,
            wandField: CharacterCollaboratorField.personality,
          ),
          _field(
            _scenario,
            label: 'Scenario',
            hint: 'Current situation / context…',
            minLines: 2,
            maxLines: 6,
            wandField: CharacterCollaboratorField.scenario,
          ),
          _field(
            _firstMes,
            label: 'First message',
            hint: 'Opening greeting…',
            help: 'Shown when a new chat starts.',
            minLines: 3,
            maxLines: 8,
            wandField: CharacterCollaboratorField.firstMes,
          ),
          _field(
            _alternateGreetings,
            label: 'Alternate greetings',
            hint: 'One greeting per line…',
            help: 'Extra first-message swipes (ST alternate_greetings).',
            minLines: 3,
            maxLines: 8,
            wandField: CharacterCollaboratorField.alternateGreetings,
          ),
          _field(
            _mesExample,
            label: 'Example messages',
            hint: '<START>\n{{user}}: …\n{{char}}: …',
            help: 'ST mes_example — teaches tone and style.',
            minLines: 4,
            maxLines: 12,
            wandField: CharacterCollaboratorField.mesExample,
          ),
          _field(
            _systemPrompt,
            label: 'System prompt (optional)',
            hint: 'Leave blank to use Anima’s default…',
            help: 'ST system_prompt. Supports {{original}}.',
            minLines: 2,
            maxLines: 6,
            wandField: CharacterCollaboratorField.systemPrompt,
            presetLabel: 'System prompt presets',
            presetList: AnimaPresets.systemPrompts,
          ),
          _field(
            _postHistory,
            label: 'Post-history instructions (optional)',
            hint: 'Nudge after the chat history…',
            help: 'ST post_history_instructions.',
            minLines: 2,
            maxLines: 6,
            wandField:
                CharacterCollaboratorField.postHistoryInstructions,
            presetLabel: 'Post-history presets',
            presetList: AnimaPresets.postHistory,
          ),
          OutlinedButton.icon(
            onPressed: _openLorebook,
            icon: const Icon(Icons.menu_book_outlined),
            label: Text(
              loreCount == 0
                  ? 'World Info / lorebook'
                  : 'World Info / lorebook ($loreEnabled/$loreCount on)',
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 16),
            child: Text(
              loreCount == 0
                  ? 'Optional keyword lore (also used for imported character_book).'
                  : 'Keyword lore is injected during chat when keys match.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          FilledButton(
            onPressed: _saving || _wandBusy != null ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    _isUpdatingExisting
                        ? 'Save update'
                        : _isGeneratedDraft || _isEditing
                        ? 'Save character'
                        : 'Create character',
                  ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
