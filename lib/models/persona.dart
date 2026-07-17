/// One user persona — who *you* are in roleplay (`{{user}}`).
class Persona {
  const Persona({
    required this.id,
    required this.name,
    this.description = '',
    this.avatarFileName,
  });

  final String id;
  final String name;

  /// Short description injected into prompts (SillyTavern persona bio).
  final String description;

  /// Local avatar under app `avatars/` (Anima-only).
  final String? avatarFileName;

  Persona copyWith({
    String? id,
    String? name,
    String? description,
    String? avatarFileName,
    bool clearAvatar = false,
  }) {
    return Persona(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      avatarFileName:
          clearAvatar ? null : (avatarFileName ?? this.avatarFileName),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
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
      avatarFileName: avatar.isEmpty ? null : avatar,
    );
  }

  static Persona starter({
    String name = 'User',
    String description = '',
    String? avatarFileName,
  }) {
    return Persona(
      id: 'persona_default',
      name: name,
      description: description,
      avatarFileName: avatarFileName,
    );
  }
}
