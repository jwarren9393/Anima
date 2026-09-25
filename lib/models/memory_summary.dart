/// Two-layer memory for long chats: a replaceable Scene plus a durable Ledger.
///
/// Stored as one `ChatSession.memorySummary` string so backups/sync stay simple.
class MemoryFact {
  const MemoryFact({required this.text, this.pinned = false});

  /// Body without a leading `- ` and without a `[pin]` marker.
  final String text;
  final bool pinned;

  static const pinToken = '[pin]';

  /// First word before `:` — `location`, `thread`, `secret`, …
  String get kind {
    final match = RegExp(r'^([A-Za-z]+)').firstMatch(text.trim());
    return (match?.group(1) ?? '').toLowerCase();
  }

  bool get isSceneKind => sceneKinds.contains(kind);

  static const sceneKinds = {'location', 'present', 'time'};

  String get identityKey {
    return text.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  MemoryFact copyWith({String? text, bool? pinned}) {
    return MemoryFact(
      text: text ?? this.text,
      pinned: pinned ?? this.pinned,
    );
  }

  String encodeLine() {
    final body = text.trim();
    if (body.isEmpty) return '';
    if (pinned) return '- $pinToken $body';
    return '- $body';
  }
}

/// Parsed Scene + Ledger with pin-safe merge after an AI rewrite.
class MemorySummaryDocument {
  const MemorySummaryDocument({
    this.scene = const [],
    this.ledger = const [],
  });

  final List<MemoryFact> scene;
  final List<MemoryFact> ledger;

  bool get isEmpty => scene.isEmpty && ledger.isEmpty;

  List<MemoryFact> get pinnedFacts => [
        for (final fact in [...scene, ...ledger])
          if (fact.pinned) fact,
      ];

  static int ledgerBulletTarget(int coveredMessageCount) {
    final covered = coveredMessageCount < 0 ? 0 : coveredMessageCount;
    return (35 + covered ~/ 8).clamp(35, 90);
  }

  static const sceneBulletMax = 10;

  factory MemorySummaryDocument.parse(String raw) {
    final text = _stripFences(raw);
    if (text.isEmpty) return const MemorySummaryDocument();

    final scene = <MemoryFact>[];
    final ledger = <MemoryFact>[];
    var section = _Section.none;
    var sawHeader = false;

    for (final rawLine in text.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      final header = _sectionOf(line);
      if (header != null) {
        sawHeader = true;
        section = header;
        continue;
      }

      final fact = _parseFact(line);
      if (fact == null) continue;

      if (sawHeader) {
        if (section == _Section.scene) {
          scene.add(fact.copyWith(pinned: false));
        } else {
          ledger.add(fact);
        }
        continue;
      }

      if (fact.isSceneKind && !fact.pinned) {
        scene.add(fact);
      } else {
        ledger.add(fact);
      }
    }

    return MemorySummaryDocument(scene: scene, ledger: ledger);
  }

  /// Encode for storage and prompt injection.
  String encode() {
    if (isEmpty) return '';
    final buffer = StringBuffer();
    if (scene.isNotEmpty) {
      buffer.writeln('## Scene');
      for (final fact in scene) {
        final line = fact.copyWith(pinned: false).encodeLine();
        if (line.isNotEmpty) buffer.writeln(line);
      }
      buffer.writeln();
    }
    if (ledger.isNotEmpty) {
      buffer.writeln('## Ledger');
      for (final fact in ledger) {
        final line = fact.encodeLine();
        if (line.isNotEmpty) buffer.writeln(line);
      }
    }
    return buffer.toString().trim();
  }

  /// Re-pin matching lines and restore any `[pin]` facts the model dropped.
  MemorySummaryDocument preservingPins(MemorySummaryDocument previous) {
    final previousPins = previous.pinnedFacts;
    if (previousPins.isEmpty) return this;

    final previousKeys = {
      for (final pin in previousPins) pin.identityKey,
    };

    List<MemoryFact> rePin(List<MemoryFact> facts) {
      return [
        for (final fact in facts)
          previousKeys.contains(fact.identityKey)
              ? fact.copyWith(pinned: true)
              : fact,
      ];
    }

    final nextScene = rePin(scene);
    final nextLedger = rePin(ledger);
    final keptKeys = {
      for (final fact in [...nextScene, ...nextLedger]) fact.identityKey,
    };

    final restored = <MemoryFact>[];
    for (final pin in previousPins) {
      if (pin.identityKey.isEmpty) continue;
      if (keptKeys.contains(pin.identityKey)) continue;
      restored.add(pin.copyWith(pinned: true));
      keptKeys.add(pin.identityKey);
    }

    return MemorySummaryDocument(
      scene: nextScene,
      ledger: [...restored, ...nextLedger],
    );
  }

  /// Apply a model rewrite without losing pins or wiping memory on empty output.
  static String finalize({
    required String existing,
    required String generated,
  }) {
    final previous = MemorySummaryDocument.parse(existing);
    final next = MemorySummaryDocument.parse(generated);
    if (next.isEmpty) return previous.encode();
    return next.preservingPins(previous).encode();
  }
}

enum _Section { none, scene, ledger }

String _stripFences(String raw) {
  var text = raw.trim();
  if (text.startsWith('```')) {
    text = text.replaceFirst(RegExp(r'^```[a-zA-Z]*\s*'), '');
    text = text.replaceFirst(RegExp(r'\s*```$'), '');
  }
  return text.trim();
}

_Section? _sectionOf(String line) {
  var body = line.trim();
  body = body.replaceFirst(RegExp(r'^#+\s*'), '');
  body = body.replaceAll('*', '').replaceAll('_', '').trim();
  if (body.endsWith(':')) body = body.substring(0, body.length - 1).trim();
  final lower = body.toLowerCase();
  if (lower == 'scene' || lower == 'current scene') return _Section.scene;
  if (lower == 'ledger' ||
      lower == 'facts' ||
      lower == 'durable' ||
      lower == 'memory ledger') {
    return _Section.ledger;
  }
  return null;
}

MemoryFact? _parseFact(String line) {
  var body = line.trim();
  while (body.startsWith('- ') ||
      body.startsWith('* ') ||
      body.startsWith('• ')) {
    body = body.substring(2).trim();
  }
  var pinned = false;
  final pinMatch = RegExp(
    r'^\[(pin|pinned)\]\s*',
    caseSensitive: false,
  ).firstMatch(body);
  if (pinMatch != null) {
    pinned = true;
    body = body.substring(pinMatch.end).trim();
  }
  if (body.isEmpty) return null;
  if (_sectionOf(body) != null) return null;
  return MemoryFact(text: body, pinned: pinned);
}
