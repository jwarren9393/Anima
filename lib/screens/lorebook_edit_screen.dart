import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/lorebook.dart';
import '../services/ai_field_changes.dart';
import '../services/lore_collaborator.dart';
import '../services/lorebook_token_service.dart';
import '../services/nanogpt_service.dart';
import '../services/settings_service.dart';
import '../widgets/character_token_badge.dart';
import '../services/world_workshop_builder.dart';
import '../widgets/ai_field_changes_sheet.dart';
import '../widgets/keyboard_inset.dart';
import '../widgets/minimal_chip_button.dart';

enum _LoreEntryFilter { all, on, off }

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
  static const _collaborator = LoreCollaborator();
  static const _tokenService = LorebookTokenService();
  final _workshopBuilder = WorldWorkshopBuilder();

  late TextEditingController _name;
  late TextEditingController _description;
  late TextEditingController _scanDepth;
  late TextEditingController _tokenBudget;
  late List<LorebookEntry> _entries;
  late Map<String, dynamic> _extensions;
  String _entrySearch = '';
  _LoreEntryFilter _entryFilter = _LoreEntryFilter.all;
  bool _consistencyBusy = false;

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

  bool _reportLooksTruncated(String report) {
    final text = report.trim();
    if (text.length < 80) return false;
    return !text.endsWith('.') &&
        !text.endsWith('!') &&
        !text.endsWith('?') &&
        !text.endsWith(':') &&
        !text.endsWith(')');
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

  void _applyLorebook(Lorebook book) {
    _name.text = book.name;
    _description.text = book.description;
    _scanDepth.text = '${book.scanDepth}';
    _tokenBudget.text = '${book.tokenBudget}';
    _entries = List<LorebookEntry>.from(book.entries);
    _extensions = Map<String, dynamic>.from(book.extensions);
  }

  Future<void> _runConsistencyCheck() async {
    if (_consistencyBusy) return;
    setState(() => _consistencyBusy = true);
    try {
      final collaborator =
          await widget.settingsService.getCollaboratorSettings();
      final messages = _collaborator.buildConsistencyCheckMessages(
        book: _snapshot(),
        characterName: widget.characterName,
        guidanceNote: collaborator.guidanceNote,
      );
      final model = await widget.settingsService.getModel();
      final sampling = WorldWorkshopBuilder.consistencyReportSampling(
        await widget.settingsService.getSampling(),
      );
      final baseUrl = await widget.settingsService.getApiBaseUrl();
      final report = await widget.nanoGptService.complete(
        model: model,
        messages: messages,
        baseUrl: baseUrl,
        sampling: sampling,
      );
      if (!mounted) return;
      final trimmedReport = report.trim();
      final truncated = _reportLooksTruncated(trimmedReport);
      final fixRequested = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Lorebook consistency'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (truncated)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        'This report may have been cut short. Try again or use '
                        'a higher max-tokens setting in Generation parameters.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.error,
                            ),
                      ),
                    ),
                  SelectableText(trimmedReport),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Close'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Fix inconsistencies'),
            ),
          ],
        ),
      );
      if (fixRequested == true && mounted) {
        await _runConsistencyFix(trimmedReport);
      }
    } on NanoGptCancelledException {
      // Ignore.
    } on NanoGptException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Consistency check failed: $error')),
      );
    } finally {
      if (mounted) setState(() => _consistencyBusy = false);
    }
  }

  Future<void> _runConsistencyFix(String consistencyReport) async {
    setState(() => _consistencyBusy = true);
    try {
      final before = _snapshot();
      final collaborator =
          await widget.settingsService.getCollaboratorSettings();
      final messages = _collaborator.buildConsistencyFixMessages(
        book: before,
        consistencyReport: consistencyReport,
        characterName: widget.characterName,
        guidanceNote: collaborator.guidanceNote,
      );
      final model = await widget.settingsService.getModel();
      final sampling = WorldWorkshopBuilder.consistencyFixSampling(
        await widget.settingsService.getSampling(),
      );
      final baseUrl = await widget.settingsService.getApiBaseUrl();

      Lorebook? fixed;
      for (var attempt = 0; attempt < 2; attempt++) {
        final raw = await widget.nanoGptService.complete(
          model: model,
          messages: messages,
          baseUrl: baseUrl,
          sampling: sampling,
        );
        try {
          fixed = _workshopBuilder.parseLorebookConsistencyFixJson(
            raw,
            original: before,
          );
          break;
        } on FormatException {
          if (attempt == 1) rethrow;
        }
      }
      if (fixed == null) {
        throw const FormatException(
          'Could not find lorebook JSON in the AI reply. Try again.',
        );
      }

      if (!mounted) return;
      final changes = compareLorebooks(before, fixed);
      if (changes.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No changes were suggested. Try editing manually.'),
          ),
        );
        return;
      }

      final apply = await showAiFieldChangesSheet(
        context: context,
        title: 'Review lorebook fixes',
        subtitle: 'Tap an item to see before and after. Apply updates this book.',
        changes: changes,
        applyLabel: 'Update lorebook',
      );
      if (apply != true || !mounted) return;

      setState(() => _applyLorebook(fixed!));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Updated ${changes.length} item${changes.length == 1 ? '' : 's'} from consistency fix.',
          ),
        ),
      );
    } on FormatException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } on NanoGptCancelledException {
      // Ignore.
    } on NanoGptException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Consistency fix failed: $error')),
      );
    } finally {
      if (mounted) setState(() => _consistencyBusy = false);
    }
  }

  bool _bookHasCompactableContent() {
    return _entries.any((e) => e.content.trim().isNotEmpty);
  }

  Future<void> _runCompactBook() async {
    if (_consistencyBusy) return;
    if (!_bookHasCompactableContent()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add lore entries with content first, then compact.'),
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Compact lorebook?'),
        content: const Text(
          'AI will shorten entry text while keeping important facts. '
          'You review every change before saving.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Compact'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _consistencyBusy = true);
    try {
      final before = _snapshot();
      final collaborator =
          await widget.settingsService.getCollaboratorSettings();
      final messages = _collaborator.buildBookCompactMessages(
        book: before,
        characterName: widget.characterName,
        guidanceNote: collaborator.guidanceNote,
      );
      final model = await widget.settingsService.getModel();
      final sampling = WorldWorkshopBuilder.consistencyFixSampling(
        await widget.settingsService.getSampling(),
      );
      final baseUrl = await widget.settingsService.getApiBaseUrl();

      Lorebook? compacted;
      for (var attempt = 0; attempt < 2; attempt++) {
        final raw = await widget.nanoGptService.complete(
          model: model,
          messages: messages,
          baseUrl: baseUrl,
          sampling: sampling,
        );
        try {
          compacted = _workshopBuilder.parseLorebookConsistencyFixJson(
            raw,
            original: before,
          );
          break;
        } on FormatException {
          if (attempt == 1) rethrow;
        }
      }
      if (compacted == null) {
        throw const FormatException(
          'Could not find lorebook JSON in the AI reply. Try again.',
        );
      }

      if (!mounted) return;
      final changes = compareLorebooks(before, compacted);
      if (changes.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No shorter version was suggested. Try editing manually.'),
          ),
        );
        return;
      }

      final apply = await showAiFieldChangesSheet(
        context: context,
        title: 'Review compacted lorebook',
        subtitle: 'Tap an item to compare before and after. Apply updates the book.',
        changes: changes,
        applyLabel: 'Update lorebook',
      );
      if (apply != true || !mounted) return;

      setState(() => _applyLorebook(compacted!));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Compacted ${changes.length} item${changes.length == 1 ? '' : 's'}.',
          ),
        ),
      );
    } on FormatException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } on NanoGptCancelledException {
      // Ignore.
    } on NanoGptException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Compact failed: $error')),
      );
    } finally {
      if (mounted) setState(() => _consistencyBusy = false);
    }
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

  List<LorebookEntry> get _visibleEntries {
    final q = _entrySearch.trim().toLowerCase();
    return [
      for (final e in _entries)
        if ((_entryFilter == _LoreEntryFilter.all ||
                (_entryFilter == _LoreEntryFilter.on && e.enabled) ||
                (_entryFilter == _LoreEntryFilter.off && !e.enabled)) &&
            (q.isEmpty ||
                e.displayLabel.toLowerCase().contains(q) ||
                e.keys.any((k) => k.toLowerCase().contains(q)) ||
                e.content.toLowerCase().contains(q)))
          e,
    ];
  }

  int _entryIndexOf(LorebookEntry entry) => _entries.indexOf(entry);

  @override
  Widget build(BuildContext context) {
    final title = widget.characterName.trim().isEmpty
        ? 'Lorebook'
        : 'Lorebook · ${widget.characterName}';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          PopupMenuButton<String>(
            enabled: !_consistencyBusy,
            onSelected: (value) {
              if (value == 'consistency') _runConsistencyCheck();
              if (value == 'compact') _runCompactBook();
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'consistency',
                enabled: !_consistencyBusy,
                child: Row(
                  children: [
                    if (_consistencyBusy)
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      const Icon(Icons.fact_check_outlined),
                    const SizedBox(width: 12),
                    const Text('Consistency check'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'compact',
                enabled: !_consistencyBusy,
                child: const Row(
                  children: [
                    Icon(Icons.compress_outlined),
                    SizedBox(width: 12),
                    Text('Compact lorebook…'),
                  ],
                ),
              ),
            ],
          ),
          TextButton(
            onPressed: _consistencyBusy ? null : _save,
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
            'Keyword lore injected when keys match recent chat.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _name,
            decoration: const InputDecoration(
              labelText: 'Book name',
              hintText: 'e.g. Kingdom lore',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          ExpansionTile(
            title: const Text('Book settings'),
            subtitle: Text(
              'Scan ${_scanDepth.text} · budget ${_tokenBudget.text} tokens',
            ),
            children: [
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
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
          const SizedBox(height: 16),
          Builder(
            builder: (context) {
              final breakdown = _tokenService.breakdown(_snapshot());
              return Row(
                children: [
                  Expanded(
                    child: Text(
                      'Entries (${_entries.length})',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  if (breakdown.totalTokens > 0) ...[
                    Text(
                      '${breakdown.enabledCount} on · ',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: Theme.of(context).colorScheme.outline,
                          ),
                    ),
                    CharacterTokenBadge(
                      tokens: breakdown.enabledTokens,
                      tooltip: lorebookTokenTooltip(breakdown),
                    ),
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: 8),
          TextField(
            decoration: const InputDecoration(
              hintText: 'Search entries…',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (v) => setState(() => _entrySearch = v),
          ),
          const SizedBox(height: 8),
          MinimalChipRow(
            children: [
              MinimalChipButton(
                label: 'All',
                selected: _entryFilter == _LoreEntryFilter.all,
                onPressed: () =>
                    setState(() => _entryFilter = _LoreEntryFilter.all),
              ),
              const SizedBox(width: 8),
              MinimalChipButton(
                label: 'On',
                selected: _entryFilter == _LoreEntryFilter.on,
                onPressed: () =>
                    setState(() => _entryFilter = _LoreEntryFilter.on),
              ),
              const SizedBox(width: 8),
              MinimalChipButton(
                label: 'Off',
                selected: _entryFilter == _LoreEntryFilter.off,
                onPressed: () =>
                    setState(() => _entryFilter = _LoreEntryFilter.off),
              ),
            ],
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
          else if (_visibleEntries.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'No entries match your search or filter.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            )
          else
            ..._visibleEntries.map((entry) {
              final index = _entryIndexOf(entry);
              final entryTokens = _tokenService.entryTokens(entry);
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
                  title: Row(
                    children: [
                      Expanded(child: Text(entry.displayLabel)),
                      if (entryTokens > 0) ...[
                        const SizedBox(width: 6),
                        CharacterTokenBadge(
                          tokens: entryTokens,
                          tooltip: lorebookEntryTokenTooltip(entry, entryTokens),
                        ),
                      ],
                    ],
                  ),
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
  final _workshopBuilder = WorldWorkshopBuilder();

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
  bool _suggestKeysBusy = false;
  bool _compactBusy = false;

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

  Future<void> _suggestKeywordsFromContent() async {
    if (_wandBusy != null || _suggestKeysBusy) return;
    final content = _content.text.trim();
    if (content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Write lore content first, then suggest keywords.'),
        ),
      );
      return;
    }

    setState(() => _suggestKeysBusy = true);
    try {
      final collaborator =
          await widget.settingsService.getCollaboratorSettings();
      final messages = _collaborator.buildKeywordSuggestMessages(
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
      _keys.text = _collaborator.mergeKeywords(_keys.text, generated);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Merged suggested keywords.')),
      );
    } on NanoGptCancelledException {
      // Ignore.
    } on NanoGptException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Suggest keywords failed: $error')),
      );
    } finally {
      if (mounted) setState(() => _suggestKeysBusy = false);
    }
  }

  LorebookEntry _entryFromDraft() {
    return LorebookEntry(
      id: _id,
      name: _name.text.trim(),
      keys: _csv(_keys.text),
      secondaryKeys: _csv(_secondaryKeys.text),
      content: _content.text.trim(),
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
  }

  void _applyEntryFields(LorebookEntry entry) {
    _name.text = entry.name;
    _keys.text = entry.keys.join(', ');
    _secondaryKeys.text = entry.secondaryKeys.join(', ');
    _content.text = entry.content;
    setState(() {});
  }

  Future<void> _runCompactEntry() async {
    if (_wandBusy != null || _compactBusy || _suggestKeysBusy) return;
    if (_content.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Write lore content first, then compact.'),
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Compact lore entry?'),
        content: const Text(
          'AI will shorten this entry while keeping important facts. '
          'You review changes before saving.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Compact'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _compactBusy = true);
    try {
      final before = _entryFromDraft();
      final collaborator =
          await widget.settingsService.getCollaboratorSettings();
      final messages = _collaborator.buildEntryCompactMessages(
        draft: _draftContext(),
        guidanceNote: collaborator.guidanceNote,
      );
      final model = await widget.settingsService.getModel();
      final sampling = WorldWorkshopBuilder.consistencyFixSampling(
        await widget.settingsService.getSampling(),
      );
      final baseUrl = await widget.settingsService.getApiBaseUrl();

      LorebookEntry? compacted;
      for (var attempt = 0; attempt < 2; attempt++) {
        final raw = await widget.nanoGptService.complete(
          model: model,
          messages: messages,
          baseUrl: baseUrl,
          sampling: sampling,
        );
        try {
          compacted = _workshopBuilder.parseLorebookEntryCompactJson(
            raw,
            original: before,
          );
          break;
        } on FormatException {
          if (attempt == 1) rethrow;
        }
      }
      if (compacted == null) {
        throw const FormatException(
          'Could not find lore entry JSON in the AI reply. Try again.',
        );
      }

      if (!mounted) return;
      final changes = compareLorebookEntry(before, compacted);
      if (changes.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No shorter version was suggested. Try editing manually.'),
          ),
        );
        return;
      }

      final apply = await showAiFieldChangesSheet(
        context: context,
        title: 'Review compacted entry',
        subtitle: 'Tap a field to compare before and after. Apply updates this entry.',
        changes: changes,
        applyLabel: 'Update entry',
      );
      if (apply != true || !mounted) return;

      _applyEntryFields(compacted);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Compacted ${changes.length} field${changes.length == 1 ? '' : 's'}.',
          ),
        ),
      );
    } on FormatException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } on NanoGptCancelledException {
      // Ignore.
    } on NanoGptException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Compact failed: $error')),
      );
    } finally {
      if (mounted) setState(() => _compactBusy = false);
    }
  }

  void _save() {
    if (_wandBusy != null || _compactBusy) return;
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
    final busy = anyWandBusy || _compactBusy;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? 'New lore entry' : 'Edit lore entry'),
        actions: [
          TextButton(
            onPressed: busy ? null : _save,
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
          OutlinedButton.icon(
            onPressed: (busy || _suggestKeysBusy) ? null : _runCompactEntry,
            icon: _compactBusy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.compress_outlined),
            label: const Text('Compact entry…'),
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
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: (_wandBusy != null || _suggestKeysBusy)
                  ? null
                  : _suggestKeywordsFromContent,
              icon: _suggestKeysBusy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.key_outlined),
              label: Text(
                _suggestKeysBusy
                    ? 'Suggesting…'
                    : 'Suggest keywords from content',
              ),
            ),
          ),
          const SizedBox(height: 12),
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
          ExpansionTile(
            title: const Text('Advanced'),
            children: [
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
              const SizedBox(height: 8),
            ],
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
