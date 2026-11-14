import 'package:flutter/material.dart';

import '../models/character.dart';
import '../models/group_beat_part.dart';

/// Edit each character line in a group-beat message.
Future<List<GroupBeatPart>?> showGroupBeatEditSheet({
  required BuildContext context,
  required List<GroupBeatPart> lines,
  required List<Character> participants,
}) {
  return showModalBottomSheet<List<GroupBeatPart>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _GroupBeatEditSheet(
      initialLines: lines,
      participants: participants,
    ),
  );
}

class _GroupBeatEditSheet extends StatefulWidget {
  const _GroupBeatEditSheet({
    required this.initialLines,
    required this.participants,
  });

  final List<GroupBeatPart> initialLines;
  final List<Character> participants;

  @override
  State<_GroupBeatEditSheet> createState() => _GroupBeatEditSheetState();
}

class _GroupBeatEditSheetState extends State<_GroupBeatEditSheet> {
  late final List<TextEditingController> _controllers;
  late final List<GroupBeatPart> _parts;

  @override
  void initState() {
    super.initState();
    _parts = List<GroupBeatPart>.from(widget.initialLines);
    _controllers = [
      for (final part in _parts)
        TextEditingController(text: part.text),
    ];
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    final out = <GroupBeatPart>[];
    for (var i = 0; i < _parts.length; i++) {
      final text = _controllers[i].text.trim();
      if (text.isEmpty) continue;
      out.add(_parts[i].copyWith(text: text));
    }
    if (out.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('At least one line needs text.')),
      );
      return;
    }
    Navigator.pop(context, out);
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
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Text('Edit group react', style: theme.textTheme.titleLarge),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Column(
                  children: [
                    for (var i = 0; i < _parts.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: TextField(
                          controller: _controllers[i],
                          minLines: 2,
                          maxLines: 6,
                          decoration: InputDecoration(
                            labelText: _parts[i].speakerName.trim().isEmpty
                                ? 'Character'
                                : _parts[i].speakerName.trim(),
                            border: const OutlineInputBorder(),
                            alignLabelWithHint: true,
                          ),
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
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: _save,
                    child: const Text('Save'),
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
