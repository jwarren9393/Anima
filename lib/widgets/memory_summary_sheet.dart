import 'package:flutter/material.dart';

import '../models/memory_summary.dart';

/// Edit Scene + Ledger memory. Returns the encoded text, `''` to clear, or
/// `null` if cancelled.
Future<String?> showMemorySummarySheet({
  required BuildContext context,
  required String initialText,
  required int memoryCoveredCount,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _MemorySummarySheet(
      initialText: initialText,
      memoryCoveredCount: memoryCoveredCount,
    ),
  );
}

class _LedgerRow {
  _LedgerRow({required this.pinned, required String text})
      : controller = TextEditingController(text: text);

  bool pinned;
  final TextEditingController controller;

  void dispose() => controller.dispose();
}

class _MemorySummarySheet extends StatefulWidget {
  const _MemorySummarySheet({
    required this.initialText,
    required this.memoryCoveredCount,
  });

  final String initialText;
  final int memoryCoveredCount;

  @override
  State<_MemorySummarySheet> createState() => _MemorySummarySheetState();
}

class _MemorySummarySheetState extends State<_MemorySummarySheet> {
  late final TextEditingController _sceneController;
  late final List<_LedgerRow> _ledger;

  @override
  void initState() {
    super.initState();
    final parsed = MemorySummaryDocument.parse(widget.initialText);
    _sceneController = TextEditingController(
      text: [
        for (final fact in parsed.scene) fact.encodeLine(),
      ].join('\n'),
    );
    _ledger = [
      for (final fact in parsed.ledger)
        _LedgerRow(pinned: fact.pinned, text: fact.text),
    ];
    if (_ledger.isEmpty) {
      _ledger.add(_LedgerRow(pinned: false, text: ''));
    }
  }

  @override
  void dispose() {
    _sceneController.dispose();
    for (final row in _ledger) {
      row.dispose();
    }
    super.dispose();
  }

  void _addFact() {
    setState(() => _ledger.add(_LedgerRow(pinned: false, text: '')));
  }

  void _removeFact(int index) {
    setState(() {
      _ledger.removeAt(index).dispose();
      if (_ledger.isEmpty) {
        _ledger.add(_LedgerRow(pinned: false, text: ''));
      }
    });
  }

  String _encode() {
    final scene = MemorySummaryDocument.parse(
      '## Scene\n${_sceneController.text}',
    ).scene;
    final ledger = <MemoryFact>[];
    for (final row in _ledger) {
      final text = row.controller.text.trim();
      if (text.isEmpty) continue;
      final parsed = MemorySummaryDocument.parse(
        row.pinned ? '- ${MemoryFact.pinToken} $text' : '- $text',
      );
      if (parsed.ledger.isNotEmpty) {
        ledger.add(parsed.ledger.first.copyWith(pinned: row.pinned));
      } else if (parsed.scene.isNotEmpty) {
        ledger.add(
          parsed.scene.first.copyWith(pinned: row.pinned),
        );
      } else {
        ledger.add(MemoryFact(text: text, pinned: row.pinned));
      }
    }
    return MemorySummaryDocument(scene: scene, ledger: ledger).encode();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final height = MediaQuery.sizeOf(context).height * 0.92;
    final target = MemorySummaryDocument.ledgerBulletTarget(
      widget.memoryCoveredCount,
    );

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SizedBox(
          height: height,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                child: Text(
                  'Memory summary',
                  style: theme.textTheme.titleLarge,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  'Scene is where you are right now (replaced each summarize). '
                  'Ledger keeps durable plot — promises, secrets, threads. '
                  'Pin a ledger line so Summarize never drops it. '
                  'Covered messages: ${widget.memoryCoveredCount} · '
                  'ledger room ~$target facts.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  children: [
                    Text('Scene', style: theme.textTheme.titleSmall),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _sceneController,
                      minLines: 3,
                      maxLines: 8,
                      keyboardType: TextInputType.multiline,
                      decoration: const InputDecoration(
                        hintText:
                            '- Location: …\n- Present: …',
                        border: OutlineInputBorder(),
                        alignLabelWithHint: true,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Text('Ledger', style: theme.textTheme.titleSmall),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: _addFact,
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Add fact'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    for (var i = 0; i < _ledger.length; i++)
                      _buildLedgerRow(theme, i),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Row(
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, ''),
                      child: const Text('Clear'),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, _encode()),
                      child: const Text('Save'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLedgerRow(ThemeData theme, int index) {
    final row = _ledger[index];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconButton(
            tooltip: row.pinned
                ? 'Unpin — summarize may drop this if resolved'
                : 'Pin — summarize will never drop this',
            onPressed: () => setState(() => row.pinned = !row.pinned),
            icon: Icon(
              row.pinned ? Icons.push_pin : Icons.push_pin_outlined,
              color: row.pinned ? theme.colorScheme.tertiary : null,
            ),
          ),
          Expanded(
            child: TextField(
              controller: row.controller,
              minLines: 1,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: 'Thread: …  or  Secret (known by Mira): …',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Remove fact',
            onPressed: () => _removeFact(index),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}
