import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/ui_style_settings.dart';
import '../services/settings_service.dart';
import '../theme/anima_theme.dart';
import '../widgets/anima_avatar.dart';
import 'settings_ui.dart';

/// Full look-and-feel studio — presets, colors, type, background, chat, motion.
class AppearanceSettingsScreen extends StatefulWidget {
  const AppearanceSettingsScreen({
    super.key,
    required this.settingsService,
  });

  final SettingsService settingsService;

  @override
  State<AppearanceSettingsScreen> createState() =>
      _AppearanceSettingsScreenState();
}

class _AppearanceSettingsScreenState extends State<AppearanceSettingsScreen> {
  bool _loading = true;
  bool _saving = false;
  bool _ttsEnabled = false;
  String _themeMode = 'system';
  UiStyleSettings _style = const UiStyleSettings();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final themeMode = await widget.settingsService.getThemeModeName();
    final tts = await widget.settingsService.getTtsEnabled();
    final style = await widget.settingsService.getUiStyle();
    if (!mounted) return;
    setState(() {
      _themeMode = themeMode;
      _ttsEnabled = tts;
      _style = style;
      _loading = false;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await widget.settingsService.saveThemeModeName(_themeMode);
    await widget.settingsService.saveTtsEnabled(_ttsEnabled);
    await widget.settingsService.saveUiStyle(_style);
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Appearance saved.')),
    );
    Navigator.of(context).pop(true);
  }

  Future<void> _resetDefaults() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset appearance?'),
        content: const Text(
          'Restore the default Parchment look, fonts, and motion. '
          'Light/Dark mode and TTS stay as they are.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (ok == true) {
      setState(() => _style = const UiStyleSettings());
    }
  }

  Future<void> _pickColor({
    required String title,
    required Color? current,
    required Color fallback,
    required void Function(Color?) onPicked,
  }) async {
    final result = await showDialog<Color?>(
      context: context,
      builder: (context) => _ColorPickerDialog(
        title: title,
        initial: current ?? fallback,
        allowClear: current != null,
      ),
    );
    if (!mounted) return;
    if (result == _ColorPickerDialog.clearSentinel) {
      onPicked(null);
    } else if (result != null) {
      onPicked(result);
    }
  }

  ThemeData get _previewTheme {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return dark ? AnimaTheme.dark(_style) : AnimaTheme.light(_style);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Appearance'),
        actions: [
          TextButton(
            onPressed: _loading || _saving ? null : _resetDefaults,
            child: const Text('Reset'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Theme(
              data: _previewTheme,
              child: ListView(
                padding: SettingsUi.listPadding,
                children: [
                  SettingsUi.sectionHint(
                    context,
                    'Build your own look: pick a preset, then tweak colors, '
                    'type, background, chat chrome, and motion. Save applies '
                    'everywhere.',
                  ),
                  const SizedBox(height: 20),
                  SettingsUi.sectionTitle(context, 'Light / Dark'),
                  const SizedBox(height: 8),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'system', label: Text('System')),
                      ButtonSegment(value: 'light', label: Text('Light')),
                      ButtonSegment(value: 'dark', label: Text('Dark')),
                    ],
                    selected: {_themeMode},
                    onSelectionChanged: (selected) {
                      setState(() => _themeMode = selected.first);
                    },
                  ),
                  const SizedBox(height: 24),
                  SettingsUi.sectionTitle(context, 'Look presets'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final preset in VisualPreset.values)
                        ChoiceChip(
                          label: Text(preset.label),
                          selected: _style.preset == preset,
                          onSelected: (_) {
                            setState(() => _style = _style.withPreset(preset));
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _style.preset.blurb,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 16),
                  _PreviewCard(style: _style),
                  const SizedBox(height: 8),
                  ExpansionTile(
                    initiallyExpanded: true,
                    tilePadding: EdgeInsets.zero,
                    title: Text(
                      'Colors',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    subtitle: const Text(
                      'Primary, accent, page, ink, chat bubbles',
                    ),
                    children: [
                      _ColorRow(
                        label: 'Primary',
                        color: _style.primaryColor ??
                            _previewTheme.colorScheme.primary,
                        overridden: _style.primaryColor != null,
                        onTap: () => _pickColor(
                          title: 'Primary color',
                          current: _style.primaryColor,
                          fallback: _previewTheme.colorScheme.primary,
                          onPicked: (c) => setState(() {
                            _style = c == null
                                ? _style.copyWith(clearPrimary: true)
                                : _style.copyWith(primaryColor: c);
                          }),
                        ),
                      ),
                      _ColorRow(
                        label: 'Accent',
                        color: _style.accentColor ??
                            _previewTheme.colorScheme.secondary,
                        overridden: _style.accentColor != null,
                        onTap: () => _pickColor(
                          title: 'Accent color',
                          current: _style.accentColor,
                          fallback: _previewTheme.colorScheme.secondary,
                          onPicked: (c) => setState(() {
                            _style = c == null
                                ? _style.copyWith(clearAccent: true)
                                : _style.copyWith(accentColor: c);
                          }),
                        ),
                      ),
                      _ColorRow(
                        label: 'Background',
                        color: _style.backgroundColor ??
                            (Theme.of(context).brightness == Brightness.dark
                                ? AnimaTheme.night
                                : AnimaTheme.parchmentDeep),
                        overridden: _style.backgroundColor != null,
                        onTap: () => _pickColor(
                          title: 'Background color',
                          current: _style.backgroundColor,
                          fallback: AnimaTheme.parchmentDeep,
                          onPicked: (c) => setState(() {
                            _style = c == null
                                ? _style.copyWith(clearBackground: true)
                                : _style.copyWith(backgroundColor: c);
                          }),
                        ),
                      ),
                      _ColorRow(
                        label: 'Surfaces / menus',
                        color: _style.surfaceColor ??
                            _previewTheme.colorScheme.surface,
                        overridden: _style.surfaceColor != null,
                        onTap: () => _pickColor(
                          title: 'Surface color',
                          current: _style.surfaceColor,
                          fallback: _previewTheme.colorScheme.surface,
                          onPicked: (c) => setState(() {
                            _style = c == null
                                ? _style.copyWith(clearSurface: true)
                                : _style.copyWith(surfaceColor: c);
                          }),
                        ),
                      ),
                      _ColorRow(
                        label: 'Text / ink',
                        color: _style.inkColor ??
                            _previewTheme.colorScheme.onSurface,
                        overridden: _style.inkColor != null,
                        onTap: () => _pickColor(
                          title: 'Text color',
                          current: _style.inkColor,
                          fallback: _previewTheme.colorScheme.onSurface,
                          onPicked: (c) => setState(() {
                            _style = c == null
                                ? _style.copyWith(clearInk: true)
                                : _style.copyWith(inkColor: c);
                          }),
                        ),
                      ),
                      _ColorRow(
                        label: 'Your chat bubbles',
                        color: _style.userBubbleColor ??
                            _previewTheme.colorScheme.primaryContainer,
                        overridden: _style.userBubbleColor != null,
                        onTap: () => _pickColor(
                          title: 'Your bubble color',
                          current: _style.userBubbleColor,
                          fallback: _previewTheme.colorScheme.primaryContainer,
                          onPicked: (c) => setState(() {
                            _style = c == null
                                ? _style.copyWith(clearUserBubble: true)
                                : _style.copyWith(userBubbleColor: c);
                          }),
                        ),
                      ),
                      _ColorRow(
                        label: 'AI chat bubbles',
                        color: _style.aiBubbleColor ??
                            _previewTheme.colorScheme.surfaceContainerLowest,
                        overridden: _style.aiBubbleColor != null,
                        onTap: () => _pickColor(
                          title: 'AI bubble color',
                          current: _style.aiBubbleColor,
                          fallback:
                              _previewTheme.colorScheme.surfaceContainerLowest,
                          onPicked: (c) => setState(() {
                            _style = c == null
                                ? _style.copyWith(clearAiBubble: true)
                                : _style.copyWith(aiBubbleColor: c);
                          }),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: Text(
                      'Typography',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    subtitle: const Text('Font family and size'),
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final pair in FontPairing.values)
                            ChoiceChip(
                              label: Text(pair.label),
                              selected: _style.fontPairing == pair,
                              onSelected: (_) {
                                setState(
                                  () =>
                                      _style = _style.copyWith(fontPairing: pair),
                                );
                              },
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _style.fontPairing.blurb,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'App text size (${_style.fontScale.toStringAsFixed(2)}×)',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      Slider(
                        value: _style.fontScale,
                        min: UiStyleSettings.minFontScale,
                        max: UiStyleSettings.maxFontScale,
                        divisions: 10,
                        label: '${_style.fontScale.toStringAsFixed(2)}×',
                        onChanged: (v) => setState(
                          () => _style = _style.copyWith(fontScale: v),
                        ),
                      ),
                      Text(
                        'Chat message size '
                        '(${_style.chatFontScale.toStringAsFixed(2)}×)',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      Slider(
                        value: _style.chatFontScale,
                        min: UiStyleSettings.minChatFontScale,
                        max: UiStyleSettings.maxChatFontScale,
                        divisions: 12,
                        label: '${_style.chatFontScale.toStringAsFixed(2)}×',
                        onChanged: (v) => setState(
                          () => _style = _style.copyWith(chatFontScale: v),
                        ),
                      ),
                    ],
                  ),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: Text(
                      'Background',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    subtitle: const Text('Wash, texture, vignette'),
                    children: [
                      Text('Style', style: Theme.of(context).textTheme.labelLarge),
                      const SizedBox(height: 8),
                      SegmentedButton<BackgroundStyle>(
                        segments: [
                          for (final s in BackgroundStyle.values)
                            ButtonSegment(value: s, label: Text(s.label)),
                        ],
                        selected: {_style.backgroundStyle},
                        onSelectionChanged: (s) {
                          setState(
                            () => _style =
                                _style.copyWith(backgroundStyle: s.first),
                          );
                        },
                      ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Fiber texture'),
                    subtitle: const Text(
                      'Optional faint paper grain — off by default',
                    ),
                    value: _style.showTexture,
                    onChanged: (v) => setState(
                      () => _style = _style.copyWith(showTexture: v),
                    ),
                  ),
                      if (_style.showTexture) ...[
                        Text(
                          'Texture strength '
                          '(${(_style.textureIntensity * 100).round()}%)',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        Slider(
                          value: _style.textureIntensity,
                          min: UiStyleSettings.minTexture,
                          max: UiStyleSettings.maxTexture,
                          divisions: 20,
                          onChanged: (v) => setState(
                            () =>
                                _style = _style.copyWith(textureIntensity: v),
                          ),
                        ),
                      ],
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Edge vignette'),
                        subtitle: const Text('Soft darkening toward page edges'),
                        value: _style.showVignette,
                        onChanged: (v) => setState(
                          () => _style = _style.copyWith(showVignette: v),
                        ),
                      ),
                    ],
                  ),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: Text(
                      'Shape & density',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    subtitle: const Text('Corners, lists, spacing'),
                    children: [
                      Text(
                        'App corner roundness '
                        '(${_style.cornerRadius.round()})',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      Slider(
                        value: _style.cornerRadius,
                        min: UiStyleSettings.minCorner,
                        max: UiStyleSettings.maxCorner,
                        divisions: 18,
                        onChanged: (v) => setState(
                          () => _style = _style.copyWith(cornerRadius: v),
                        ),
                      ),
                      Text('List density',
                          style: Theme.of(context).textTheme.labelLarge),
                      const SizedBox(height: 8),
                      SegmentedButton<UiDensity>(
                        segments: [
                          for (final d in UiDensity.values)
                            ButtonSegment(value: d, label: Text(d.label)),
                        ],
                        selected: {_style.density},
                        onSelectionChanged: (s) {
                          setState(
                            () => _style = _style.copyWith(density: s.first),
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: Text(
                      'Chat chrome',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    subtitle: const Text('Bubbles, spacing, avatars'),
                    children: [
                      Text(
                        'Bubble roundness '
                        '(${_style.chatBubbleRadius.round()})',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      Slider(
                        value: _style.chatBubbleRadius,
                        min: UiStyleSettings.minBubbleRadius,
                        max: UiStyleSettings.maxBubbleRadius,
                        divisions: 24,
                        onChanged: (v) => setState(
                          () =>
                              _style = _style.copyWith(chatBubbleRadius: v),
                        ),
                      ),
                      Text(
                        'Message spacing '
                        '(${_style.messageSpacing.toStringAsFixed(0)})',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      Slider(
                        value: _style.messageSpacing,
                        min: UiStyleSettings.minMessageSpacing,
                        max: UiStyleSettings.maxMessageSpacing,
                        divisions: 12,
                        onChanged: (v) => setState(
                          () =>
                              _style = _style.copyWith(messageSpacing: v),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Center(
                        child: AnimaAvatar(
                          label: 'A',
                          style: _style.avatarStyle,
                          icon: Icons.smart_toy_outlined,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text('Avatar shape',
                          style: Theme.of(context).textTheme.labelLarge),
                      const SizedBox(height: 8),
                      SegmentedButton<AvatarShape>(
                        segments: [
                          for (final shape in AvatarShape.values)
                            ButtonSegment(
                              value: shape,
                              label: Text(shape.label),
                            ),
                        ],
                        selected: {_style.avatarStyle.shape},
                        onSelectionChanged: (s) {
                          setState(() {
                            _style = _style.copyWith(
                              avatarStyle:
                                  _style.avatarStyle.copyWith(shape: s.first),
                            );
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      Text('Avatar size',
                          style: Theme.of(context).textTheme.labelLarge),
                      const SizedBox(height: 8),
                      SegmentedButton<AvatarSizeTier>(
                        segments: [
                          for (final tier in AvatarSizeTier.values)
                            ButtonSegment(
                              value: tier,
                              label: Text(tier.label),
                            ),
                        ],
                        selected: {_style.avatarStyle.sizeTier},
                        onSelectionChanged: (s) {
                          setState(() {
                            _style = _style.copyWith(
                              avatarStyle: _style.avatarStyle
                                  .copyWith(sizeTier: s.first),
                            );
                          });
                        },
                      ),
                      Text(
                        'Avatar scale '
                        '(${_style.avatarStyle.scale.toStringAsFixed(2)}×)',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      Slider(
                        value: _style.avatarStyle.scale,
                        min: AvatarStyleSettings.minScale,
                        max: AvatarStyleSettings.maxScale,
                        divisions: 15,
                        onChanged: (v) {
                          setState(() {
                            _style = _style.copyWith(
                              avatarStyle:
                                  _style.avatarStyle.copyWith(scale: v),
                            );
                          });
                        },
                      ),
                    ],
                  ),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: Text(
                      'Motion',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    subtitle: const Text('Page transitions & animation speed'),
                    children: [
                      SegmentedButton<MotionPreference>(
                        segments: [
                          for (final m in MotionPreference.values)
                            ButtonSegment(value: m, label: Text(m.label)),
                        ],
                        selected: {_style.motion},
                        onSelectionChanged: (s) {
                          setState(
                            () => _style = _style.copyWith(motion: s.first),
                          );
                        },
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _style.motion == MotionPreference.off
                            ? 'Animations off — instant screen changes.'
                            : 'Affects page transitions and scroll animation feel.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: Text(
                      'Sound',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    children: [
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Read replies aloud (TTS)'),
                        subtitle: const Text(
                          'Uses your phone’s voice. Long-press a message → Speak.',
                        ),
                        value: _ttsEnabled,
                        onChanged: (v) => setState(() => _ttsEnabled = v),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  SettingsUi.saveButton(
                    saving: _saving,
                    label: 'Save appearance',
                    onPressed: _saving ? null : _save,
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({required this.style});

  final UiStyleSettings style;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ui = AnimaUiTheme.of(context);
    final userBg = style.userBubbleColor ?? scheme.primaryContainer;
    final aiBg = style.aiBubbleColor ?? scheme.surfaceContainerLowest;
    final radius = BorderRadius.circular(style.chatBubbleRadius);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Live preview',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: aiBg,
                  borderRadius: radius,
                  border: Border.all(color: scheme.outlineVariant),
                ),
                child: Text(
                  'The road goes ever on…',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontSize: (Theme.of(context)
                                    .textTheme
                                    .bodyLarge
                                    ?.fontSize ??
                                16) *
                            ui.chatFontScale,
                      ),
                ),
              ),
            ),
            SizedBox(height: style.messageSpacing + 6),
            Align(
              alignment: Alignment.centerRight,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: userBg,
                  borderRadius: radius,
                  border: Border.all(
                    color: scheme.primary.withValues(alpha: 0.35),
                  ),
                ),
                child: Text(
                  'And I shall follow.',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: scheme.onPrimaryContainer,
                        fontSize: (Theme.of(context)
                                    .textTheme
                                    .bodyLarge
                                    ?.fontSize ??
                                16) *
                            ui.chatFontScale,
                      ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ColorRow extends StatelessWidget {
  const _ColorRow({
    required this.label,
    required this.color,
    required this.onTap,
    this.overridden = false,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool overridden;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      subtitle: Text(overridden ? 'Custom' : 'From preset'),
      trailing: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Theme.of(context).colorScheme.outline),
        ),
      ),
      onTap: onTap,
    );
  }
}

class _ColorPickerDialog extends StatefulWidget {
  const _ColorPickerDialog({
    required this.title,
    required this.initial,
    this.allowClear = false,
  });

  static final clearSentinel = Color(0x00000001);

  final String title;
  final Color initial;
  final bool allowClear;

  @override
  State<_ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<_ColorPickerDialog> {
  static const _swatches = <Color>[
    Color(0xFF3D5C4A),
    Color(0xFFA67C3D),
    Color(0xFF2F6F6A),
    Color(0xFF3D4F6B),
    Color(0xFF8B4518),
    Color(0xFFB33B2A),
    Color(0xFF5B6E7A),
    Color(0xFF6B5B7A),
    Color(0xFFE8D9BC),
    Color(0xFFD9C7A3),
    Color(0xFF2C241B),
    Color(0xFF161410),
    Color(0xFFC5D4C8),
    Color(0xFFE8D4B0),
    Color(0xFFD5DDEA),
    Color(0xFFF2E4D0),
    Color(0xFFFFFFFF),
    Color(0xFF000000),
  ];

  late Color _selected;
  late TextEditingController _hex;

  @override
  void initState() {
    super.initState();
    _selected = widget.initial;
    _hex = TextEditingController(text: _toHex(widget.initial));
  }

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  String _toHex(Color c) {
    final v = c.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase();
    return v.substring(2); // RRGGBB
  }

  void _applyHex(String raw) {
    var text = raw.trim().replaceFirst('#', '');
    if (text.length == 6) {
      final parsed = int.tryParse(text, radix: 16);
      if (parsed != null) {
        setState(() => _selected = Color(0xFF000000 | parsed));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 320,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 48,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: _selected,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _hex,
                decoration: const InputDecoration(
                  labelText: 'Hex (RRGGBB)',
                  prefixText: '#',
                  border: OutlineInputBorder(),
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9a-fA-F]')),
                  LengthLimitingTextInputFormatter(6),
                ],
                onChanged: _applyHex,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final swatch in _swatches)
                    InkWell(
                      onTap: () {
                        setState(() {
                          _selected = swatch;
                          _hex.text = _toHex(swatch);
                        });
                      },
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: swatch,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _selected.toARGB32() == swatch.toARGB32()
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).colorScheme.outline,
                            width:
                                _selected.toARGB32() == swatch.toARGB32() ? 2.5 : 1,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (widget.allowClear)
          TextButton(
            onPressed: () =>
                Navigator.pop(context, _ColorPickerDialog.clearSentinel),
            child: const Text('Use preset'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _selected),
          child: const Text('Apply'),
        ),
      ],
    );
  }
}
