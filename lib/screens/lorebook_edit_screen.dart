import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/lorebook.dart';
import '../services/lore_collaborator.dart';
import '../services/nanogpt_service.dart';
import '../services/settings_service.dart';
import '../widgets/keyboard_inset.dart';

/// Edit a character's or global World Info / lorebook (SillyTavern-style).
class LorebookEditScreen extends StatefulWidget {
  const LorebookEditScreen({
    super.key,
    required this.initial,
    required this.settingsService,
    required this.nanoGptService,
    this.characterName = '',
  });

  final Lorebook initial;
  final SettingsService settingsService;
  final NanoGptService nanoGptService;
  final String characterName;

  @override
  State<LorebookEditScreen> createState() => _LorebookEditScreenState();
}

class _LorebookEditScreenState extends State<LorebookEditScreen> {
  late TextEditingController _name;
  late TextEditingController _description;
  late TextEditingController _scanDepth;
  late TextEditingController _tokenBudget;
  late List<LorebookEntry> _entries;
  late Map<String, dynamic> _extensions;

  @override
  void initState() {
    super.initState();
    final book = widget.initial;
    _name = TextEditingController(text: book.name);
    _description = TextEditingController(text: book.description);
    _scanDepth = TextEditingController(text: '${book.scanDepth}');
    _tokenBudget = TextEditingController(text: '${book.tokenBudget}');
    _entries = List<LorebookEntry>.from(book.entries);
    _extensions = Map<String, dynamic>.from(book.extensions);
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _scanDepth.dispose();
    _tokenBudget.dispose();
    super.dispose();
  }

  Lorebook _snapshot() {
    return Lorebook(
      name: _name.text.trim(),
      description: _description.text.trim(),
      scanDepth: int.tryParse(_scanDepth.text.trim()) ?? 4,
      tokenBudget: int.tryParse(_tokenBudget.text.trim()) ?? 512,
      recursiveScanning: widget.initial.recursiveScanning,
      entries: List<LorebookEntry>.from(_entries),
      extensions: _extensions,
    );
  }

  void _save() {
    Navigator.of(context).pop(_snapshot());
  }

  Future<void> _editEntry(int? index) async {
    final existing = index == null ? null : _entries[index];
    final siblings = <LoreSiblingSummary>[];
    for (var i = 0; i < _entries.length; i++) {
      if (index != null && i == index) continue;
      siblings.add(LoreSiblingSummary.fromEntry(_entries[i]));
    }

    final result = await Navigator.of(context).push<LorebookEntry>(
      MaterialPageRoute(
        builder: (_) => _LorebookEntryEditScreen(
          existing: existing,
          settingsService: widget.settingsService,
          nanoGptService: widget.nanoGptService,
          bookName: _name.text.trim(),
          bookDescription: _description.text.trim(),
          characterName: widget.characterName,
          siblingEntries: siblings,
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      if (index == null) {
        final nextId = _nextEntryId();
        _entries.add(result.copyWith(id: result.id ?? nextId));
      } else {
        _entries[index] = result;
      }
    });
  }

  int _nextEntryId() {
    var max = 0;
    for (final e in _entries) {
      final id = e.id ?? 0;
      if (id > max) max = id;
    }
    return max + 1;
  }

  Future<void> _confirmDelete(int index) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete lore entry?'),
        content: Text(
          'Remove “${_entries[index].displayLabel}”? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      setState(() => _entries.removeAt(index));
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.characterName.trim().isEmpty
        ? 'Lorebook'
        : 'Lorebook · ${widget.characterName}';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('Save'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editEntry(null),
        icon: const Icon(Icons.add),
        label: const Text('Add entry'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
        children: [
          Text(
            'World Info only sends lore when a keyword shows up in recent chat '
            '(or when an entry is set to Always on). That keeps prompts small on a phone.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Open an entry (or Add entry) and tap the wand on Label, Keywords, '
            'or Lore content to append AI text — same as the character editor.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            decoration: const InputDecoration(
              labelText: 'Book name',
              hintText: 'e.g. Kingdom lore',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _description,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Book notes (optional)',
              hintText: 'For you — not sent to the AI',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _scanDepth,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Scan depth',
                    helperText: 'Recent messages to scan',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _tokenBudget,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Token budget',
                    helperText: 'Max lore size (~chars÷4)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            'Entries (${_entries.length})',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (_entries.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'No lore entries yet. Tap “Add entry” — for example, key '
                '“sword” and content describing the legendary blade.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            )
          else
            ...List.generate(_entries.length, (index) {
              final entry = _entries[index];
              final subtitleParts = <String>[
                if (entry.constant)
                  'Always on'
                else if (entry.keys.isNotEmpty)
                  'Keys: ${entry.keys.join(', ')}'
                else
                  'No keys',
                'Order ${entry.insertionOrder}',
              ];
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  title: Text(entry.displayLabel),
                  subtitle: Text(
                    subtitleParts.join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Switch(
                        value: entry.enabled,
                        onChanged: (on) {
                          setState(() {
                            _entries[index] = entry.copyWith(enabled: on);
                          });
                        },
                      ),
                      IconButton(
                        tooltip: 'Delete',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _confirmDelete(index),
                      ),
                    ],
                  ),
                  onTap: () => _editEntry(index),
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _LorebookEntryEditScreen extends StatefulWidget {
  const _LorebookEntryEditScreen({
    this.existing,
    required this.settingsService,
    required this.nanoGptService,
    this.bookName = '',
    this.bookDescription = '',
    this.characterName = '',
    this.siblingEntries = const [],
  });

  final LorebookEntry? existing;
  final SettingsService settingsService;
  final NanoGptService nanoGptService;
  final String bookName;
  final String bookDescription;
  final String characterName;
  final List<LoreSiblingSummary> siblingEntries;

  @override
  State<_LorebookEntryEditScreen> createState() =>
      _LorebookEntryEditScreenState();
}

class _LorebookEntryEditScreenState extends State<_LorebookEntryEditScreen> {
  static const _collaborator = LoreCollaborator();

  late TextEditingController _name;
  late TextEditingController _keys;
  late TextEditingController _secondaryKeys;
  late TextEditingController _content;
  late TextEditingController _order;
  late TextEditingController _priority;
  late TextEditingController _comment;
  late bool _enabled;
  late bool _constant;
  late bool _selective;
  late bool _caseSensitive;
  late LorebookPosition _position;
  late Map<String, dynamic> _extensions;
  int? _id;
  LoreCollaboratorField? _wandBusy;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _id = e?.id;
    _name = TextEditingController(text: e?.name ?? '');
    _keys = TextEditingController(text: (e?.keys ?? const []).join(', '));
    _secondaryKeys =
        TextEditingController(text: (e?.secondaryKeys ?? const []).join(', '));
    _content = TextEditingController(text: e?.content ?? '');
    _order = TextEditingController(text: '${e?.insertionOrder ?? 100}');
    _priority = TextEditingController(text: '${e?.priority ?? 10}');
    _comment = TextEditingController(text: e?.comment ?? '');
    _enabled = e?.enabled ?? true;
    _constant = e?.constant ?? false;
    _selective = e?.selective ?? false;
    _caseSensitive = e?.caseSensitive ?? false;
    _position = e?.position ?? LorebookPosition.beforeChar;
    _extensions = Map<String, dynamic>.from(e?.extensions ?? const {});
  }

  @override
  void dispose() {
    _name.dispose();
    _keys.dispose();
    _secondaryKeys.dispose();
    _content.dispose();
    _order.dispose();
    _priority.dispose();
    _comment.dispose();
    super.dispose();
  }

  List<String> _csv(String raw) => raw
      .split(RegExp(r'[,;\n]'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  LoreEntryDraftContext _draftContext() {
    return LoreEntryDraftContext(
      bookName: widget.bookName,
      bookDescription: widget.bookDescription,
      characterName: widget.characterName,
      name: _name.text,
      keys: _keys.text,
      secondaryKeys: _secondaryKeys.text,
      content: _content.text,
      comment: _comment.text,
      constant: _constant,
      selective: _selective,
      siblingEntries: widget.siblingEntries,
    );
  }

  TextEditingController _controllerFor(LoreCollaboratorField field) {
    switch (field) {
      case LoreCollaboratorField.name:
        return _name;
      case LoreCollaboratorField.keys:
        return _keys;
      case LoreCollaboratorField.secondaryKeys:
        return _secondaryKeys;
      case LoreCollaboratorField.content:
        return _content;
    }
  }

  Future<void> _runWand(LoreCollaboratorField field) async {
    if (_wandBusy != null) return;

    setState(() => _wandBusy = field);
    try {
      final collaborator =
          await widget.settingsService.getCollaboratorSettings();
      final messages = _collaborator.buildMessages(
        field: field,
        draft: _draftContext(),
        guidanceNote: collaborator.guidanceNote,
      );
      final model = await widget.settingsService.getModel();
      final sampling = await widget.settingsService.getSampling();
      final baseUrl = await widget.settingsService.getApiBaseUrl();
      final generated = await widget.nanoGptService.complete(
        model: model,
        messages: messages,
        baseUrl: baseUrl,
        sampling: sampling,
      );
      if (!mounted) return;
      final controller = _controllerFor(field);
      controller.text = _collaborator.appendGenerated(
        controller.text,
        generated,
        field: field,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Appended AI text to ${_collaborator.fieldLabel(field)}.',
          ),
        ),
      );
    } on NanoGptCancelledException {
      // One-shot complete; ignore cancel edge cases.
    } on NanoGptException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Wand failed: $error')),
      );
    } finally {
      if (mounted) setState(() => _wandBusy = null);
    }
  }

  Widget? _wandSuffix(LoreCollaboratorField field) {
    final wandBusy = _wandBusy == field;
    final anyWandBusy = _wandBusy != null;
    return IconButton(
      tooltip: 'AI wand — expand this field',
      onPressed: anyWandBusy ? null : () => _runWand(field),
      icon: wandBusy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.auto_awesome),
    );
  }

  void _save() {
    if (_wandBusy != null) return;
    final content = _content.text.trim();
    if (content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Write some lore content first.')),
      );
      return;
    }
    if (!_constant && _csv(_keys.text).isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add at least one keyword, or turn on Always on.'),
        ),
      );
      return;
    }

    final entry = LorebookEntry(
      id: _id,
      name: _name.text.trim(),
      keys: _csv(_keys.text),
      secondaryKeys: _csv(_secondaryKeys.text),
      content: content,
      enabled: _enabled,
      insertionOrder: int.tryParse(_order.text.trim()) ?? 100,
      caseSensitive: _caseSensitive,
      selective: _selective,
      constant: _constant,
      position: _position,
      priority: int.tryParse(_priority.text.trim()) ?? 10,
      comment: _comment.text.trim(),
      extensions: _extensions,
    );
    Navigator.of(context).pop(entry);
  }

  @override
  Widget build(BuildContext context) {
    final anyWandBusy = _wandBusy != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? 'New lore entry' : 'Edit lore entry'),
        actions: [
          TextButton(
            onPressed: anyWandBusy ? null : _save,
            child: const Text('Done'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Tap the wand on Label, Keywords, or Lore content to append AI text '
            '(uses your NanoGPT model + Settings → AI collaborator).',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Enabled'),
            subtitle: const Text('Off entries are ignored during chat.'),
            value: _enabled,
            onChanged: (v) => setState(() => _enabled = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Always on'),
            subtitle: const Text(
              'Include every turn (still limited by the token budget).',
            ),
            value: _constant,
            onChanged: (v) => setState(() => _constant = v),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _name,
            scrollPadding: kAnimaKeyboardScrollPadding,
            decoration: InputDecoration(
              labelText: 'Label (optional)',
              hintText: 'Short name for this entry',
              border: const OutlineInputBorder(),
              suffixIcon: _wandSuffix(LoreCollaboratorField.name),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _keys,
            scrollPadding: kAnimaKeyboardScrollPadding,
            decoration: InputDecoration(
              labelText: 'Keywords',
              hintText: 'sword, blade, Excalibur',
              helperText: _constant
                  ? 'Optional when Always on is checked.'
                  : 'Comma-separated. Any one match can fire this entry.',
              border: const OutlineInputBorder(),
              suffixIcon: _wandSuffix(LoreCollaboratorField.keys),
            ),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Selective (two-key)'),
            subtitle: const Text(
              'Require a primary keyword AND a secondary keyword.',
            ),
            value: _selective,
            onChanged: (v) => setState(() => _selective = v),
          ),
          if (_selective) ...[
            TextField(
              controller: _secondaryKeys,
              scrollPadding: kAnimaKeyboardScrollPadding,
              decoration: InputDecoration(
                labelText: 'Secondary keywords',
                hintText: 'quest, legend',
                border: const OutlineInputBorder(),
                suffixIcon: _wandSuffix(LoreCollaboratorField.secondaryKeys),
              ),
            ),
            const SizedBox(height: 12),
          ],
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Case-sensitive keys'),
            value: _caseSensitive,
            onChanged: (v) => setState(() => _caseSensitive = v),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _content,
            minLines: 5,
            maxLines: 12,
            scrollPadding: kAnimaKeyboardScrollPadding,
            decoration: InputDecoration(
              labelText: 'Lore content',
              hintText: 'Facts injected into the AI prompt when this fires…',
              alignLabelWithHint: true,
              border: const OutlineInputBorder(),
              suffixIcon: _wandSuffix(LoreCollaboratorField.content),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Placement',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          SegmentedButton<LorebookPosition>(
            segments: const [
              ButtonSegment(
                value: LorebookPosition.beforeChar,
                label: Text('Before desc'),
              ),
              ButtonSegment(
                value: LorebookPosition.afterChar,
                label: Text('After desc'),
              ),
            ],
            selected: {_position},
            onSelectionChanged: (selected) {
              setState(() => _position = selected.first);
            },
          ),
          const SizedBox(height: 4),
          Text(
            'Before puts lore above the character description; after puts it below.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _order,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Insertion order',
                    helperText: 'Lower = earlier',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _priority,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Priority',
                    helperText: 'Lower drops first',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _comment,
            minLines: 2,
            maxLines: 4,
            scrollPadding: kAnimaKeyboardScrollPadding,
            decoration: const InputDecoration(
              labelText: 'Comment (optional)',
              hintText: 'Notes for you — not sent to the AI',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: anyWandBusy ? null : _save,
            child: const Text('Save entry'),
          ),
        ],
      ),
    );
  }
}
