import 'package:flutter/material.dart';

import '../models/character.dart';
import '../models/chat_session.dart';
import '../models/persona.dart';
import '../services/chat_session_resolver.dart';

/// Manage per-chat character/persona/lore copies.
Future<void> showChatOverridesSheet({
  required BuildContext context,
  required ChatSession session,
  required List<Character> participants,
  required Persona? persona,
  required ValueChanged<ChatSession> onChanged,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => _ChatOverridesSheet(
      session: session,
      participants: participants,
      persona: persona,
      onChanged: onChanged,
    ),
  );
}

class _ChatOverridesSheet extends StatelessWidget {
  const _ChatOverridesSheet({
    required this.session,
    required this.participants,
    required this.persona,
    required this.onChanged,
  });

  final ChatSession session;
  final List<Character> participants;
  final Persona? persona;
  final ValueChanged<ChatSession> onChanged;

  static const _resolver = ChatSessionResolver();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final overrideIds = session.characterOverrides.keys.toSet();
    final hasPersonaOverride = session.personaOverride != null;
    final hasChatLore =
        session.chatLorebook != null && !session.chatLorebook!.isEmpty;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Chat copies', style: theme.textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(
              'These overrides apply only in this chat. Your library cards stay '
              'unchanged.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            if (overrideIds.isEmpty && !hasPersonaOverride && !hasChatLore)
              Text(
                'No chat-only copies yet. Update a character or persona for '
                'this chat, or add chat lore.',
                style: theme.textTheme.bodySmall,
              ),
            for (final character in participants)
              if (overrideIds.contains(character.id))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.badge_outlined),
                  title: Text('${character.name} (chat copy)'),
                  subtitle: const Text('Reset to library card'),
                  trailing: IconButton(
                    tooltip: 'Reset',
                    onPressed: () {
                      final next = Map<String, Character>.from(
                        session.characterOverrides,
                      )..remove(character.id);
                      onChanged(
                        session.copyWith(
                          characterOverrides: next,
                          clearCharacterOverrides: next.isEmpty,
                        ),
                      );
                      Navigator.pop(context);
                    },
                    icon: const Icon(Icons.restore),
                  ),
                ),
            if (hasPersonaOverride && persona != null)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.person_outline),
                title: Text('${persona!.name} (chat copy)'),
                subtitle: const Text('Reset to library persona'),
                trailing: IconButton(
                  tooltip: 'Reset',
                  onPressed: () {
                    onChanged(session.copyWith(clearPersonaOverride: true));
                    Navigator.pop(context);
                  },
                  icon: const Icon(Icons.restore),
                ),
              ),
            if (hasChatLore)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.menu_book_outlined),
                title: Text(
                  session.chatLorebook!.name.trim().isEmpty
                      ? 'Chat lorebook'
                      : session.chatLorebook!.name.trim(),
                ),
                subtitle: Text(
                  '${session.chatLorebook!.entries.length} '
                  'entr${session.chatLorebook!.entries.length == 1 ? 'y' : 'ies'}',
                ),
                trailing: IconButton(
                  tooltip: 'Clear chat lore',
                  onPressed: () {
                    onChanged(session.copyWith(clearChatLorebook: true));
                    Navigator.pop(context);
                  },
                  icon: const Icon(Icons.restore),
                ),
              ),
            if (_resolver.hasChatOverrides(session)) ...[
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () {
                  onChanged(
                    session.copyWith(
                      clearCharacterOverrides: true,
                      clearPersonaOverride: true,
                      clearChatLorebook: true,
                    ),
                  );
                  Navigator.pop(context);
                },
                child: const Text('Reset all chat copies'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
