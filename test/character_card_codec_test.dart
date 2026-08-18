import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:anima/models/character.dart';
import 'package:anima/services/character_card_codec.dart';
import 'package:anima/services/prompt_builder.dart';

void main() {
  final codec = CharacterCardCodec();

  test('imports and exports SillyTavern Card V2 JSON', () {
    const raw = '''
{
  "spec": "chara_card_v2",
  "spec_version": "2.0",
  "data": {
    "name": "Aiko",
    "description": "{{char}} is a barista.",
    "personality": "Sarcastic but kind.",
    "scenario": "{{user}} visits late.",
    "first_mes": "You again?",
    "mes_example": "<START>\\n{{user}}: Hi\\n{{char}}: Hey.",
    "creator_notes": "Slice of life",
    "system_prompt": "",
    "post_history_instructions": "Stay in character.",
    "alternate_greetings": ["Evening.", "We're closing soon."],
    "tags": ["cafe"],
    "creator": "Tester",
    "character_version": "1.0",
    "extensions": {"demo": true}
  }
}
''';

    final character = codec.parseJsonString(raw, preferredId: 'char_test');
    expect(character.id, 'char_test');
    expect(character.name, 'Aiko');
    expect(character.description, '{{char}} is a barista.');
    expect(character.alternateGreetings, ['Evening.', "We're closing soon."]);
    expect(character.extensions['demo'], true);

    final exported = codec.toCardV2Json(character);
    final map = jsonDecode(exported) as Map<String, dynamic>;
    expect(map['spec'], 'chara_card_v2');
    expect(map['data']['name'], 'Aiko');
    expect(map['data']['extensions']['demo'], true);
  });

  test('imports Card V3 and flat V1', () {
    final v3 = codec.parseJsonString(jsonEncode({
      'spec': 'chara_card_v3',
      'spec_version': '3.0',
      'data': {
        'name': 'V3Bot',
        'description': 'desc',
        'personality': '',
        'scenario': '',
        'first_mes': 'Hello',
        'mes_example': '',
        'alternate_greetings': <String>[],
        'extensions': <String, dynamic>{},
      },
    }));
    expect(v3.name, 'V3Bot');
    expect(v3.firstMes, 'Hello');

    final v1 = codec.parseJsonString(jsonEncode({
      'name': 'V1Bot',
      'description': 'old',
      'personality': 'p',
      'scenario': 's',
      'first_mes': 'hi',
      'mes_example': 'ex',
    }));
    expect(v1.name, 'V1Bot');
    expect(v1.description, 'old');
  });

  test('migrates legacy Anima character JSON', () {
    final legacy = Character.fromJson({
      'id': 'char_old',
      'name': 'Legacy',
      'systemPrompt': 'You are Legacy.',
      'firstMessage': 'Hey there.',
    });
    expect(legacy.description, 'You are Legacy.');
    expect(legacy.firstMes, 'Hey there.');
  });

  test('applies {{user}} and {{char}} macros', () {
    const builder = PromptBuilder();
    final text = builder.applyMacros(
      'Hi {{user}}, I am {{char}}.',
      charName: 'Aiko',
      userName: 'Sam',
    );
    expect(text, 'Hi Sam, I am Aiko.');
  });

  test('rejects PNG without chara chunk', () {
    // Minimal invalid-ish PNG signature only.
    final bytes = Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]);
    expect(
      () => codec.parseBytes(bytes),
      throwsA(isA<FormatException>()),
    );
  });
}
