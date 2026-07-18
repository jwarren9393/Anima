/// One user persona — who *you* are in roleplay (`{{user}}`).
class Persona {
  const Persona({
    required this.id,
    required this.name,
    this.description = '',
    this.appearance = '',
    this.personality = '',
    this.background = '',
    this.goals = '',
    this.avatarFileName,
  });

  final String id;
  final String name;

  /// Short identity / role summary injected into prompts.
  final String description;

  final String appearance;
  final String personality;
  final String background;
  final String goals;

  /// Local avatar under app `avatars/` (Anima-only).
  final String? avatarFileName;

  /// Structured player identity sent to NanoGPT on every generation.
  String get promptText {
    final parts = <String>[
      if (description.trim().isNotEmpty)
        'Identity and role:\n${description.trim()}',
      if (appearance.trim().isNotEmpty) 'Appearance:\n${appearance.trim()}',
      if (personality.trim().isNotEmpty) 'Personality:\n${personality.trim()}',
      if (background.trim().isNotEmpty) 'Background:\n${background.trim()}',
      if (goals.trim().isNotEmpty) 'Goals and motivations:\n${goals.trim()}',
    ];
    return parts.join('\n\n');
  }

  Persona copyWith({
    String? id,
    String? name,
    String? description,
    String? appearance,
    String? personality,
    String? background,
    String? goals,
    String? avatarFileName,
    bool clearAvatar = false,
  }) {
    return Persona(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      appearance: appearance ?? this.appearance,
      personality: personality ?? this.personality,
      background: background ?? this.background,
      goals: goals ?? this.goals,
      avatarFileName: clearAvatar
          ? null
          : (avatarFileName ?? this.avatarFileName),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'appearance': appearance,
    'personality': personality,
    'background': background,
    'goals': goals,
    if (avatarFileName != null && avatarFileName!.isNotEmpty)
      'avatar_file': avatarFileName,
  };

  factory Persona.fromJson(Map<String, dynamic> json) {
    final avatar = '${json['avatar_file'] ?? ''}'.trim();
    return Persona(
      id: '${json['id'] ?? ''}'.trim().isEmpty
          ? 'persona_${DateTime.now().millisecondsSinceEpoch}'
          : '${json['id']}'.trim(),
      name: '${json['name'] ?? 'User'}'.trim().isEmpty
          ? 'User'
          : '${json['name']}'.trim(),
      description: '${json['description'] ?? ''}'.trim(),
      appearance: '${json['appearance'] ?? ''}'.trim(),
      personality: '${json['personality'] ?? ''}'.trim(),
      background: '${json['background'] ?? ''}'.trim(),
      goals: '${json['goals'] ?? ''}'.trim(),
      avatarFileName: avatar.isEmpty ? null : avatar,
    );
  }

  static Persona starter({
    String name = 'User',
    String description = '',
    String appearance = '',
    String personality = '',
    String background = '',
    String goals = '',
    String? avatarFileName,
  }) {
    return Persona(
      id: 'persona_default',
      name: name,
      description: description,
      appearance: appearance,
      personality: personality,
      background: background,
      goals: goals,
      avatarFileName: avatarFileName,
    );
  }
}
