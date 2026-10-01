import 'dart:convert';
import 'dart:typed_data';

import '../models/persona.dart';

/// Reads persona cards from JSON — the shape this app writes, plus the shapes an
/// AI collaborator (or a hand-edited file) is likely to produce.
///
/// Accepted layouts:
///  * one persona        `{"name": "…", "description": "…"}`
///  * a list of them     `[{…}, {…}]` (the `anima_personas.json` layout)
///  * a wrapper          `{"personas": [ … ]}`
///  * a nested object    `{"persona": { … }}`, `{"details": { … }}`, `{"card": { … }}`
///  * a full app backup  `{"files": {"anima_personas.json": "[…]"}}`
///
/// Field names are matched leniently, so `identity`/`summary` count as the
/// description, `backstory`/`history` as the background, `looks` as the
/// appearance, and so on. A field may also be a list of lines, which is joined
/// with newlines (AI output often arrives that way).
class PersonaCardCodec {
  const PersonaCardCodec();

  static const _nameKeys = [
    'name',
    'title',
    'display_name',
    'displayName',
    'persona_name',
    'personaName',
  ];
  static const _idKeys = ['id', 'persona_id', 'personaId'];
  static const _descriptionKeys = [
    'description',
    'summary',
    'identity',
    'role',
    'overview',
    'identity_and_role',
    'identityAndRole',
    'who_they_are',
    'whoTheyAre',
  ];
  static const _appearanceKeys = [
    'appearance',
    'looks',
    'physical',
    'physical_description',
    'physicalDescription',
    'body',
  ];
  static const _personalityKeys = [
    'personality',
    'traits',
    'temperament',
    'character',
  ];
  static const _backgroundKeys = [
    'background',
    'backstory',
    'back_story',
    'history',
    'bio',
    'biography',
    'origin',
  ];
  static const _goalsKeys = [
    'goals',
    'motivations',
    'motivation',
    'objectives',
    'drives',
    'ambitions',
    'desires',
  ];
  static const _avatarKeys = ['avatar_file', 'avatarFile', 'avatar', 'image'];
  static const _nestedKeys = [
    'persona',
    'details',
    'fields',
    'card',
    'data',
    'profile',
  ];

  /// Parses [raw] JSON into personas. Throws [FormatException] with a plain
  /// English message when nothing usable is found.
  List<Persona> parseJson(String raw, {String Function()? newId}) {
    if (raw.trim().isEmpty) {
      throw const FormatException('That file is empty.');
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      throw const FormatException(
        'That file is not valid JSON. Export a persona as JSON and try again.',
      );
    }

    final personas = <Persona>[];
    _collect(decoded, personas, newId);

    if (personas.isEmpty) {
      throw const FormatException(
        'No persona found in that file — it needs at least a "name" field.',
      );
    }
    return personas;
  }

  /// Same as [parseJson] for a file already read into memory.
  List<Persona> parseBytes(Uint8List bytes, {String Function()? newId}) {
    return parseJson(utf8.decode(bytes, allowMalformed: true), newId: newId);
  }

  void _collect(
    dynamic node,
    List<Persona> out,
    String Function()? newId, {
    Map<String, dynamic>? merge,
  }) {
    if (node is List) {
      for (final item in node) {
        _collect(item, out, newId);
      }
      return;
    }
    if (node is! Map) return;

    final map = <String, dynamic>{
      ...?merge,
      ...Map<String, dynamic>.from(node),
    };

    // A backup file: {"files": {"anima_personas.json": "<json text>"}}.
    final files = map['files'];
    if (files is Map) {
      for (final key in files.keys) {
        if ('$key'.toLowerCase().contains('persona')) {
          final inner = files[key];
          if (inner is String && inner.trim().isNotEmpty) {
            _collect(jsonDecodeSafe(inner), out, newId);
          }
        }
      }
      return;
    }

    // Wrappers that hold the real list or object.
    for (final key in const [
      'personas',
      'persona_cards',
      'personaCards',
      'list',
      'items',
    ]) {
      final wrapped = map[key];
      if (wrapped is List) {
        for (final item in wrapped) {
          _collect(item, out, newId);
        }
        return;
      }
      if (wrapped is Map) {
        _collect(wrapped, out, newId, merge: map);
        return;
      }
    }

    // {"name": "Kaelen", "persona": "long description"} — a plain string.
    final nestedPersona = map['persona'];
    if (nestedPersona is String && nestedPersona.trim().isNotEmpty) {
      map.putIfAbsent('description', () => nestedPersona);
      map.remove('persona');
    }

    // A card that wraps its fields in one nested object.
    for (final key in _nestedKeys) {
      final nested = map[key];
      if (nested is Map) {
        final persona = fromMap(
          map,
          nested: Map<String, dynamic>.from(nested),
          newId: newId,
        );
        if (persona != null) out.add(persona);
        return;
      }
    }

    final persona = fromMap(map, newId: newId);
    if (persona != null) out.add(persona);
  }

  /// Turns one card into a [Persona]. Returns null when it has no usable name.
  static Persona? fromMap(
    Map<String, dynamic> map, {
    Map<String, dynamic>? nested,
    String Function()? newId,
  }) {
    final flat = <String, dynamic>{
      ...map,
      ...?nested,
    };

    final name = _text(_first(flat, _nameKeys));
    if (name.isEmpty) return null;

    final id = _text(_first(flat, _idKeys));
    final avatar = _text(_first(flat, _avatarKeys));

    return Persona.fromJson({
      'id': id.isNotEmpty
          ? id
          : (newId?.call() ??
              'persona_${DateTime.now().microsecondsSinceEpoch}'),
      'name': name.split('\n').first.trim(),
      'description': _text(_first(flat, _descriptionKeys)),
      'appearance': _text(_first(flat, _appearanceKeys)),
      'personality': _text(_first(flat, _personalityKeys)),
      'background': _text(_first(flat, _backgroundKeys)),
      'goals': _text(_first(flat, _goalsKeys)),
      // JSON cannot carry an image, so only a bare local file name is useful.
      if (avatar.isNotEmpty && !avatar.contains('/') && !avatar.contains(':'))
        'avatar_file': avatar,
    });
  }

  static dynamic _first(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      if (map.containsKey(key)) {
        final value = map[key];
        if (value != null && '$value'.trim().isNotEmpty) return value;
      }
    }
    return null;
  }

  /// Lists become newline-joined text; anything else is trimmed text.
  static String _text(dynamic value) {
    if (value == null) return '';
    if (value is String) return value.trim();
    if (value is List) {
      return value
          .map((item) => '$item'.trim())
          .where((line) => line.isNotEmpty)
          .join('\n')
          .trim();
    }
    if (value is Map) {
      return value.entries
          .map((entry) => '${entry.key}: ${entry.value}'.trim())
          .where((line) => line.isNotEmpty)
          .join('\n')
          .trim();
    }
    return '$value'.trim();
  }

  /// Best-effort decode — used for text stored inside a backup file.
  static dynamic jsonDecodeSafe(String raw) {
    try {
      return jsonDecode(raw);
    } on FormatException {
      return null;
    }
  }
}
