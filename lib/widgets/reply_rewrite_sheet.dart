import 'package:flutter/material.dart';

import '../services/reply_rewrite_service.dart';

/// Pick how to rewrite an assistant reply (regenerate / new swipe).
Future<ReplyRewriteChoice?> showReplyRewriteSheet(BuildContext context) {
  return showModalBottomSheet<ReplyRewriteChoice>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => const _ReplyRewriteSheet(),
  );
}

class _ReplyRewriteSheet extends StatefulWidget {
  const _ReplyRewriteSheet();

  @override
  State<_ReplyRewriteSheet> createState() => _ReplyRewriteSheetState();
}

class _ReplyRewriteSheetState extends State<_ReplyRewriteSheet> {
  static const _service = ReplyRewriteService();
  final _customController = TextEditingController();
  ReplyRewriteMode? _selected;

  @override
  void dispose() {
    _customController.dispose();
    super.dispose();
  }

  void _submit() {
    final mode = _selected;
    if (mode == null) return;
    if (mode == ReplyRewriteMode.custom &&
        _customController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Type a custom instruction first.')),
      );
      return;
    }
    Navigator.pop(
      context,
      ReplyRewriteChoice(
        mode: mode,
        customInstruction: _customController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCustom = _selected == ReplyRewriteMode.custom;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: Text('Rewrite reply', style: theme.textTheme.titleLarge),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'Steer the next generation without OOC. The rewrite is saved '
                'as a new swipe — swipe back to the old text anytime.',
                style: theme.textTheme.bodySmall,
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final mode in ReplyRewriteService.modesForMenu) ...[
                    ListTile(
                      leading: Icon(
                        _selected == mode
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                        color: _selected == mode
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                      title: Text(_service.label(mode)),
                      subtitle: Text(_service.subtitle(mode)),
                      onTap: () => setState(() => _selected = mode),
                    ),
                    if (mode == ReplyRewriteMode.custom && isCustom)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                        child: TextField(
                          controller: _customController,
                          autofocus: true,
                          minLines: 2,
                          maxLines: 5,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: const InputDecoration(
                            labelText: 'Custom instruction',
                            hintText:
                                'e.g. Make her sound more suspicious of the king…',
                            border: OutlineInputBorder(),
                            alignLabelWithHint: true,
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: _selected == null ? null : _submit,
                    child: const Text('Rewrite'),
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
