import 'package:flutter/material.dart';

import '../models/living_world.dart';
import '../services/living_world_factory_service.dart';
import '../services/living_world_service.dart';
import '../services/nanogpt_service.dart';
import '../services/settings_service.dart';

/// Collect a brainstorm pitch, run the multi-pass factory, save the notebook.
Future<LivingWorld?> showLivingWorldFactorySheet({
  required BuildContext context,
  required LivingWorldService worldService,
  required NanoGptService nanoGptService,
  required SettingsService settingsService,
}) {
  return showModalBottomSheet<LivingWorld>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _LivingWorldFactorySheet(
      worldService: worldService,
      nanoGptService: nanoGptService,
      settingsService: settingsService,
    ),
  );
}

class _LivingWorldFactorySheet extends StatefulWidget {
  const _LivingWorldFactorySheet({
    required this.worldService,
    required this.nanoGptService,
    required this.settingsService,
  });

  final LivingWorldService worldService;
  final NanoGptService nanoGptService;
  final SettingsService settingsService;

  @override
  State<_LivingWorldFactorySheet> createState() =>
      _LivingWorldFactorySheetState();
}

class _LivingWorldFactorySheetState extends State<_LivingWorldFactorySheet> {
  static const _factory = LivingWorldFactoryService();

  final _pitch = TextEditingController();
  double _places = 8;
  double _people = 24;
  bool _busy = false;
  String _status = '';
  String? _error;

  @override
  void dispose() {
    _pitch.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    if (_busy) return;
    final brainstorm = _pitch.text.trim();
    if (brainstorm.isEmpty) {
      setState(() => _error = 'Describe the world you want first.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _status = 'Starting factory…';
    });

    try {
      final build = await widget.settingsService.getCharacterBuildSettings();
      final mainModel = await widget.settingsService.getModel();
      final model = build.resolvedModel(mainModel);
      final sampling = build.toSampling().copyWith(
            // Factory passes need room for JSON lists.
            maxTokens: build.maxTokens.clamp(1024, 8192),
          );

      final request = LivingWorldFactoryRequest(
        brainstorm: brainstorm,
        targetPlaceCount: _places.round(),
        targetPersonCount: _people.round(),
      );

      final world = await _factory.compile(
        request: request,
        onProgress: (progress) {
          if (!mounted) return;
          setState(() => _status = progress.status);
        },
        completePass: (pass, messages) async {
          return widget.nanoGptService.complete(
            model: model,
            messages: messages,
            sampling: sampling,
          );
        },
      );

      final saved = await widget.worldService.save(world);
      if (!mounted) return;
      Navigator.of(context).pop(saved);
    } on NanoGptException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
        _status = '';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '$e';
        _status = '';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'World factory',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(
                'Multi-pass compile into a Living World notebook on disk '
                '(outline → places → people → relationships → events). '
                'Not Creation Center chat — each step writes structured JSON.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _pitch,
                enabled: !_busy,
                minLines: 4,
                maxLines: 8,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Describe the world',
                  alignLabelWithHint: true,
                  hintText:
                      'e.g. A rainy coastal town with a night market, a missing '
                      'crate mystery, and about twenty named locals…',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Places: ${_places.round()}',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              Slider(
                value: _places,
                min: 3,
                max: 20,
                divisions: 17,
                label: '${_places.round()}',
                onChanged: _busy
                    ? null
                    : (v) => setState(() => _places = v),
              ),
              Text(
                'People: ${_people.round()}',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              Slider(
                value: _people,
                min: 6,
                max: 50,
                divisions: 44,
                label: '${_people.round()}',
                onChanged: _busy
                    ? null
                    : (v) => setState(() => _people = v),
              ),
              if (_status.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (_busy)
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    if (_busy) const SizedBox(width: 10),
                    Expanded(child: Text(_status)),
                  ],
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: TextStyle(color: scheme.error),
                ),
              ],
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _busy ? null : _run,
                child: Text(_busy ? 'Building…' : 'Build world'),
              ),
              TextButton(
                onPressed: _busy ? null : () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
