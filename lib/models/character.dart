/// A character you chat with: a name plus personality instructions for the AI.
class Character {
  const Character({
    required this.id,
    required this.name,
    required this.systemPrompt,
  });

  /// Stable id saved on this device (not shown to you in normal use).
  final String id;

  /// Display name, e.g. "Luna" or "Coach".
  final String name;

  /// Instructions sent to NanoGPT as the system message (personality / role).
  final String systemPrompt;

  Character copyWith({
    String? id,
    String? name,
    String? systemPrompt,
  }) {
    return Character(
      id: id ?? this.id,
      name: name ?? this.name,
      systemPrompt: systemPrompt ?? this.systemPrompt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'systemPrompt': systemPrompt,
      };

  factory Character.fromJson(Map<String, dynamic> json) {
    return Character(
      id: json['id'] as String? ?? '',
      name: (json['name'] as String? ?? '').trim(),
      systemPrompt: (json['systemPrompt'] as String? ?? '').trim(),
    );
  }

  /// Starter character created the first time the app has none saved.
  static Character starter() {
    return Character(
      id: 'char_starter',
      name: 'Anima',
      systemPrompt:
          'You are Anima, a warm, thoughtful companion. '
          'Keep replies clear and conversational. '
          'Be supportive without being overbearing.',
    );
  }
}
