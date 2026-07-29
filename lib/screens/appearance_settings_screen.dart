import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/chat_experience_settings.dart';
import '../models/theme_palette.dart';
import '../models/ui_style_settings.dart';
import '../services/appearance_controller.dart';
import '../services/chat_background_service.dart';
import '../services/settings_service.dart';
import '../theme/anima_theme.dart';
import '../widgets/anima_avatar.dart';
import '../widgets/minimal_chip_button.dart';
import '../widgets/rp_rich_text.dart';
import 'settings_ui.dart';

enum _AppearanceCategory { presets, layout, colors, fonts, chat, avatars }

/// Theme Studio — global presets plus advanced color / font / avatar controls.
class AppearanceSettingsScreen extends StatefulWidget {
  const AppearanceSettingsScreen({
    super.key,
    required this.settingsService,
    required this.appearanceController,
  });

  final SettingsService settingsService;
  final AppearanceController appearanceController;

  @override
  State<AppearanceSettingsScreen> createState() =>
      _AppearanceSettingsScreenState();
}

class _AppearanceSettingsScreenState extends State<AppearanceSettingsScreen> {
  bool _loading = true;
  bool _saving = false;
  late UiStyleSettings _draft;
  final _chatBackgroundService = ChatBackgroundService();
  String? _backgroundPreviewPath;
  _AppearanceCategory _category = _AppearanceCategory.presets;

  @override
  void initState() {
    super.initState();
    _draft = widget.appearanceController.style;
    _load();
  }

  Future<void> _load() async {
    final style = await widget.settingsService.getUiStyle();
    final previewPath = await _resolveBackgroundPreview(
      style.chatExperience.backgroundImageFileName,
    );
    if (!mounted) return;
    setState(() {
      _draft = style;
      _backgroundPreviewPath = previewPath;
      _loading = false;
    });
  }

  Future<String?> _resolveBackgroundPreview(String? fileName) async {
    if (fileName == null || fileName.trim().isEmpty) return null;
    return _chatBackgroundService.resolvePath(fileName);
  }

  Future<void> _pickChatBackground() async {
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

    var ext = '.jpg';
    final name = file.name.toLowerCase();
    if (name.endsWith('.png')) {
      ext = '.png';
    } else if (name.endsWith('.webp')) {
      ext = '.webp';
    }

    final previous = _draft.chatExperience.backgroundImageFileName;
    final saved = await _chatBackgroundService.saveBytes(
      stem: 'chat_bg_${DateTime.now().millisecondsSinceEpoch}',
      bytes: bytes,
      extension: ext,
    );
    if (previous != null && previous != saved) {
      await _chatBackgroundService.delete(previous);
    }

    final previewPath = await _chatBackgroundService.resolvePath(saved);
    if (!mounted) return;
    setState(() {
      _draft = _draft.copyWith(
        chatExperience: _draft.chatExperience.copyWith(
          backgroundEnabled: true,
          backgroundImageFileName: saved,
        ),
        markCustom: true,
      );
      _backgroundPreviewPath = previewPath;
    });
  }

  Future<void> _clearChatBackground() async {
    final previous = _draft.chatExperience.backgroundImageFileName;
    if (previous != null) {
      await _chatBackgroundService.delete(previous);
    }
    if (!mounted) return;
    setState(() {
      _draft = _draft.copyWith(
        chatExperience: _draft.chatExperience.copyWith(
          clearBackgroundImage: true,
        ),
        markCustom: true,
      );
      _backgroundPreviewPath = null;
    });
  }

  void _applyPreset(ThemePreset preset) {
    setState(() {
      _draft = UiStyleSettings.fromPreset(
        preset,
        avatarStyle: _draft.avatarStyle,
      );
    });
  }

  void _resetToPreset() {
    if (_draft.presetId == ThemePresets.customId) {
      _applyPreset(ThemePresets.obsidianGold);
      return;
    }
    _applyPreset(ThemePresets.byId(_draft.presetId));
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await widget.appearanceController.save(_draft);
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Appearance saved.')));
    Navigator.of(context).pop(true);
  }

  Future<void> _pickColor({
    required String label,
    required Color current,
    required ValueChanged<Color> onPicked,
  }) async {
    final picked = await showDialog<Color>(
      context: context,
      builder: (context) => _ColorPickerDialog(title: label, initial: current),
    );
    if (picked == null) return;
    onPicked(picked);
  }

  Widget _colorTile({
    required String label,
    required Color color,
    required ValueChanged<Color> onPicked,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      trailing: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
      ),
      onTap: () => _pickColor(
        label: label,
        current: color,
        onPicked: (c) {
          setState(() {
            onPicked(c);
            _draft = _draft.copyWith(markCustom: true);
          });
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final previewTheme = AnimaTheme.fromSettings(_draft);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Appearance'),
        actions: [
          TextButton(
            onPressed: _loading || _saving ? null : _resetToPreset,
            child: const Text('Reset'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: SettingsUi.listPadding,
              children: [
                SettingsUi.sectionHint(
                  context,
                  'Pick a global theme preset, then fine-tune colors, fonts, '
                  'and chat look. Changes preview below; tap Save to apply '
                  'everywhere.',
                ),
                const SizedBox(height: 16),
                _LivePreview(theme: previewTheme, style: _draft),
                const SizedBox(height: 16),
                MinimalChipRow(
                  children: [
                    MinimalChipButton(
                      label: 'Presets',
                      selected: _category == _AppearanceCategory.presets,
                      onPressed: () => setState(
                        () => _category = _AppearanceCategory.presets,
                      ),
                    ),
                    const SizedBox(width: 8),
                    MinimalChipButton(
                      label: 'Layout',
                      selected: _category == _AppearanceCategory.layout,
                      onPressed: () => setState(
                        () => _category = _AppearanceCategory.layout,
                      ),
                    ),
                    const SizedBox(width: 8),
                    MinimalChipButton(
                      label: 'Colors',
                      selected: _category == _AppearanceCategory.colors,
                      onPressed: () => setState(
                        () => _category = _AppearanceCategory.colors,
                      ),
                    ),
                    const SizedBox(width: 8),
                    MinimalChipButton(
                      label: 'Fonts',
                      selected: _category == _AppearanceCategory.fonts,
                      onPressed: () => setState(
                        () => _category = _AppearanceCategory.fonts,
                      ),
                    ),
                    const SizedBox(width: 8),
                    MinimalChipButton(
                      label: 'Chat',
                      selected: _category == _AppearanceCategory.chat,
                      onPressed: () => setState(
                        () => _category = _AppearanceCategory.chat,
                      ),
                    ),
                    const SizedBox(width: 8),
                    MinimalChipButton(
                      label: 'Avatars',
                      selected: _category == _AppearanceCategory.avatars,
                      onPressed: () => setState(
                        () => _category = _AppearanceCategory.avatars,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (_category == _AppearanceCategory.presets) ...[
                SettingsUi.sectionTitle(context, 'Theme presets'),
                const SizedBox(height: 10),
                ...ThemePresets.all.map((preset) {
                  final selected = _draft.presetId == preset.id;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Material(
                      color: selected
                          ? scheme.primaryContainer.withValues(alpha: 0.55)
                          : scheme.surfaceContainerHigh.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => _applyPreset(preset),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              _PresetSwatch(palette: preset.palette),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      preset.name,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleSmall,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${preset.visualStyle.label} · '
                                      '${preset.description}',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                              if (selected)
                                Icon(Icons.check_circle, color: scheme.primary),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }),
                if (_draft.isCustom) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Custom — you’ve tweaked colors or options away from a '
                    'named preset.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
                ],
                if (_category == _AppearanceCategory.layout) ...[
                SettingsUi.sectionTitle(context, 'Background'),
                const SizedBox(height: 8),
                Text('Style', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                SegmentedButton<VisualStyle>(
                  segments: [
                    for (final style in VisualStyle.values)
                      ButtonSegment(value: style, label: Text(style.label)),
                  ],
                  selected: {_draft.visualStyle},
                  onSelectionChanged: (selected) {
                    setState(() {
                      _draft = _draft.copyWith(
                        visualStyle: selected.first,
                        markCustom: true,
                      );
                    });
                  },
                ),
                const SizedBox(height: 12),
                Text(
                  'Background mode',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                SegmentedButton<BackgroundMode>(
                  segments: [
                    for (final mode in BackgroundMode.values)
                      ButtonSegment(value: mode, label: Text(mode.label)),
                  ],
                  selected: {_draft.backgroundMode},
                  onSelectionChanged: (selected) {
                    setState(() {
                      _draft = _draft.copyWith(
                        backgroundMode: selected.first,
                        markCustom: true,
                      );
                    });
                  },
                ),
                _colorTile(
                  label: 'Background',
                  color: _draft.palette.background,
                  onPicked: (c) {
                    _draft = _draft.copyWith(
                      palette: _draft.palette.copyWith(background: c),
                      markCustom: true,
                    );
                  },
                ),
                _colorTile(
                  label: 'Background alt',
                  color: _draft.palette.backgroundAlt,
                  onPicked: (c) {
                    _draft = _draft.copyWith(
                      palette: _draft.palette.copyWith(backgroundAlt: c),
                      markCustom: true,
                    );
                  },
                ),
                const SizedBox(height: 12),
                ],
                if (_category == _AppearanceCategory.colors) ...[
                SettingsUi.sectionTitle(context, 'Colors'),
                _colorTile(
                  label: 'Accent',
                  color: _draft.palette.accent,
                  onPicked: (c) {
                    _draft = _draft.copyWith(
                      palette: _draft.palette.copyWith(accent: c),
                      markCustom: true,
                    );
                  },
                ),
                _colorTile(
                  label: 'Accent deep',
                  color: _draft.palette.accentDeep,
                  onPicked: (c) {
                    _draft = _draft.copyWith(
                      palette: _draft.palette.copyWith(accentDeep: c),
                      markCustom: true,
                    );
                  },
                ),
                _colorTile(
                  label: 'Header / app bar',
                  color: _draft.palette.header,
                  onPicked: (c) {
                    _draft = _draft.copyWith(
                      palette: _draft.palette.copyWith(header: c),
                      markCustom: true,
                    );
                  },
                ),
                _colorTile(
                  label: 'Menu / surface',
                  color: _draft.palette.surface,
                  onPicked: (c) {
                    _draft = _draft.copyWith(
                      palette: _draft.palette.copyWith(surface: c),
                      markCustom: true,
                    );
                  },
                ),
                _colorTile(
                  label: 'Surface high',
                  color: _draft.palette.surfaceHigh,
                  onPicked: (c) {
                    _draft = _draft.copyWith(
                      palette: _draft.palette.copyWith(surfaceHigh: c),
                      markCustom: true,
                    );
                  },
                ),
                _colorTile(
                  label: 'Main text',
                  color: _draft.palette.text,
                  onPicked: (c) {
                    _draft = _draft.copyWith(
                      palette: _draft.palette.copyWith(text: c),
                      markCustom: true,
                    );
                  },
                ),
                _colorTile(
                  label: 'Muted text',
                  color: _draft.palette.textMuted,
                  onPicked: (c) {
                    _draft = _draft.copyWith(
                      palette: _draft.palette.copyWith(textMuted: c),
                      markCustom: true,
                    );
                  },
                ),
                _colorTile(
                  label: 'Your bubble',
                  color: _draft.palette.userBubble,
                  onPicked: (c) {
                    _draft = _draft.copyWith(
                      palette: _draft.palette.copyWith(userBubble: c),
                      markCustom: true,
                    );
                  },
                ),
                _colorTile(
                  label: 'AI bubble',
                  color: _draft.palette.aiBubble,
                  onPicked: (c) {
                    _draft = _draft.copyWith(
                      palette: _draft.palette.copyWith(aiBubble: c),
                      markCustom: true,
                    );
                  },
                ),
                _colorTile(
                  label: 'RP action text (*asterisks*)',
                  color: _draft.palette.resolvedRpActionText,
                  onPicked: (c) {
                    _draft = _draft.copyWith(
                      palette: _draft.palette.copyWith(rpActionText: c),
                    );
                  },
                ),
                _colorTile(
                  label: 'RP dialogue text ("quotes")',
                  color: _draft.palette.resolvedRpDialogueText,
                  onPicked: (c) {
                    _draft = _draft.copyWith(
                      palette: _draft.palette.copyWith(rpDialogueText: c),
                    );
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Light surfaces'),
                  subtitle: const Text(
                    'Use a light color scheme (Ivory-style readability).',
                  ),
                  value: _draft.palette.brightness == Brightness.light,
                  onChanged: (value) {
                    setState(() {
                      _draft = _draft.copyWith(
                        palette: _draft.palette.copyWith(
                          brightness: value
                              ? Brightness.light
                              : Brightness.dark,
                        ),
                        markCustom: true,
                      );
                    });
                  },
                ),
                const SizedBox(height: 12),
                ],
                if (_category == _AppearanceCategory.fonts) ...[
                SettingsUi.sectionTitle(context, 'Fonts & size'),
                const SizedBox(height: 8),
                DropdownButtonFormField<AnimaFontChoice>(
                  initialValue: _draft.headingFont,
                  decoration: SettingsUi.fieldDecoration(label: 'Heading font'),
                  items: [
                    for (final font in AnimaFontChoice.values)
                      DropdownMenuItem(value: font, child: Text(font.label)),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _draft = _draft.copyWith(
                        headingFont: value,
                        markCustom: true,
                      );
                    });
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<AnimaFontChoice>(
                  initialValue: _draft.bodyFont,
                  decoration: SettingsUi.fieldDecoration(label: 'Body font'),
                  items: [
                    for (final font in AnimaFontChoice.values)
                      DropdownMenuItem(value: font, child: Text(font.label)),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _draft = _draft.copyWith(
                        bodyFont: value,
                        markCustom: true,
                      );
                    });
                  },
                ),
                Text(
                  'Text scale (${_draft.textScale.toStringAsFixed(2)}×)',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Slider(
                  value: _draft.textScale,
                  min: UiStyleSettings.minTextScale,
                  max: UiStyleSettings.maxTextScale,
                  onChanged: (v) {
                    setState(() {
                      _draft = _draft.copyWith(textScale: v, markCustom: true);
                    });
                  },
                ),
                Text(
                  'Heading scale (${_draft.headingScale.toStringAsFixed(2)}×)',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Slider(
                  value: _draft.headingScale,
                  min: UiStyleSettings.minHeadingScale,
                  max: UiStyleSettings.maxHeadingScale,
                  onChanged: (v) {
                    setState(() {
                      _draft = _draft.copyWith(
                        headingScale: v,
                        markCustom: true,
                      );
                    });
                  },
                ),
                Text(
                  'Chat text scale (${_draft.chatFontScale.toStringAsFixed(2)}×)',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Slider(
                  value: _draft.chatFontScale,
                  min: UiStyleSettings.minChatFontScale,
                  max: UiStyleSettings.maxChatFontScale,
                  onChanged: (v) {
                    setState(() {
                      _draft = _draft.copyWith(
                        chatFontScale: v,
                        markCustom: true,
                      );
                    });
                  },
                ),
                const SizedBox(height: 8),
                ],
                if (_category == _AppearanceCategory.layout) ...[
                SettingsUi.sectionTitle(context, 'Shape & glass'),
                Text(
                  'Corner roundness (${_draft.cornerRadius.round()})',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Slider(
                  value: _draft.cornerRadius,
                  min: UiStyleSettings.minCornerRadius,
                  max: UiStyleSettings.maxCornerRadius,
                  onChanged: (v) {
                    setState(() {
                      _draft = _draft.copyWith(
                        cornerRadius: v,
                        markCustom: true,
                      );
                    });
                  },
                ),
                if (_draft.isGlass) ...[
                  Text(
                    'Glass opacity (${_draft.glassOpacity.toStringAsFixed(2)})',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Slider(
                    value: _draft.glassOpacity,
                    min: UiStyleSettings.minGlassOpacity,
                    max: UiStyleSettings.maxGlassOpacity,
                    onChanged: (v) {
                      setState(() {
                        _draft = _draft.copyWith(
                          glassOpacity: v,
                          markCustom: true,
                        );
                      });
                    },
                  ),
                  Text(
                    'Glass blur (${_draft.glassBlur.round()})',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Slider(
                    value: _draft.glassBlur,
                    min: UiStyleSettings.minGlassBlur,
                    max: UiStyleSettings.maxGlassBlur,
                    onChanged: (v) {
                      setState(() {
                        _draft = _draft.copyWith(
                          glassBlur: v,
                          markCustom: true,
                        );
                      });
                    },
                  ),
                ],
                ],
                if (_category == _AppearanceCategory.chat) ...[
                SettingsUi.sectionTitle(context, 'Chat experience'),
                const SizedBox(height: 8),
                Text(
                  'Storybook mode is inspired by immersive RP themes — speaker '
                  'headers, side hero portraits that fade into bubbles, and an '
                  'optional custom image behind the chat.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                SegmentedButton<ChatLayoutMode>(
                  segments: [
                    for (final mode in ChatLayoutMode.values)
                      ButtonSegment(
                        value: mode,
                        label: Text(mode.label),
                      ),
                  ],
                  selected: {_draft.chatExperience.layoutMode},
                  onSelectionChanged: (selected) {
                    if (selected.isEmpty) return;
                    final mode = selected.first;
                    setState(() {
                      _draft = _draft.copyWith(
                        chatExperience: mode == ChatLayoutMode.storybook
                            ? ChatExperienceSettings.storybook
                            : const ChatExperienceSettings(),
                        markCustom: true,
                      );
                    });
                  },
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Chat background image'),
                  subtitle: const Text(
                    'Pick a photo from your device — stays fixed while you chat',
                  ),
                  value: _draft.chatExperience.backgroundEnabled,
                  onChanged: (value) {
                    setState(() {
                      _draft = _draft.copyWith(
                        chatExperience: _draft.chatExperience.copyWith(
                          backgroundEnabled: value,
                        ),
                        markCustom: true,
                      );
                    });
                  },
                ),
                if (_draft.chatExperience.backgroundEnabled) ...[
                  const SizedBox(height: 8),
                  if (_backgroundPreviewPath != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: AspectRatio(
                        aspectRatio: 16 / 9,
                        child: Image.file(
                          File(_backgroundPreviewPath!),
                          fit: BoxFit.cover,
                        ),
                      ),
                    )
                  else
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                      ),
                      child: Text(
                        'No background chosen yet.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _pickChatBackground,
                          icon: const Icon(Icons.image_outlined),
                          label: Text(
                            _draft.chatExperience.hasBackgroundImage
                                ? 'Change image'
                                : 'Choose image',
                          ),
                        ),
                      ),
                      if (_draft.chatExperience.hasBackgroundImage) ...[
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: 'Remove background',
                          onPressed: _clearChatBackground,
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ],
                  ),
                  Text(
                    'Background blur (${_draft.chatExperience.backgroundBlur.round()})',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Slider(
                    value: _draft.chatExperience.backgroundBlur,
                    min: ChatExperienceSettings.minBackgroundBlur,
                    max: ChatExperienceSettings.maxBackgroundBlur,
                    onChanged: (v) {
                      setState(() {
                        _draft = _draft.copyWith(
                          chatExperience: _draft.chatExperience.copyWith(
                            backgroundBlur: v,
                          ),
                          markCustom: true,
                        );
                      });
                    },
                  ),
                ],
                Text(
                  'Bubble opacity (${(_draft.chatExperience.bubbleOpacity * 100).round()}%)',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Slider(
                  value: _draft.chatExperience.bubbleOpacity,
                  min: ChatExperienceSettings.minBubbleOpacity,
                  max: ChatExperienceSettings.maxBubbleOpacity,
                  onChanged: (v) {
                    setState(() {
                      _draft = _draft.copyWith(
                        chatExperience: _draft.chatExperience.copyWith(
                          bubbleOpacity: v,
                        ),
                        markCustom: true,
                      );
                    });
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Speaker name above messages'),
                  subtitle: const Text(
                    'Small avatar + name header on each bubble',
                  ),
                  value: _draft.chatExperience.showSpeakerHeader,
                  onChanged: (value) {
                    setState(() {
                      _draft = _draft.copyWith(
                        chatExperience: _draft.chatExperience.copyWith(
                          showSpeakerHeader: value,
                        ),
                        markCustom: true,
                      );
                    });
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Side hero portrait'),
                  subtitle: const Text(
                    'Portrait inside each bubble — one border, fades into the text',
                  ),
                  value: _draft.chatExperience.showSideHeroPortrait,
                  onChanged: (value) {
                    setState(() {
                      _draft = _draft.copyWith(
                        chatExperience: _draft.chatExperience.copyWith(
                          showSideHeroPortrait: value,
                        ),
                        markCustom: true,
                      );
                    });
                  },
                ),
                ],
                if (_category == _AppearanceCategory.avatars) ...[
                SettingsUi.sectionTitle(context, 'Chat avatars'),
                const SizedBox(height: 12),
                Center(
                  child: AnimaAvatar(
                    label: 'You',
                    style: _draft.avatarStyle,
                    icon: Icons.person,
                  ),
                ),
                const SizedBox(height: 16),
                Text('Shape', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                SegmentedButton<AvatarShape>(
                  segments: [
                    for (final shape in AvatarShape.values)
                      ButtonSegment(value: shape, label: Text(shape.label)),
                  ],
                  selected: {_draft.avatarStyle.shape},
                  onSelectionChanged: (selected) {
                    setState(() {
                      _draft = _draft.copyWith(
                        avatarStyle: _draft.avatarStyle.copyWith(
                          shape: selected.first,
                        ),
                      );
                    });
                  },
                ),
                const SizedBox(height: 16),
                Text('Size', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                SegmentedButton<AvatarSizeTier>(
                  segments: [
                    for (final tier in AvatarSizeTier.values)
                      ButtonSegment(value: tier, label: Text(tier.label)),
                  ],
                  selected: {_draft.avatarStyle.sizeTier},
                  onSelectionChanged: (selected) {
                    setState(() {
                      _draft = _draft.copyWith(
                        avatarStyle: _draft.avatarStyle.copyWith(
                          sizeTier: selected.first,
                        ),
                      );
                    });
                  },
                ),
                Text(
                  'Fine scale (${_draft.avatarStyle.scale.toStringAsFixed(2)}×)',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Slider(
                  value: _draft.avatarStyle.scale,
                  min: AvatarStyleSettings.minScale,
                  max: AvatarStyleSettings.maxScale,
                  onChanged: (v) {
                    setState(() {
                      _draft = _draft.copyWith(
                        avatarStyle: _draft.avatarStyle.copyWith(scale: v),
                      );
                    });
                  },
                ),
                ],
                const SizedBox(height: 28),
                SettingsUi.saveButton(
                  saving: _saving,
                  label: 'Save appearance',
                  onPressed: _saving ? null : _save,
                ),
                const SizedBox(height: 24),
              ],
            ),
    );
  }
}

class _PresetSwatch extends StatelessWidget {
  const _PresetSwatch({required this.palette});

  final ThemePalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [palette.background, palette.accent, palette.surfaceHigh],
        ),
        border: Border.all(color: palette.text.withValues(alpha: 0.25)),
      ),
    );
  }
}

class _LivePreview extends StatelessWidget {
  const _LivePreview({required this.theme, required this.style});

  final ThemeData theme;
  final UiStyleSettings style;

  @override
  Widget build(BuildContext context) {
    final ui = AnimaUiTheme.fromSettings(style);
    return Theme(
      data: theme,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Preview', style: theme.textTheme.titleMedium),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: style.palette.header.withValues(
                    alpha: style.isGlass ? style.glassOpacity : 1,
                  ),
                  borderRadius: BorderRadius.circular(style.cornerRadius),
                ),
                child: Text(
                  'Anima header',
                  style: theme.appBarTheme.titleTextStyle,
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: style.chatExperience.bubbleFill(ui.userBubbleColor),
                    borderRadius: BorderRadius.circular(ui.chatBubbleRadius),
                  ),
                  child: Text(
                    'Your message',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: ui.userBubbleForeground,
                      fontSize: 14 * ui.chatFontScale,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: style.chatExperience.bubbleFill(ui.aiBubbleColor),
                    borderRadius: BorderRadius.circular(ui.chatBubbleRadius),
                  ),
                  child: RpRichText(
                    text: '*smiles* "Hello there."',
                    baseStyle: theme.textTheme.bodyMedium!.copyWith(
                      color: ui.aiBubbleForeground,
                      fontSize: 14 * ui.chatFontScale,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ColorPickerDialog extends StatefulWidget {
  const _ColorPickerDialog({required this.title, required this.initial});

  final String title;
  final Color initial;

  @override
  State<_ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<_ColorPickerDialog> {
  static const _swatches = <Color>[
    Color(0xFFE8C547),
    Color(0xFF6EB6FF),
    Color(0xFF4FD68A),
    Color(0xFFFF8FB8),
    Color(0xFFC084FC),
    Color(0xFFD4A373),
    Color(0xFF8AB4F8),
    Color(0xFF8B5E34),
    Color(0xFFF4F0E6),
    Color(0xFF050508),
    Color(0xFF1E1E28),
    Color(0xFFF6F1E8),
  ];

  late HSVColor _hsv;
  late TextEditingController _hex;

  @override
  void initState() {
    super.initState();
    _hsv = HSVColor.fromColor(widget.initial);
    _hex = TextEditingController(text: ThemePalette.colorToHex(widget.initial));
  }

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  void _setColor(Color color) {
    setState(() {
      _hsv = HSVColor.fromColor(color);
      _hex.text = ThemePalette.colorToHex(color);
    });
  }

  @override
  Widget build(BuildContext context) {
    final color = _hsv.toColor();
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 48,
              width: double.infinity,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final swatch in _swatches)
                  InkWell(
                    onTap: () => _setColor(swatch),
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: swatch,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Hue', style: Theme.of(context).textTheme.bodySmall),
            Slider(
              value: _hsv.hue,
              max: 360,
              onChanged: (v) {
                setState(() {
                  _hsv = _hsv.withHue(v);
                  _hex.text = ThemePalette.colorToHex(_hsv.toColor());
                });
              },
            ),
            Text('Saturation', style: Theme.of(context).textTheme.bodySmall),
            Slider(
              value: _hsv.saturation,
              onChanged: (v) {
                setState(() {
                  _hsv = _hsv.withSaturation(v);
                  _hex.text = ThemePalette.colorToHex(_hsv.toColor());
                });
              },
            ),
            Text('Lightness', style: Theme.of(context).textTheme.bodySmall),
            Slider(
              value: _hsv.value,
              onChanged: (v) {
                setState(() {
                  _hsv = _hsv.withValue(v);
                  _hex.text = ThemePalette.colorToHex(_hsv.toColor());
                });
              },
            ),
            TextField(
              controller: _hex,
              decoration: const InputDecoration(
                labelText: 'Hex (#AARRGGBB or #RRGGBB)',
                border: OutlineInputBorder(),
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[#0-9a-fA-F]')),
              ],
              onChanged: (raw) {
                final parsed = ThemePalette.colorFromHex(raw, color);
                if (ThemePalette.colorToHex(parsed) ==
                    ThemePalette.colorToHex(color)) {
                  return;
                }
                setState(() => _hsv = HSVColor.fromColor(parsed));
              },
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
          onPressed: () => Navigator.pop(context, color),
          child: const Text('Use color'),
        ),
      ],
    );
  }
}
