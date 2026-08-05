import 'package:flutter/material.dart';

import '../models/persona.dart';
import '../services/nanogpt_service.dart';
import '../services/persona_service.dart';
import '../services/settings_service.dart';
import '../screens/persona_edit_screen.dart';
import '../screens/personas_screen.dart';
import 'anima_avatar.dart';

/// Persona row shown while starting a new chat (solo or group).
class NewChatPersonaBar extends StatelessWidget {
  const NewChatPersonaBar({
    super.key,
    required this.persona,
    required this.personaService,
    required this.settingsService,
    required this.nanoGptService,
    required this.onPersonaChanged,
    this.busy = false,
  });

  final Persona persona;
  final PersonaService personaService;
  final SettingsService settingsService;
  final NanoGptService nanoGptService;
  final ValueChanged<Persona> onPersonaChanged;
  final bool busy;

  Future<void> _pick(BuildContext context) async {
    final chosen = await Navigator.of(context).push<Persona>(
      MaterialPageRoute(
        builder: (_) => PersonasScreen(
          personaService: personaService,
          settingsService: settingsService,
          nanoGptService: nanoGptService,
          pickForChat: true,
          selectedPersonaId: persona.id,
        ),
      ),
    );
    if (chosen != null) {
      onPersonaChanged(chosen);
    }
  }

  Future<void> _create(BuildContext context) async {
    final created = await Navigator.of(context).push<Persona>(
      MaterialPageRoute(
        builder: (_) => PersonaEditScreen(
          personaService: personaService,
          settingsService: settingsService,
          nanoGptService: nanoGptService,
        ),
      ),
    );
    if (created != null) {
      onPersonaChanged(created);
    }
  }

  String _subtitle(Persona p) {
    if (p.isAnonymous) {
      return 'Generic player — no saved persona details';
    }
    if (p.promptText.trim().isEmpty) {
      return 'No persona details yet';
    }
    final line = p.description.trim().isNotEmpty
        ? p.description.trim()
        : p.promptText.replaceAll('\n', ' ');
    return line;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        enabled: !busy,
        leading: AnimaAvatar(
          fileName: persona.avatarFileName,
          label: persona.name,
          radius: 22,
        ),
        title: Text('You: ${persona.name}'),
        subtitle: Text(
          _subtitle(persona),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Icon(Icons.chevron_right, color: colorScheme.onSurfaceVariant),
        onTap: busy ? null : () => _pick(context),
        onLongPress: busy ? null : () => _create(context),
      ),
    );
  }
}
