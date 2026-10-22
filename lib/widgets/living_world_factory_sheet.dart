import 'package:flutter/material.dart';

import '../models/living_world.dart';
import '../models/world_workshop.dart';
import '../services/character_service.dart';
import '../services/living_world_factory_service.dart';
import '../services/living_world_service.dart';
import '../services/nanogpt_service.dart';
import '../services/persona_service.dart';
import '../services/settings_service.dart';
import '../services/world_workshop_service.dart';

/// How long one factory pass may wait on NanoGPT (5 sequential passes).
const _kFactoryPassTimeout = Duration(minutes: 5);

/// Collect a brainstorm pitch, run the multi-pass factory, save the notebook.
Future<LivingWorld?> showLivingWorldFactorySheet({
  required BuildContext context,
  required LivingWorldService worldService,
  required NanoGptService nanoGptService,
  required SettingsService settingsService,
  CharacterService? characterService,
  PersonaService? personaService,
  WorldWorkshopService? workshopService,
}) {
  return showModalBottomSheet<LivingWorld>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _LivingWorldFactorySheet(
      worldService: worldService,
      nanoGptService: nanoGptService,
      settingsService: settingsService,
      characterService: characterService,
      personaService: personaService,
      workshopService: workshopService ?? WorldWorkshopService(),
    ),
  );
}

class _LivingWorldFactorySheet extends StatefulWidget {
  const _LivingWorldFactorySheet({
    required this.worldService,
    required this.nanoGptService,
    required this.settingsService,
    required this.workshopService,
    this.characterService,
    this.personaService,
  });

  final LivingWorldService worldService;
  final NanoGptService nanoGptService;
  final SettingsService settingsService;
  final WorldWorkshopService workshopService;
  final CharacterService? characterService;
  final PersonaService? personaService;

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
  String? _seedNote;

  @override
  void dispose() {
    _pitch.dispose();
    super.dispose();
  }

  String _shortHint(String name, String summary) {
    final n = name.trim().isEmpty ? 'Unnamed' : name.trim();
    final s = summary.trim();
    if (s.isEmpty) return n;
    return '$n — ${s.length > 160 ? '${s.substring(0, 160)}…' : s}';
  }

  Future<void> _seedFromWorkshop() async {
    if (_busy) return;
    List<WorldWorkshop> workshops;
    try {
      workshops = await widget.workshopService.loadWorkshops();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Could not load Creation Center workshops: $e');
      return;
    }
    if (!mounted) return;
    if (workshops.isEmpty) {
      setState(
        () => _error =
            'No Creation Center workshops yet — create one first, or type a pitch.',
      );
      return;
    }

    final picked = await showModalBottomSheet<WorldWorkshop>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: ListView(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Text(
                  'Seed from Creation Center',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  'One-way only — fills the factory pitch from the workshop '
                  'summary (and linked persona/cards). Does not turn Creation '
                  'Center into the living engine.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              for (final w in workshops)
                ListTile(
                  title: Text(w.title.trim().isEmpty ? 'Untitled' : w.title),
                  subtitle: Text(
                    w.worldSummary.trim().isEmpty
                        ? 'No world summary yet'
                        : w.worldSummary.trim(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => Navigator.pop(context, w),
                ),
            ],
          ),
        );
      },
    );
    if (picked == null || !mounted) return;

    final characterLines = <String>[];
    final characterService = widget.characterService;
    if (characterService != null && picked.linkedCharacterIds.isNotEmpty) {
      try {
        final all = await characterService.loadCharacters();
        final byId = {for (final c in all) c.id: c};
        for (final id in picked.linkedCharacterIds) {
          final c = byId[id];
          if (c == null) continue;
          characterLines.add(_shortHint(c.name, c.description));
        }
      } catch (_) {}
    }

    var personaLine = '';
    final personaId = picked.linkedPersonaId?.trim() ?? '';
    final personaService = widget.personaService;
    if (personaService != null && personaId.isNotEmpty) {
      try {
        final personas = await personaService.loadPersonas();
        for (final p in personas) {
          if (p.id != personaId) continue;
          personaLine = _shortHint(p.name, p.description);
          break;
        }
      } catch (_) {}
    }

    final pitch = LivingWorldFactoryRequest.brainstormFromWorkshop(
      title: picked.title,
      worldSummary: picked.worldSummary,
      characterLines: characterLines,
      personaLine: personaLine,
    );
    if (!mounted) return;
    if (pitch.isEmpty) {
      setState(
        () => _error =
            'That workshop has no summary or linked cards to seed from.',
      );
      return;
    }
    setState(() {
      _pitch.text = pitch;
      _seedNote =
          'Seeded from “${picked.title.trim().isEmpty ? 'Untitled' : picked.title.trim()}”';
      _error = null;
    });
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
      _status = 'Starting factory (5 AI steps — stay on this screen)…';
    });

    try {
      final build = await widget.settingsService.getCharacterBuildSettings();
      final mainModel = await widget.settingsService.getModel();
      final model = build.resolvedModel(mainModel);
      // Always allow a large reply — character-build maxTokens (often 2K)
      // truncates mid-JSON when drafting many people in one shot.
      final sampling = build.toSampling().copyWith(maxTokens: 8192);

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
            timeout: _kFactoryPassTimeout,
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
                'Runs 5 AI steps in a row (outline → places → people → '
                'relationships → events). Each step can take a few minutes — '
                'keep this sheet open until it finishes.',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _busy ? null : _seedFromWorkshop,
                icon: const Icon(Icons.auto_awesome_outlined),
                label: const Text('Seed from Creation Center…'),
              ),
              if (_seedNote != null) ...[
                const SizedBox(height: 6),
                Text(
                  _seedNote!,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: scheme.primary),
                ),
              ],
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
                onChanged: _busy ? null : (v) => setState(() => _places = v),
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
                onChanged: _busy ? null : (v) => setState(() => _people = v),
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
                Text(_error!, style: TextStyle(color: scheme.error)),
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
