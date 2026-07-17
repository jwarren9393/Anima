import 'package:flutter/material.dart';

import '../models/ui_style_settings.dart';
import '../services/settings_service.dart';
import '../widgets/anima_avatar.dart';
import 'settings_ui.dart';

/// Slim appearance menu — chat avatars now; room for more later.
/// App theme is fixed Obsidian & Gold (not customizable here).
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
  AvatarStyleSettings _avatarStyle = const AvatarStyleSettings();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final style = await widget.settingsService.getUiStyle();
    if (!mounted) return;
    setState(() {
      _avatarStyle = style.avatarStyle;
      _loading = false;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await widget.settingsService.saveUiStyle(
      UiStyleSettings(avatarStyle: _avatarStyle),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Appearance saved.')),
    );
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Appearance')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: SettingsUi.listPadding,
              children: [
                SettingsUi.sectionHint(
                  context,
                  'Anima uses a fixed Obsidian & Gold glass look. '
                  'Chat avatars can still be tuned below — more options can '
                  'land here later.',
                ),
                const SizedBox(height: 24),
                SettingsUi.sectionTitle(context, 'Chat avatars'),
                const SizedBox(height: 12),
                Center(
                  child: AnimaAvatar(
                    label: 'You',
                    style: _avatarStyle,
                    icon: Icons.person,
                  ),
                ),
                const SizedBox(height: 16),
                Text('Shape', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                SegmentedButton<AvatarShape>(
                  segments: [
                    for (final shape in AvatarShape.values)
                      ButtonSegment(
                        value: shape,
                        label: Text(shape.label),
                      ),
                  ],
                  selected: {_avatarStyle.shape},
                  onSelectionChanged: (selected) {
                    setState(() {
                      _avatarStyle =
                          _avatarStyle.copyWith(shape: selected.first);
                    });
                  },
                ),
                const SizedBox(height: 16),
                Text('Size', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                SegmentedButton<AvatarSizeTier>(
                  segments: [
                    for (final tier in AvatarSizeTier.values)
                      ButtonSegment(
                        value: tier,
                        label: Text(tier.label),
                      ),
                  ],
                  selected: {_avatarStyle.sizeTier},
                  onSelectionChanged: (selected) {
                    setState(() {
                      _avatarStyle =
                          _avatarStyle.copyWith(sizeTier: selected.first);
                    });
                  },
                ),
                const SizedBox(height: 8),
                Text(
                  'Fine scale (${_avatarStyle.scale.toStringAsFixed(2)}×)',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Slider(
                  value: _avatarStyle.scale,
                  min: AvatarStyleSettings.minScale,
                  max: AvatarStyleSettings.maxScale,
                  label: '${_avatarStyle.scale.toStringAsFixed(2)}×',
                  onChanged: (v) {
                    setState(() {
                      _avatarStyle = _avatarStyle.copyWith(scale: v);
                    });
                  },
                ),
                const SizedBox(height: 8),
                Text(
                  'Applies to persona and character photos in chat.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 28),
                SettingsUi.saveButton(
                  saving: _saving,
                  label: 'Save appearance',
                  onPressed: _saving ? null : _save,
                ),
              ],
            ),
    );
  }
}
