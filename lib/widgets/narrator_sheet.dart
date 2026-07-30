import 'package:flutter/material.dart';

import '../models/chat_message.dart';
import '../services/nanogpt_service.dart';
import '../services/narrator_service.dart';
import '../services/settings_service.dart';

/// Result from the narrator sheet — text to post, or null if cancelled.
class NarratorSheetResult {
  const NarratorSheetResult({required this.text});

  final String text;
}

Future<NarratorSheetResult?> showNarratorSheet({
  required BuildContext context,
  required NanoGptService nanoGptService,
  required SettingsService settingsService,
  required List<ChatMessage> recentMessages,
  required String userName,
  required String characterName,
  bool isGroup = false,
  List<String> otherCharacterNames = const [],
  String initialText = '',
}) {
  return showModalBottomSheet<NarratorSheetResult>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _NarratorSheet(
      nanoGptService: nanoGptService,
      settingsService: settingsService,
      recentMessages: recentMessages,
      userName: userName,
      characterName: characterName,
      isGroup: isGroup,
      otherCharacterNames: otherCharacterNames,
      initialText: initialText,
    ),
  );
}

class _NarratorSheet extends StatefulWidget {
  const _NarratorSheet({
    required this.nanoGptService,
    required this.settingsService,
    required this.recentMessages,
    required this.userName,
    required this.characterName,
    required this.isGroup,
    required this.otherCharacterNames,
    required this.initialText,
  });

  final NanoGptService nanoGptService;
  final SettingsService settingsService;
  final List<ChatMessage> recentMessages;
  final String userName;
  final String characterName;
  final bool isGroup;
  final List<String> otherCharacterNames;
  final String initialText;

  @override
  State<_NarratorSheet> createState() => _NarratorSheetState();
}

class _NarratorSheetState extends State<_NarratorSheet> {
  static const _narrator = NarratorService();

  final _nudgeController = TextEditingController();
  final _draftController = TextEditingController();
  bool _generating = false;

  @override
  void initState() {
    super.initState();
    _draftController.text = widget.initialText.trim();
  }

  @override
  void dispose() {
    _nudgeController.dispose();
    _draftController.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    if (_generating) return;
    setState(() => _generating = true);
    try {
      final collaborator =
          await widget.settingsService.getCollaboratorSettings();
      final model = await widget.settingsService.getModel();
      final sampling = await widget.settingsService.getSampling();
      final baseUrl = await widget.settingsService.getApiBaseUrl();
      final messages = _narrator.buildGenerateMessages(
        userName: widget.userName,
        characterName: widget.characterName,
        recentMessages: widget.recentMessages,
        narratorNote: collaborator.narratorNote,
        nudge: _nudgeController.text,
        existingDraft: _draftController.text,
        isGroup: widget.isGroup,
        otherCharacterNames: widget.otherCharacterNames,
      );
      final generated = await widget.nanoGptService.complete(
        model: model,
        messages: messages,
        baseUrl: baseUrl,
        sampling: sampling.copyWith(
          temperature: sampling.temperature > 0.75 ? 0.75 : sampling.temperature,
        ),
      );
      if (!mounted) return;
      _draftController.text = generated.trim();
      _draftController.selection = TextSelection.collapsed(
        offset: _draftController.text.length,
      );
    } on NanoGptException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Narrator failed: $error')),
      );
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  void _post() {
    final text = _draftController.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Type or generate narrator text first.'),
        ),
      );
      return;
    }
    Navigator.pop(context, NarratorSheetResult(text: text));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: Text('Narrator', style: theme.textTheme.titleLarge),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Text(
                'Omniscient scene voice — edit below or nudge the AI, then post '
                'into the chat. Works in every chat except Creation Center.',
                style: theme.textTheme.bodySmall,
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _nudgeController,
                      minLines: 1,
                      maxLines: 3,
                      textCapitalization: TextCapitalization.sentences,
                      enabled: !_generating,
                      decoration: const InputDecoration(
                        labelText: 'Nudge (optional)',
                        hintText:
                            'Steer the scene — e.g. raise tension, a storm rolls in…',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _draftController,
                      minLines: 4,
                      maxLines: 10,
                      textCapitalization: TextCapitalization.sentences,
                      enabled: !_generating,
                      decoration: const InputDecoration(
                        labelText: 'Narrator line',
                        hintText:
                            'Type your own narration, or tap Generate…',
                        alignLabelWithHint: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: _generating ? null : _generate,
                    icon: _generating
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.auto_awesome, size: 18),
                    label: Text(_generating ? 'Generating…' : 'Generate'),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _generating
                        ? null
                        : () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _generating ? null : _post,
                    child: const Text('Post'),
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
