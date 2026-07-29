import 'package:flutter/material.dart';

import '../models/chat_session.dart';
import '../models/character.dart';
import '../models/global_lorebook.dart';
import '../models/persona.dart';
import '../models/world_workshop.dart';
import '../models/workshop_hub_models.dart';
import '../widgets/anima_avatar.dart';

/// Read-only workshop dashboard + quick actions (Creation Center hub).
class WorkshopOverviewSheet extends StatelessWidget {
  const WorkshopOverviewSheet({
    super.key,
    required this.workshop,
    required this.status,
    required this.linkedLorebook,
    required this.linkedCharacters,
    required this.linkedPersona,
    required this.workshopChats,
    this.onPlayWorld,
    this.onOpenLorebook,
    this.onOpenOpeningScene,
    this.onOpenChat,
    this.onSummarizeWorld,
    this.onGenerateOverview,
    this.onExportBundle,
    this.onRefreshFromChat,
    this.onEditChatKit,
    this.onEditWorldSummary,
    this.onEditSheets,
    this.onSceneIdeas,
    this.onGlossary,
    this.onDuplicate,
    this.onMerge,
  });

  final WorldWorkshop workshop;
  final WorkshopHubStatus status;
  final GlobalLorebook? linkedLorebook;
  final List<Character> linkedCharacters;
  final Persona? linkedPersona;
  final List<ChatSession> workshopChats;
  final VoidCallback? onPlayWorld;
  final VoidCallback? onOpenLorebook;
  final VoidCallback? onOpenOpeningScene;
  final ValueChanged<ChatSession>? onOpenChat;
  final VoidCallback? onSummarizeWorld;
  final VoidCallback? onGenerateOverview;
  final VoidCallback? onExportBundle;
  final VoidCallback? onRefreshFromChat;
  final VoidCallback? onEditChatKit;
  final VoidCallback? onEditWorldSummary;
  final VoidCallback? onEditSheets;
  final VoidCallback? onSceneIdeas;
  final VoidCallback? onGlossary;
  final VoidCallback? onDuplicate;
  final VoidCallback? onMerge;

  String _lorebookLabel() {
    return switch (status.lorebookState) {
      'linked' => linkedLorebook != null
          ? 'Linked · ${linkedLorebook!.entryCount} entries'
          : 'Linked',
      'stale' => 'Stale · update recommended',
      'draft' => 'Draft · not exported yet',
      'missing' => 'Missing · re-link in World Info',
      _ => 'None',
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DraggableScrollableSheet(
      initialChildSize: 0.72,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Material(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                child: Row(
                  children: [
                    AnimaAvatar(
                      fileName: workshop.coverFileName,
                      label: workshop.title,
                      radius: 28,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            workshop.title,
                            style: theme.textTheme.titleLarge,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (workshop.tags.isNotEmpty)
                            Text(
                              workshop.tags.join(' · '),
                              style: theme.textTheme.labelSmall,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (onPlayWorld != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: FilledButton.icon(
                    onPressed: onPlayWorld,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Play this world'),
                  ),
                ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        Chip(
                          avatar: const Icon(Icons.menu_book, size: 18),
                          label: Text(_lorebookLabel()),
                        ),
                        Chip(
                          avatar: const Icon(Icons.theater_comedy, size: 18),
                          label: Text(
                            status.openingSceneSet
                                ? 'Opening scene set'
                                : 'No opening scene',
                          ),
                        ),
                        Chip(
                          avatar: const Icon(Icons.people_outline, size: 18),
                          label: Text(
                            '${status.characterCount} character'
                            '${status.characterCount == 1 ? '' : 's'}',
                          ),
                        ),
                        if (status.personaLinked)
                          const Chip(
                            avatar: Icon(Icons.badge_outlined, size: 18),
                            label: Text('Persona linked'),
                          ),
                        if (status.canonPinCount > 0)
                          Chip(
                            avatar: const Icon(Icons.push_pin, size: 18),
                            label: Text(
                              '${status.canonPinCount} canon pin'
                              '${status.canonPinCount == 1 ? '' : 's'}',
                            ),
                          ),
                        if (status.sceneIdeaCount > 0)
                          Chip(
                            avatar: const Icon(Icons.lightbulb_outline, size: 18),
                            label: Text(
                              '${status.sceneIdeaCount} scene idea'
                              '${status.sceneIdeaCount == 1 ? '' : 's'}',
                            ),
                          ),
                      ],
                    ),
                    if (status.isLorebookStale) ...[
                      const SizedBox(height: 12),
                      Material(
                        color: theme.colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            '${status.messagesSinceLorebookUpdate} messages since '
                            'last lorebook update. Consider updating World Info.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onErrorContainer,
                            ),
                          ),
                        ),
                      ),
                    ],
                    if (status.sourceChatTitle != null) ...[
                      const SizedBox(height: 16),
                      Text('Source', style: theme.textTheme.titleSmall),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.forum_outlined),
                        title: Text(status.sourceChatTitle!),
                        subtitle: const Text('Imported chat seed'),
                      ),
                    ],
                    if (workshop.worldSummary.trim().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text('World summary', style: theme.textTheme.titleSmall),
                      Text(
                        workshop.worldSummary.trim(),
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                    if (workshop.worldOverview.trim().isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text('World overview', style: theme.textTheme.titleSmall),
                      Text(
                        workshop.worldOverview.trim(),
                        style: theme.textTheme.bodySmall,
                        maxLines: 8,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (linkedCharacters.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text('Characters', style: theme.textTheme.titleSmall),
                      for (final c in linkedCharacters)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: AnimaAvatar(
                            fileName: c.avatarFileName,
                            label: c.name,
                            radius: 18,
                          ),
                          title: Text(c.name),
                        ),
                    ],
                    if (linkedPersona != null) ...[
                      const SizedBox(height: 8),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: AnimaAvatar(
                          fileName: linkedPersona!.avatarFileName,
                          label: linkedPersona!.name,
                          radius: 18,
                        ),
                        title: Text('Persona: ${linkedPersona!.name}'),
                      ),
                    ],
                    if (workshopChats.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text(
                        'Roleplay chats',
                        style: theme.textTheme.titleSmall,
                      ),
                      for (final chat in workshopChats)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            chat.isGroup
                                ? Icons.groups_outlined
                                : Icons.chat_bubble_outline,
                          ),
                          title: Text(chat.title),
                          subtitle: Text(
                            '${chat.messages.length} messages',
                          ),
                          onTap: onOpenChat == null
                              ? null
                              : () => onOpenChat!(chat),
                        ),
                    ],
                    const SizedBox(height: 16),
                    Text('Actions', style: theme.textTheme.titleSmall),
                    if (onOpenLorebook != null)
                      ListTile(
                        leading: const Icon(Icons.menu_book_outlined),
                        title: const Text('World Info lorebook'),
                        onTap: onOpenLorebook,
                      ),
                    if (onOpenOpeningScene != null)
                      ListTile(
                        leading: const Icon(Icons.theater_comedy_outlined),
                        title: const Text('Opening scene'),
                        onTap: onOpenOpeningScene,
                      ),
                    if (onSummarizeWorld != null)
                      ListTile(
                        leading: const Icon(Icons.notes_outlined),
                        title: const Text('Summarize workshop'),
                        onTap: onSummarizeWorld,
                      ),
                    if (onGenerateOverview != null)
                      ListTile(
                        leading: const Icon(Icons.description_outlined),
                        title: const Text('Generate world overview'),
                        onTap: onGenerateOverview,
                      ),
                    if (onGlossary != null)
                      ListTile(
                        leading: const Icon(Icons.list_alt_outlined),
                        title: const Text('Glossary → lorebook entries'),
                        onTap: onGlossary,
                      ),
                    if (onSceneIdeas != null)
                      ListTile(
                        leading: const Icon(Icons.lightbulb_outline),
                        title: const Text('Generate scene ideas'),
                        onTap: onSceneIdeas,
                      ),
                    if (onEditSheets != null)
                      ListTile(
                        leading: const Icon(Icons.map_outlined),
                        title: const Text('Locations & relationships'),
                        onTap: onEditSheets,
                      ),
                    if (onEditChatKit != null)
                      ListTile(
                        leading: const Icon(Icons.tune),
                        title: const Text('Default chat kit'),
                        onTap: onEditChatKit,
                      ),
                    if (onEditWorldSummary != null)
                      ListTile(
                        leading: const Icon(Icons.edit_note),
                        title: const Text('Edit world summary'),
                        onTap: onEditWorldSummary,
                      ),
                    if (onRefreshFromChat != null)
                      ListTile(
                        leading: const Icon(Icons.sync_outlined),
                        title: const Text('Refresh from linked chat'),
                        onTap: onRefreshFromChat,
                      ),
                    if (onExportBundle != null)
                      ListTile(
                        leading: const Icon(Icons.archive_outlined),
                        title: const Text('Export world bundle'),
                        onTap: onExportBundle,
                      ),
                    if (onDuplicate != null)
                      ListTile(
                        leading: const Icon(Icons.copy_outlined),
                        title: const Text('Duplicate workshop'),
                        onTap: onDuplicate,
                      ),
                    if (onMerge != null)
                      ListTile(
                        leading: const Icon(Icons.merge_type),
                        title: const Text('Merge with another workshop'),
                        onTap: onMerge,
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
