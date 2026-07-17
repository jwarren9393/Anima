import 'package:flutter/material.dart';

import '../services/character_service.dart';
import '../services/nanogpt_service.dart';
import '../services/settings_service.dart';
import '../services/world_info_service.dart';
import 'characters_screen.dart';
import 'lorebooks_screen.dart';
import 'settings_ui.dart';

/// App-wide World Info: global lorebooks + scan settings + character books.
class LoreSettingsScreen extends StatefulWidget {
  const LoreSettingsScreen({
    super.key,
    required this.settingsService,
    required this.characterService,
    required this.worldInfoService,
    required this.nanoGptService,
  });

  final SettingsService settingsService;
  final CharacterService characterService;
  final WorldInfoService worldInfoService;
  final NanoGptService nanoGptService;

  @override
  State<LoreSettingsScreen> createState() => _LoreSettingsScreenState();
}

class _LoreSettingsScreenState extends State<LoreSettingsScreen> {
  final _scanDepthController = TextEditingController();
  final _tokenBudgetController = TextEditingController();
  bool _recursiveScanning = false;
  bool _loading = true;
  bool _saving = false;
  int _globalBookCount = 0;
  int _globalEnabledCount = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final lore = await widget.settingsService.getLoreSettings();
    final books = await widget.worldInfoService.loadBooks();
    if (!mounted) return;
    setState(() {
      _scanDepthController.text = '${lore.scanDepth}';
      _tokenBudgetController.text = '${lore.tokenBudget}';
      _recursiveScanning = lore.recursiveScanning;
      _globalBookCount = books.length;
      _globalEnabledCount = books.where((b) => b.enabled).length;
      _loading = false;
    });
  }

  Future<void> _save() async {
    final depth = int.tryParse(_scanDepthController.text.trim());
    final budget = int.tryParse(_tokenBudgetController.text.trim());
    if (depth == null || depth < 1 || depth > 50) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Scan depth must be between 1 and 50.')),
      );
      return;
    }
    if (budget == null || budget < 10 || budget > 4000) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Token budget must be between 10 and 4000.'),
        ),
      );
      return;
    }

    setState(() => _saving = true);
    await widget.settingsService.saveLoreSettings(
      LoreSettings(
        scanDepth: depth,
        tokenBudget: budget,
        recursiveScanning: _recursiveScanning,
      ),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('World Info settings saved.')),
    );
  }

  Future<void> _openGlobalBooks() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LorebooksScreen(
          worldInfoService: widget.worldInfoService,
          settingsService: widget.settingsService,
          nanoGptService: widget.nanoGptService,
        ),
      ),
    );
    await _load();
  }

  Future<void> _openCharacters() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CharactersScreen(
          characterService: widget.characterService,
          settingsService: widget.settingsService,
          nanoGptService: widget.nanoGptService,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _scanDepthController.dispose();
    _tokenBudgetController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('World Info & lore')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: SettingsUi.listPadding,
              children: [
                SettingsUi.sectionHint(
                  context,
                  'Like SillyTavern: create or import global lorebooks that '
                  'apply across chats. Each character can still have their own '
                  'embedded book. Keyword entries only inject when they match '
                  'recent messages (or are Always on).',
                ),
                const SizedBox(height: 24),
                SettingsUi.sectionTitle(context, 'Global lorebooks'),
                const SizedBox(height: 8),
                SettingsUi.sectionHint(
                  context,
                  _globalBookCount == 0
                      ? 'No global books yet — create one or import a '
                          'SillyTavern World Info JSON.'
                      : '$_globalEnabledCount of $_globalBookCount enabled. '
                          'Enabled books apply to chats by default; group setup '
                          'can pick a subset.',
                ),
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  onPressed: _openGlobalBooks,
                  icon: const Icon(Icons.public),
                  label: Text(
                    _globalBookCount == 0
                        ? 'Manage global lorebooks'
                        : 'Manage global lorebooks ($_globalBookCount)',
                  ),
                ),
                const SizedBox(height: 32),
                SettingsUi.sectionTitle(context, 'Scan behavior'),
                const SizedBox(height: 16),
                TextField(
                  controller: _scanDepthController,
                  keyboardType: TextInputType.number,
                  inputFormatters: SettingsUi.positiveIntInput(),
                  decoration: SettingsUi.fieldDecoration(
                    label: 'Scan depth (messages)',
                    helperText:
                        'How many recent messages to check for keywords. Default 4.',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _tokenBudgetController,
                  keyboardType: TextInputType.number,
                  inputFormatters: SettingsUi.positiveIntInput(),
                  decoration: SettingsUi.fieldDecoration(
                    label: 'Token budget',
                    helperText:
                        'Max lore size per turn (approximate). Default 512.',
                  ),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Recursive scanning'),
                  subtitle: const Text(
                    'SillyTavern option — not active in Anima yet; saved for later.',
                  ),
                  value: _recursiveScanning,
                  onChanged: (v) => setState(() => _recursiveScanning = v),
                ),
                const SizedBox(height: 16),
                SettingsUi.saveButton(
                  saving: _saving,
                  label: 'Save World Info settings',
                  onPressed: _saving ? null : _save,
                ),
                const SizedBox(height: 32),
                SettingsUi.sectionTitle(context, 'Per-character lorebooks'),
                const SizedBox(height: 8),
                SettingsUi.sectionHint(
                  context,
                  'Open a character → World Info / lorebook to edit the book '
                  'embedded on that card (imported cards often already have one).',
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _openCharacters,
                  icon: const Icon(Icons.menu_book),
                  label: const Text('Edit character lorebooks'),
                ),
              ],
            ),
    );
  }
}
