import 'package:flutter/material.dart';

import '../models/character.dart';

/// Bottom sheet: pick who reacts together, optional nudge, then generate one beat.
class GroupReplySheet extends StatefulWidget {
  const GroupReplySheet({
    super.key,
    required this.participants,
    this.minSpeakers = 2,
  });

  final List<Character> participants;
  final int minSpeakers;

  @override
  State<GroupReplySheet> createState() => _GroupReplySheetState();
}

/// Selected speakers + optional nudge; null if cancelled.
class GroupReplySheetResult {
  const GroupReplySheetResult({
    required this.speakers,
    this.nudge = '',
  });

  final List<Character> speakers;
  final String nudge;
}

Future<GroupReplySheetResult?> showGroupReplySheet({
  required BuildContext context,
  required List<Character> participants,
}) {
  return showModalBottomSheet<GroupReplySheetResult>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => GroupReplySheet(participants: participants),
  );
}

class _GroupReplySheetState extends State<GroupReplySheet> {
  late final Set<String> _selectedIds;
  final _nudgeController = TextEditingController();
  bool _selectAll = true;

  @override
  void initState() {
    super.initState();
    _selectedIds = {
      for (final c in widget.participants) c.id,
    };
  }

  @override
  void dispose() {
    _nudgeController.dispose();
    super.dispose();
  }

  void _toggleAll(bool value) {
    setState(() {
      _selectAll = value;
      if (value) {
        _selectedIds
          ..clear()
          ..addAll(widget.participants.map((c) => c.id));
      } else {
        _selectedIds.clear();
      }
    });
  }

  void _toggleOne(Character character, bool selected) {
    setState(() {
      if (selected) {
        _selectedIds.add(character.id);
      } else {
        _selectedIds.remove(character.id);
      }
      _selectAll = _selectedIds.length == widget.participants.length;
    });
  }

  void _generate() {
    final speakers = widget.participants
        .where((c) => _selectedIds.contains(c.id))
        .toList(growable: false);
    if (speakers.length < widget.minSpeakers) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Pick at least ${widget.minSpeakers} characters for a group beat.',
          ),
        ),
      );
      return;
    }
    Navigator.pop(
      context,
      GroupReplySheetResult(
        speakers: speakers,
        nudge: _nudgeController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final selectedCount = _selectedIds.length;

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
              child: Text('Group react', style: theme.textTheme.titleLarge),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Text(
                'One AI call — brief simultaneous reactions from everyone '
                'you pick. Keeps the moment cohesive instead of long '
                'back-to-back solo replies.',
                style: theme.textTheme.bodySmall,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: CheckboxListTile(
                value: _selectAll,
                onChanged: (v) => _toggleAll(v ?? false),
                title: const Text('Everyone in chat'),
                controlAffinity: ListTileControlAffinity.leading,
                dense: true,
              ),
            ),
            for (final character in widget.participants)
              CheckboxListTile(
                value: _selectedIds.contains(character.id),
                onChanged: (v) => _toggleOne(character, v ?? false),
                title: Text(
                  character.name.trim().isEmpty
                      ? 'Character'
                      : character.name.trim(),
                ),
                controlAffinity: ListTileControlAffinity.leading,
                dense: true,
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: TextField(
                controller: _nudgeController,
                minLines: 1,
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Nudge (optional)',
                  hintText: 'e.g. everyone reacts to the news — keep it brief',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Row(
                children: [
                  Text(
                    '$selectedCount selected',
                    style: theme.textTheme.bodySmall,
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _generate,
                    icon: const Icon(Icons.groups_outlined, size: 18),
                    label: const Text('Generate beat'),
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
