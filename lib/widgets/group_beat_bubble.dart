import 'package:flutter/material.dart';

import '../models/group_beat_part.dart';
import '../models/ui_style_settings.dart';
import 'anima_avatar.dart';
import 'rp_rich_text.dart';

/// One timeline card for a coordinated group react moment.
class GroupBeatBubble extends StatelessWidget {
  const GroupBeatBubble({
    super.key,
    required this.lines,
    this.avatarForSpeakerId,
    this.avatarStyle,
    this.onTap,
    this.onLongPress,
  });

  final List<GroupBeatPart> lines;
  final String? Function(String speakerId)? avatarForSpeakerId;
  final AvatarStyleSettings? avatarStyle;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ui = AnimaUiTheme.of(context);
    final baseStyle = (theme.textTheme.bodyMedium ?? const TextStyle()).copyWith(
      fontSize:
          (theme.textTheme.bodyMedium?.fontSize ?? 16) * ui.chatFontScale,
      height: 1.45,
    );

    return Material(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.72),
      borderRadius: BorderRadius.circular(ui.chatBubbleRadius),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(ui.chatBubbleRadius),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.groups_outlined,
                    size: 16,
                    color: theme.colorScheme.tertiary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Group react',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.tertiary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  if (onTap != null)
                    Icon(
                      Icons.edit_outlined,
                      size: 16,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                ],
              ),
              const SizedBox(height: 10),
              for (var i = 0; i < lines.length; i++) ...[
                if (i > 0) const SizedBox(height: 10),
                _BeatLineRow(
                  line: lines[i],
                  avatarFileName: avatarForSpeakerId?.call(lines[i].speakerId),
                  avatarStyle: avatarStyle,
                  baseStyle: baseStyle,
                  ui: ui,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _BeatLineRow extends StatelessWidget {
  const _BeatLineRow({
    required this.line,
    required this.avatarFileName,
    required this.avatarStyle,
    required this.baseStyle,
    required this.ui,
  });

  final GroupBeatPart line;
  final String? avatarFileName;
  final AvatarStyleSettings? avatarStyle;
  final TextStyle baseStyle;
  final AnimaUiTheme ui;

  @override
  Widget build(BuildContext context) {
    final name = line.speakerName.trim().isEmpty
        ? 'Character'
        : line.speakerName.trim();
    final style = avatarStyle ??
        const AvatarStyleSettings(
          sizeTier: AvatarSizeTier.small,
          scale: 0.7,
        );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimaAvatar(
          fileName: avatarFileName,
          label: name,
          radius: 14,
          style: style,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: baseStyle.copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: (baseStyle.fontSize ?? 16) * 0.92,
                ),
              ),
              const SizedBox(height: 2),
              RpRichText(
                text: line.text,
                baseStyle: baseStyle,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
