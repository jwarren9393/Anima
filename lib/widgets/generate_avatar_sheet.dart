import 'package:flutter/material.dart';

import '../services/nanogpt_service.dart';
import '../services/settings_service.dart';

/// Bottom sheet: edit prompt, pick model, generate, preview, accept.
class GenerateAvatarSheet extends StatefulWidget {
  const GenerateAvatarSheet({
    super.key,
    required this.promptController,
    required this.settingsService,
    required this.nanoGptService,
    required this.onAccepted,
  });

  final TextEditingController promptController;
  final SettingsService settingsService;
  final NanoGptService nanoGptService;
  final Future<void> Function(NanoGptGeneratedImage image) onAccepted;

  @override
  State<GenerateAvatarSheet> createState() => _GenerateAvatarSheetState();
}

class _GenerateAvatarSheetState extends State<GenerateAvatarSheet> {
  bool _loadingModels = true;
  bool _generating = false;
  bool _subscriptionOnly = false;
  String? _modelsError;
  List<NanoGptImageModelInfo> _models = const [];
  String? _selectedModelId;
  NanoGptGeneratedImage? _preview;
  String? _creditsHint;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final savedModel = await widget.settingsService.getImageModel();
    final subscriptionOnly = await widget.settingsService
        .getUseSubscriptionApi();
    try {
      final models = await widget.nanoGptService.listImageModels(
        subscriptionOnly: subscriptionOnly,
      );
      if (!mounted) return;
      String? selected = savedModel;
      if (models.isNotEmpty && !models.any((m) => m.id == selected)) {
        selected = models.first.id;
      }
      setState(() {
        _subscriptionOnly = subscriptionOnly;
        _models = models;
        _selectedModelId = selected;
        _loadingModels = false;
      });
    } on NanoGptException catch (error) {
      if (!mounted) return;
      setState(() {
        _subscriptionOnly = subscriptionOnly;
        _loadingModels = false;
        _modelsError = error.message;
        _selectedModelId = savedModel;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _subscriptionOnly = subscriptionOnly;
        _loadingModels = false;
        _modelsError = 'Could not load image models: $error';
        _selectedModelId = savedModel;
      });
    }

    try {
      final credits = await widget.nanoGptService.getCredits();
      if (!mounted) return;
      final images = credits.dailyImages;
      if (images != null) {
        setState(() {
          _creditsHint =
              '${_whole(images.remaining)} / ${_whole(images.limit)} '
              'daily images remaining';
        });
      }
    } catch (_) {
      // Credits are optional context for the sheet.
    }
  }

  String _whole(double value) {
    if (value == value.roundToDouble()) return '${value.round()}';
    return value.toStringAsFixed(1);
  }

  NanoGptImageModelInfo? get _selectedModel {
    final id = _selectedModelId;
    if (id == null) return null;
    for (final model in _models) {
      if (model.id == id) return model;
    }
    return null;
  }

  String _modelLabel(NanoGptImageModelInfo model) {
    final bits = <String>[model.displayName];
    if (model.subscriptionIncluded || _subscriptionOnly) {
      bits.add('Included');
    } else {
      bits.add('Paid');
      if (model.pricePerImageUsd != null) {
        bits.add('\$${model.pricePerImageUsd!.toStringAsFixed(3)}');
      }
    }
    if (model.nsfw) bits.add('NSFW');
    return bits.join(' · ');
  }

  Future<bool> _confirmPaidIfNeeded(NanoGptImageModelInfo? model) async {
    if (_subscriptionOnly) return true;
    if (model == null || model.subscriptionIncluded) return true;
    final price = model.pricePerImageUsd;
    final priceText = price == null
        ? 'This model may charge wallet money.'
        : 'This model is about \$${price.toStringAsFixed(3)} per image (wallet).';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Paid image model?'),
        content: Text(
          '“${model.displayName}” is not on NanoGPT’s subscription image list. '
          '$priceText\n\n'
          'Continue only if you are okay spending real money. '
          'To stay on subscription allowance, turn on Use subscription API '
          'in Settings → API & connection.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Use paid model'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _generate() async {
    final prompt = widget.promptController.text.trim();
    final model = _selectedModelId?.trim() ?? '';
    if (prompt.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter an image prompt first.')),
      );
      return;
    }
    if (model.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Choose an image model in Settings → API & connection.',
          ),
        ),
      );
      return;
    }

    final selected = _selectedModel;
    if (!await _confirmPaidIfNeeded(selected)) return;
    if (!mounted) return;

    setState(() {
      _generating = true;
      _preview = null;
    });
    try {
      await widget.settingsService.saveImageModel(model);
      final resolution = selected?.preferredSquareResolution;
      final image = await widget.nanoGptService.generateImage(
        model: model,
        prompt: prompt,
        resolution: resolution,
        subscriptionOnly: _subscriptionOnly,
      );
      if (!mounted) return;
      setState(() => _preview = image);

      try {
        final credits = await widget.nanoGptService.getCredits();
        if (!mounted) return;
        final images = credits.dailyImages;
        if (images != null) {
          setState(() {
            _creditsHint =
                '${_whole(images.remaining)} / ${_whole(images.limit)} '
                'daily images remaining';
          });
        }
      } catch (_) {}
    } on NanoGptException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.message),
          backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Image generation failed: $error'),
          backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
        ),
      );
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _usePreview() async {
    final preview = _preview;
    if (preview == null || _generating) return;
    await widget.onAccepted(preview);
    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 8, 16, bottomInset + 16),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Generate avatar', style: theme.textTheme.titleLarge),
              const SizedBox(height: 6),
              Text(
                _subscriptionOnly
                    ? 'Subscription mode: only NanoGPT subscription image '
                          'models are shown (image allowance, not wallet money).'
                    : 'Subscription mode is off — paid image models can charge '
                          'wallet money. Turn on Use subscription API in Settings '
                          'to hide them.',
                style: theme.textTheme.bodySmall,
              ),
              if (_creditsHint != null) ...[
                const SizedBox(height: 8),
                Text(
                  _creditsHint!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.tertiary,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              if (_loadingModels)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_models.isNotEmpty)
                DropdownButtonFormField<String>(
                  initialValue:
                      _selectedModelId != null &&
                          _models.any((m) => m.id == _selectedModelId)
                      ? _selectedModelId
                      : null,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: _subscriptionOnly
                        ? 'Subscription image model'
                        : 'Image model',
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [
                    for (final model in _models)
                      DropdownMenuItem(
                        value: model.id,
                        child: Text(
                          _modelLabel(model),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: _generating
                      ? null
                      : (id) => setState(() => _selectedModelId = id),
                )
              else
                Text(
                  _modelsError ??
                      (_subscriptionOnly
                          ? 'No subscription image models available.'
                          : 'No image models available. Check Settings → API & connection.'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              const SizedBox(height: 12),
              TextField(
                controller: widget.promptController,
                minLines: 4,
                maxLines: 8,
                enabled: !_generating,
                decoration: const InputDecoration(
                  labelText: 'Image prompt',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 12),
              if (_preview != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: Image.memory(_preview!.bytes, fit: BoxFit.cover),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _generating
                          ? null
                          : () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: _generating ? null : _generate,
                      child: _generating
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(_preview == null ? 'Generate' : 'Regenerate'),
                    ),
                  ),
                ],
              ),
              if (_preview != null) ...[
                const SizedBox(height: 8),
                FilledButton.tonal(
                  onPressed: _generating ? null : _usePreview,
                  child: const Text('Use as avatar'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
