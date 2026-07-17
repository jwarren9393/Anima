import 'package:flutter/material.dart';

import '../models/anima_presets.dart';
import '../services/settings_service.dart';
import '../widgets/preset_picker.dart';
import 'settings_ui.dart';

/// Core + penalty generation parameters, context size, and auto-summarize.
class SamplingSettingsScreen extends StatefulWidget {
  const SamplingSettingsScreen({
    super.key,
    required this.settingsService,
  });

  final SettingsService settingsService;

  @override
  State<SamplingSettingsScreen> createState() => _SamplingSettingsScreenState();
}

class _SamplingSettingsScreenState extends State<SamplingSettingsScreen> {
  final _temperatureController = TextEditingController();
  final _topPController = TextEditingController();
  final _maxTokensController = TextEditingController();
  final _frequencyPenaltyController = TextEditingController();
  final _presencePenaltyController = TextEditingController();
  final _repetitionPenaltyController = TextEditingController();
  final _historyTokensController = TextEditingController();
  final _summarizeEveryController = TextEditingController();
  final _keepRecentController = TextEditingController();
  bool _autoSummarize = false;
  String? _activePresetName;
  String? _activeContextPresetName;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await widget.settingsService.getSampling();
    final c = await widget.settingsService.getContextSettings();
    if (!mounted) return;
    setState(() {
      _applySettingsToFields(s);
      _applyContextToFields(c);
      _loading = false;
    });
  }

  void _applySettingsToFields(SamplingSettings s) {
    _temperatureController.text = s.temperature.toString();
    _topPController.text = s.topP.toString();
    _maxTokensController.text = s.maxTokens == null ? '' : '${s.maxTokens}';
    _frequencyPenaltyController.text = s.frequencyPenalty.toString();
    _presencePenaltyController.text = s.presencePenalty.toString();
    _repetitionPenaltyController.text =
        s.repetitionPenalty == null ? '' : s.repetitionPenalty.toString();
  }

  void _applyContextToFields(ContextSettings c) {
    _historyTokensController.text = '${c.historyTokenBudget}';
    _summarizeEveryController.text = '${c.summarizeEveryMessages}';
    _keepRecentController.text = '${c.summarizeKeepRecent}';
    _autoSummarize = c.autoSummarize;
  }

  Future<void> _pickPreset() async {
    final preset = await pickSamplingPreset(context: context);
    if (preset == null || !mounted) return;
    setState(() {
      _applySettingsToFields(preset.settings);
      _activePresetName = preset.name;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Loaded “${preset.name}”. Tap Save to keep it.'),
      ),
    );
  }

  Future<void> _pickContextPreset() async {
    final preset = await pickContextPreset(context: context);
    if (preset == null || !mounted) return;
    setState(() {
      _historyTokensController.text = '${preset.historyTokenBudget}';
      _activeContextPresetName = preset.name;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Context set to “${preset.name}”. Tap Save to keep it.'),
      ),
    );
  }

  Future<void> _save() async {
    final temperature =
        double.tryParse(_temperatureController.text.trim()) ??
            SamplingSettings.defaultTemperature;
    final topP = double.tryParse(_topPController.text.trim()) ??
        SamplingSettings.defaultTopP;
    final maxParsed =
        SettingsUi.parseOptionalPositiveInt(_maxTokensController.text);
    final maxRaw = _maxTokensController.text.trim();
    if (maxRaw.isNotEmpty && maxParsed == null) {
      _showError('Max tokens must be a positive number, or blank.');
      return;
    }

    final frequencyPenalty =
        double.tryParse(_frequencyPenaltyController.text.trim()) ??
            SamplingSettings.defaultPenalty;
    final presencePenalty =
        double.tryParse(_presencePenaltyController.text.trim()) ??
            SamplingSettings.defaultPenalty;

    final repetitionPenalty = SettingsUi.parseOptionalDouble(
      _repetitionPenaltyController.text,
      min: -2,
      max: 2,
    );
    if (_repetitionPenaltyController.text.trim().isNotEmpty &&
        repetitionPenalty == null) {
      _showError('Repetition penalty must be between -2 and 2, or blank.');
      return;
    }

    final historyTokens =
        int.tryParse(_historyTokensController.text.trim()) ??
            ContextSettings.defaultHistoryTokens;
    if (historyTokens < 512 || historyTokens > 32000) {
      _showError('Context tokens must be between 512 and 32000.');
      return;
    }
    final summarizeEvery =
        int.tryParse(_summarizeEveryController.text.trim()) ??
            ContextSettings.defaultSummarizeEvery;
    if (summarizeEvery < 5 || summarizeEvery > 100) {
      _showError('Summarize every must be between 5 and 100 messages.');
      return;
    }
    final keepRecent = int.tryParse(_keepRecentController.text.trim()) ??
        ContextSettings.defaultKeepRecent;
    if (keepRecent < 4 || keepRecent > 40) {
      _showError('Keep recent must be between 4 and 40 messages.');
      return;
    }

    setState(() => _saving = true);
    await widget.settingsService.saveSampling(
      SamplingSettings(
        temperature: temperature.clamp(0.0, 2.0),
        topP: topP.clamp(0.0, 1.0),
        maxTokens: maxParsed,
        frequencyPenalty: frequencyPenalty.clamp(-2.0, 2.0),
        presencePenalty: presencePenalty.clamp(-2.0, 2.0),
        repetitionPenalty: repetitionPenalty,
      ),
    );
    await widget.settingsService.saveContextSettings(
      ContextSettings(
        historyTokenBudget: historyTokens,
        autoSummarize: _autoSummarize,
        summarizeEveryMessages: summarizeEvery,
        summarizeKeepRecent: keepRecent,
      ),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Generation & context settings saved.')),
    );
    await _load();
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  void dispose() {
    _temperatureController.dispose();
    _topPController.dispose();
    _maxTokensController.dispose();
    _frequencyPenaltyController.dispose();
    _presencePenaltyController.dispose();
    _repetitionPenaltyController.dispose();
    _historyTokensController.dispose();
    _summarizeEveryController.dispose();
    _keepRecentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Generation parameters')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: SettingsUi.listPadding,
              children: [
                SettingsUi.sectionHint(
                  context,
                  'These knobs shape how NanoGPT writes in every chat. '
                  'Start with a preset, then tweak one number at a time. '
                  'Context size and summarization are global too — they '
                  'apply to all chats.',
                ),
                const SizedBox(height: 12),
                PresetButton(
                  label: 'Load a generation preset',
                  onPressed: _pickPreset,
                ),
                if (_activePresetName != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Last loaded: $_activePresetName (save to keep)',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                const SizedBox(height: 12),
                _section(context, 'Core'),
                _detailedField(
                  controller: _temperatureController,
                  label: 'Temperature (0–2)',
                  help: AnimaPresets.temperatureHelp,
                  decimal: true,
                ),
                _detailedField(
                  controller: _topPController,
                  label: 'Top P (0–1)',
                  help: AnimaPresets.topPHelp,
                  decimal: true,
                ),
                _detailedField(
                  controller: _maxTokensController,
                  label: 'Max tokens (optional)',
                  help: AnimaPresets.maxTokensHelp,
                  decimal: false,
                ),
                const SizedBox(height: 16),
                _section(context, 'Penalties'),
                _detailedField(
                  controller: _frequencyPenaltyController,
                  label: 'Frequency penalty (-2–2)',
                  help: AnimaPresets.frequencyPenaltyHelp,
                  decimal: true,
                ),
                _detailedField(
                  controller: _presencePenaltyController,
                  label: 'Presence penalty (-2–2)',
                  help: AnimaPresets.presencePenaltyHelp,
                  decimal: true,
                ),
                _detailedField(
                  controller: _repetitionPenaltyController,
                  label: 'Repetition penalty (optional)',
                  help: AnimaPresets.repetitionPenaltyHelp,
                  decimal: true,
                ),
                const SizedBox(height: 16),
                _section(context, 'Context size (tokens)'),
                Text(
                  AnimaPresets.contextMaxHistoryHelp,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                PresetButton(
                  label: 'Context size presets',
                  onPressed: _pickContextPreset,
                ),
                if (_activeContextPresetName != null)
                  Text(
                    'Last loaded: $_activeContextPresetName (save to keep)',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                const SizedBox(height: 8),
                _detailedField(
                  controller: _historyTokensController,
                  label: 'History token budget (512–32000)',
                  help:
                      'Exact token budget for recent chat history. Presets fill '
                      'this for you (2K / 4K / 8K / 16K).',
                  decimal: false,
                ),
                const SizedBox(height: 8),
                _section(context, 'Memory summarization'),
                Text(
                  AnimaPresets.autoSummarizeHelp,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Auto-summarize long chats'),
                  subtitle: const Text(
                    'Updates each chat’s Memory summary after enough new messages',
                  ),
                  value: _autoSummarize,
                  onChanged: (value) => setState(() => _autoSummarize = value),
                ),
                _detailedField(
                  controller: _summarizeEveryController,
                  label: 'Summarize every N messages (5–100)',
                  help: AnimaPresets.summarizeEveryHelp,
                  decimal: false,
                ),
                _detailedField(
                  controller: _keepRecentController,
                  label: 'Keep recent raw messages (4–40)',
                  help: AnimaPresets.summarizeKeepRecentHelp,
                  decimal: false,
                ),
                Text(
                  'In a chat: ⋮ → Memory summary to read/edit, or Summarize now '
                  'to run one update manually.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 24),
                SettingsUi.saveButton(
                  saving: _saving,
                  label: 'Save parameters',
                  onPressed: _saving ? null : _save,
                ),
                const SizedBox(height: 24),
              ],
            ),
    );
  }

  Widget _section(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SettingsUi.sectionTitle(context, title),
    );
  }

  Widget _detailedField({
    required TextEditingController controller,
    required String label,
    required String help,
    required bool decimal,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: controller,
            keyboardType: decimal
                ? const TextInputType.numberWithOptions(decimal: true)
                : TextInputType.number,
            inputFormatters: decimal
                ? SettingsUi.decimalInput()
                : SettingsUi.positiveIntInput(),
            decoration: SettingsUi.fieldDecoration(label: label),
          ),
          const SizedBox(height: 6),
          Text(help, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}
