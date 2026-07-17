import 'dart:convert';
import 'dart:typed_data';

import '../models/character.dart';

/// Import / export SillyTavern-compatible Character Cards (V1, V2, V3).
///
/// - JSON: V1 flat, V2 `chara_card_v2`, V3 `chara_card_v3`
/// - PNG: reads `tEXt` keywords `chara` and `ccv3` (usually base64 JSON)
class CharacterCardCodec {
  /// Parse card bytes (JSON UTF-8 or PNG with embedded card).
  Character parseBytes(Uint8List bytes, {String? preferredId}) {
    if (_looksLikePng(bytes)) {
      final jsonText = extractJsonFromPng(bytes);
      if (jsonText == null) {
        throw const FormatException(
          'This PNG does not contain a SillyTavern character card '
          '(missing “chara” / “ccv3” text chunk).',
        );
      }
      return parseJsonString(jsonText, preferredId: preferredId);
    }

    final text = utf8.decode(bytes).trim();
    return parseJsonString(text, preferredId: preferredId);
  }

  Character parseJsonString(String raw, {String? preferredId}) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException('Character card JSON must be an object.');
    }
    return fromCardMap(
      Map<String, dynamic>.from(decoded),
      preferredId: preferredId,
    );
  }

  /// Accepts V1 / V2 / V3 card maps (and Anima on-device maps).
  Character fromCardMap(Map<String, dynamic> root, {String? preferredId}) {
    final spec = '${root['spec'] ?? ''}'.toLowerCase();
    final Map<String, dynamic> data;

    if (spec.contains('chara_card_v2') ||
        spec.contains('chara_card_v3') ||
        root['data'] is Map) {
      data = Map<String, dynamic>.from(root['data'] as Map);
    } else {
      data = Map<String, dynamic>.from(root);
    }

    final id = (preferredId != null && preferredId.trim().isNotEmpty)
        ? preferredId.trim()
        : (_asString(root['id']).isNotEmpty
            ? _asString(root['id'])
            : 'char_${DateTime.now().millisecondsSinceEpoch}');

    final normalized = <String, dynamic>{
      ...data,
      'id': id,
      'name': data['name'] ?? root['name'] ?? '',
    };
    return Character.fromJson(normalized);
  }

  /// Export as Character Card V2 JSON (works in SillyTavern and most card sites).
  String toCardV2Json(Character character, {bool pretty = true}) {
    final data = <String, dynamic>{
      'name': character.name,
      'description': character.description,
      'personality': character.personality,
      'scenario': character.scenario,
      'first_mes': character.firstMes,
      'mes_example': character.mesExample,
      'creator_notes': character.creatorNotes,
      'system_prompt': character.systemPrompt,
      'post_history_instructions': character.postHistoryInstructions,
      'alternate_greetings': character.alternateGreetings,
      'tags': character.tags,
      'creator': character.creator,
      'character_version': character.characterVersion,
      'extensions':
          character.extensions.isEmpty ? <String, dynamic>{} : character.extensions,
    };
    if (character.characterBook != null) {
      data['character_book'] = character.characterBook;
    }

    final card = <String, dynamic>{
      'spec': 'chara_card_v2',
      'spec_version': '2.0',
      'data': data,
    };

    return pretty
        ? const JsonEncoder.withIndent('  ').convert(card)
        : jsonEncode(card);
  }

  /// Export V3 wrapper (same core data) for newer SillyTavern versions.
  String toCardV3Json(Character character, {bool pretty = true}) {
    final v2 = jsonDecode(toCardV2Json(character, pretty: false))
        as Map<String, dynamic>;
    v2['spec'] = 'chara_card_v3';
    v2['spec_version'] = '3.0';
    return pretty
        ? const JsonEncoder.withIndent('  ').convert(v2)
        : jsonEncode(v2);
  }

  /// Pull base64 JSON from PNG `chara` / `ccv3` text chunks.
  String? extractJsonFromPng(Uint8List bytes) {
    if (!_looksLikePng(bytes)) return null;

    var offset = 8;
    String? chara;
    String? ccv3;

    while (offset + 12 <= bytes.length) {
      final length = _readUint32(bytes, offset);
      final type = String.fromCharCodes(bytes.sublist(offset + 4, offset + 8));
      final dataStart = offset + 8;
      final dataEnd = dataStart + length;
      if (dataEnd + 4 > bytes.length) break;

      final chunkData = bytes.sublist(dataStart, dataEnd);
      if (type == 'tEXt') {
        final decoded = _parseTextChunk(chunkData);
        if (decoded != null) {
          final key = decoded.key.toLowerCase();
          if (key == 'chara') chara = decoded.value;
          if (key == 'ccv3') ccv3 = decoded.value;
        }
      } else if (type == 'IEND') {
        break;
      }

      offset = dataEnd + 4;
    }

    final payload = ccv3 ?? chara;
    if (payload == null || payload.isEmpty) return null;

    try {
      return utf8.decode(base64.decode(payload.trim()));
    } catch (_) {
      if (payload.trimLeft().startsWith('{')) return payload;
      rethrow;
    }
  }

  bool _looksLikePng(Uint8List bytes) {
    if (bytes.length < 8) return false;
    const sig = [137, 80, 78, 71, 13, 10, 26, 10];
    for (var i = 0; i < 8; i++) {
      if (bytes[i] != sig[i]) return false;
    }
    return true;
  }

  int _readUint32(Uint8List bytes, int offset) {
    return (bytes[offset] << 24) |
        (bytes[offset + 1] << 16) |
        (bytes[offset + 2] << 8) |
        bytes[offset + 3];
  }

  ({String key, String value})? _parseTextChunk(Uint8List data) {
    final sep = data.indexOf(0);
    if (sep <= 0 || sep >= data.length - 1) return null;
    final key = ascii.decode(data.sublist(0, sep), allowInvalid: true);
    final value = ascii.decode(data.sublist(sep + 1), allowInvalid: true);
    return (key: key, value: value);
  }

  String _asString(dynamic value) {
    if (value == null) return '';
    return '$value'.trim();
  }
}
