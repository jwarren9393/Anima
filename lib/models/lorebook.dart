/// SillyTavern-compatible character lorebook (World Info) embedded in a card.
///
/// Spec: Character Card V2 `character_book` — keyword-triggered lore so long
/// worlds do not dump everything into every prompt.
class Lorebook {
  const Lorebook({
    this.name = '',
    this.description = '',
    this.scanDepth = 4,
    this.tokenBudget = 512,
    this.recursiveScanning = false,
    this.entries = const [],
    this.extensions = const {},
  });

  /// Human label (not sent to the AI).
  final String name;
  final String description;

  /// How many recent chat messages to scan for keywords.
  final int scanDepth;

  /// Rough max “tokens” of lore to inject (we approximate 1 token ≈ 4 chars).
  final int tokenBudget;

  /// When enabled, selected entry content can trigger further lore entries.
  final bool recursiveScanning;

  final List<LorebookEntry> entries;
  final Map<String, dynamic> extensions;

  bool get isEmpty => entries.isEmpty;

  Lorebook copyWith({
    String? name,
    String? description,
    int? scanDepth,
    int? tokenBudget,
    bool? recursiveScanning,
    List<LorebookEntry>? entries,
    Map<String, dynamic>? extensions,
  }) {
    return Lorebook(
      name: name ?? this.name,
      description: description ?? this.description,
      scanDepth: scanDepth ?? this.scanDepth,
      tokenBudget: tokenBudget ?? this.tokenBudget,
      recursiveScanning: recursiveScanning ?? this.recursiveScanning,
      entries: entries ?? this.entries,
      extensions: extensions ?? this.extensions,
    );
  }

  Map<String, dynamic> toJson() => {
        if (name.isNotEmpty) 'name': name,
        if (description.isNotEmpty) 'description': description,
        'scan_depth': scanDepth,
        'token_budget': tokenBudget,
        'recursive_scanning': recursiveScanning,
        'extensions': extensions.isEmpty ? <String, dynamic>{} : extensions,
        'entries': entries.map((e) => e.toJson()).toList(),
      };

  factory Lorebook.fromJson(Map<String, dynamic> json) {
    final entries = <LorebookEntry>[];
    final rawEntries = json['entries'];
    // Character Card V2 uses a list; SillyTavern World Info exports a map by uid.
    if (rawEntries is List) {
      for (final item in rawEntries) {
        if (item is Map) {
          entries.add(
            LorebookEntry.fromJson(Map<String, dynamic>.from(item)),
          );
        }
      }
    } else if (rawEntries is Map) {
      for (final item in rawEntries.values) {
        if (item is Map) {
          entries.add(
            LorebookEntry.fromJson(Map<String, dynamic>.from(item)),
          );
        }
      }
    }

    return Lorebook(
      name: _str(json['name']),
      description: _str(json['description']),
      scanDepth: _int(
        json['scan_depth'] ?? json['scanDepth'],
        fallback: 4,
      ).clamp(1, 50),
      tokenBudget: _int(
        json['token_budget'] ?? json['tokenBudget'],
        fallback: 512,
      ).clamp(10, 4000),
      recursiveScanning: json['recursive_scanning'] == true ||
          json['recursiveScanning'] == true,
      entries: entries,
      extensions: _map(json['extensions']),
    );
  }

  /// Parse a standalone SillyTavern / Anima lorebook JSON file.
  ///
  /// Accepts: character_book object, full card with character_book, or a bare
  /// World Info export (`entries` list or map).
  factory Lorebook.parseImport(Map<String, dynamic> root, {String? fallbackName}) {
    Map<String, dynamic> bookMap = root;

    final embedded = root['character_book'] ?? root['characterBook'];
    if (embedded is Map) {
      bookMap = Map<String, dynamic>.from(embedded);
    } else if (root['data'] is Map) {
      final data = Map<String, dynamic>.from(root['data'] as Map);
      final nested = data['character_book'] ?? data['characterBook'];
      if (nested is Map) {
        bookMap = Map<String, dynamic>.from(nested);
      }
    }

    final book = Lorebook.fromJson(bookMap);
    if (book.name.trim().isNotEmpty) return book;
    final name = (fallbackName ?? '').trim();
    if (name.isEmpty) return book;
    return book.copyWith(name: name);
  }

  /// Empty book ready for the editor.
  factory Lorebook.empty({String name = ''}) => Lorebook(name: name);

  static String _str(dynamic value) =>
      ('$value' == 'null' ? '' : '$value').trim();

  static int _int(dynamic value, {required int fallback}) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse('$value') ?? fallback;
  }

  static Map<String, dynamic> _map(dynamic value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    return {};
  }
}

/// One World Info entry — keys trigger [content] into the prompt.
class LorebookEntry {
  const LorebookEntry({
    this.id,
    this.keys = const [],
    this.secondaryKeys = const [],
    this.content = '',
    this.enabled = true,
    this.insertionOrder = 100,
    this.caseSensitive = false,
    this.selective = false,
    this.constant = false,
    this.position = LorebookPosition.beforeChar,
    this.priority = 10,
    this.name = '',
    this.comment = '',
    this.extensions = const {},
  });

  final int? id;

  /// Keywords that can fire this entry (any match is enough, unless selective).
  final List<String> keys;

  /// Used with [selective]: need a key from both lists.
  final List<String> secondaryKeys;

  /// Text injected when this entry fires.
  final String content;

  final bool enabled;

  /// Lower numbers insert earlier in the lore block.
  final int insertionOrder;

  final bool caseSensitive;

  /// If true, require a primary key AND a secondary key.
  final bool selective;

  /// If true, always include (within budget) — no keyword needed.
  final bool constant;

  /// Where to place relative to character description fields.
  final LorebookPosition position;

  /// When over budget, lower priority numbers are dropped first.
  final int priority;

  /// Optional label for the editor UI.
  final String name;
  final String comment;
  final Map<String, dynamic> extensions;

  String get displayLabel {
    if (name.trim().isNotEmpty) return name.trim();
    if (comment.trim().isNotEmpty) return comment.trim();
    if (keys.isNotEmpty) return keys.join(', ');
    if (constant) return 'Always-on entry';
    return 'Untitled entry';
  }

  LorebookEntry copyWith({
    int? id,
    List<String>? keys,
    List<String>? secondaryKeys,
    String? content,
    bool? enabled,
    int? insertionOrder,
    bool? caseSensitive,
    bool? selective,
    bool? constant,
    LorebookPosition? position,
    int? priority,
    String? name,
    String? comment,
    Map<String, dynamic>? extensions,
    bool clearId = false,
  }) {
    return LorebookEntry(
      id: clearId ? null : (id ?? this.id),
      keys: keys ?? this.keys,
      secondaryKeys: secondaryKeys ?? this.secondaryKeys,
      content: content ?? this.content,
      enabled: enabled ?? this.enabled,
      insertionOrder: insertionOrder ?? this.insertionOrder,
      caseSensitive: caseSensitive ?? this.caseSensitive,
      selective: selective ?? this.selective,
      constant: constant ?? this.constant,
      position: position ?? this.position,
      priority: priority ?? this.priority,
      name: name ?? this.name,
      comment: comment ?? this.comment,
      extensions: extensions ?? this.extensions,
    );
  }

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'keys': keys,
        'content': content,
        'extensions': extensions.isEmpty ? <String, dynamic>{} : extensions,
        'enabled': enabled,
        'insertion_order': insertionOrder,
        'case_sensitive': caseSensitive,
        if (name.isNotEmpty) 'name': name,
        'priority': priority,
        if (comment.isNotEmpty) 'comment': comment,
        'selective': selective,
        'secondary_keys': secondaryKeys,
        'constant': constant,
        'position': position.jsonValue,
      };

  factory LorebookEntry.fromJson(Map<String, dynamic> json) {
    // ST World Info uses `disable`; Character Card uses `enabled`.
    final disabled = json['disable'] == true || json['disabled'] == true;
    final enabledFlag = json['enabled'];
    final enabled = disabled
        ? false
        : (enabledFlag == null ? true : enabledFlag != false);

    return LorebookEntry(
      id: json['id'] is int
          ? json['id'] as int
          : json['uid'] is int
              ? json['uid'] as int
              : int.tryParse('${json['id'] ?? json['uid'] ?? ''}'),
      keys: _stringList(json['keys'] ?? json['key']),
      secondaryKeys: _stringList(
        json['secondary_keys'] ?? json['keysecondary'] ?? json['keySecondary'],
      ),
      content: _str(json['content']),
      enabled: enabled,
      insertionOrder: _int(
        json['insertion_order'] ?? json['order'],
        fallback: 100,
      ),
      caseSensitive:
          json['case_sensitive'] == true || json['caseSensitive'] == true,
      selective: json['selective'] == true,
      constant: json['constant'] == true,
      position: LorebookPosition.fromJson(json['position']),
      priority: _int(json['priority'], fallback: 10),
      name: _str(json['name']),
      comment: _str(json['comment']),
      extensions: json['extensions'] is Map
          ? Map<String, dynamic>.from(json['extensions'] as Map)
          : {},
    );
  }

  static String _str(dynamic value) =>
      ('$value' == 'null' ? '' : '$value').trim();

  static int _int(dynamic value, {required int fallback}) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse('$value') ?? fallback;
  }

  static List<String> _stringList(dynamic value) {
    if (value is! List) return const [];
    return value
        .map((item) => '$item'.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }
}

enum LorebookPosition {
  beforeChar,
  afterChar;

  String get jsonValue =>
      this == LorebookPosition.afterChar ? 'after_char' : 'before_char';

  static LorebookPosition fromJson(dynamic value) {
    // SillyTavern numeric positions: 0 ≈ before defs, 1 ≈ after defs.
    if (value is num) {
      return value.round() == 1
          ? LorebookPosition.afterChar
          : LorebookPosition.beforeChar;
    }
    final text = '$value'.toLowerCase().trim();
    if (text == 'after_char' || text == 'after' || text == '1') {
      return LorebookPosition.afterChar;
    }
    return LorebookPosition.beforeChar;
  }
}
