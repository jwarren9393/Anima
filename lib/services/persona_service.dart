import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import '../models/persona.dart';
import 'avatar_service.dart';
import 'settings_service.dart';

/// Saves multiple personas on this device and tracks the default active one.
///
/// File: app documents / `anima_personas.json`
/// Default id: secure storage key `active_persona_id`
class PersonaService {
  PersonaService({
    Future<Directory> Function()? documentsDirectory,
    FlutterSecureStorage? storage,
    AvatarService? avatarService,
    SettingsService? settingsService,
  })  : _documentsDirectory =
            documentsDirectory ?? getApplicationDocumentsDirectory,
        _storage = storage ?? const FlutterSecureStorage(),
        _avatarService = avatarService ??
            AvatarService(documentsDirectory: documentsDirectory),
        _settingsService = settingsService ?? SettingsService(storage: storage);

  static const _fileName = 'anima_personas.json';
  static const _activeIdKey = 'active_persona_id';

  final Future<Directory> Function() _documentsDirectory;
  final FlutterSecureStorage _storage;
  final AvatarService _avatarService;
  final SettingsService _settingsService;

  Future<File> _file() async {
    final dir = await _documentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  /// Loads all personas. Migrates the old single persona from Settings once.
  Future<List<Persona>> loadPersonas() async {
    final file = await _file();
    if (!await file.exists()) {
      return _migrateFromLegacySettings();
    }

    try {
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) {
        return _migrateFromLegacySettings();
      }
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return _migrateFromLegacySettings();
      }
      final personas = decoded
          .whereType<Map>()
          .map((item) => Persona.fromJson(Map<String, dynamic>.from(item)))
          .where((p) => p.id.isNotEmpty && p.name.isNotEmpty)
          .toList();
      if (personas.isEmpty) {
        return _migrateFromLegacySettings();
      }
      return personas;
    } catch (_) {
      return _migrateFromLegacySettings();
    }
  }

  Future<List<Persona>> _migrateFromLegacySettings() async {
    final name = await _settingsService.getUserName();
    final description = await _settingsService.getUserPersona();
    final avatar = await _settingsService.getPersonaAvatarFileName();
    final starter = Persona.starter(
      name: name,
      description: description,
      avatarFileName: avatar,
    );
    await savePersonas([starter]);
    await setActivePersonaId(starter.id);
    return [starter];
  }

  Future<void> savePersonas(List<Persona> personas) async {
    final file = await _file();
    final payload = personas.map((p) => p.toJson()).toList();
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(payload),
    );
  }

  Future<String?> getActivePersonaId() async {
    final value = await _storage.read(key: _activeIdKey);
    if (value == null || value.trim().isEmpty) return null;
    return value.trim();
  }

  Future<void> setActivePersonaId(String? id) async {
    if (id == null || id.trim().isEmpty) {
      await _storage.delete(key: _activeIdKey);
      return;
    }
    await _storage.write(key: _activeIdKey, value: id.trim());
  }

  /// Default persona for new chats (falls back to first in the list).
  Future<Persona> getActivePersona() async {
    final all = await loadPersonas();
    final activeId = await getActivePersonaId();
    if (activeId != null) {
      for (final p in all) {
        if (p.id == activeId) return p;
      }
    }
    final first = all.first;
    await setActivePersonaId(first.id);
    return first;
  }

  /// Resolve a persona by id, or the active default if missing.
  Future<Persona> resolve(String? personaId) async {
    if (personaId != null && personaId.trim().isNotEmpty) {
      final all = await loadPersonas();
      for (final p in all) {
        if (p.id == personaId) return p;
      }
    }
    return getActivePersona();
  }

  Future<Persona?> getById(String id) async {
    final all = await loadPersonas();
    for (final p in all) {
      if (p.id == id) return p;
    }
    return null;
  }

  Future<List<Persona>> upsert(Persona persona) async {
    final all = await loadPersonas();
    final index = all.indexWhere((p) => p.id == persona.id);
    if (index >= 0) {
      all[index] = persona;
    } else {
      all.add(persona);
    }
    await savePersonas(all);
    final active = await getActivePersonaId();
    if (active == null) {
      await setActivePersonaId(persona.id);
    }
    return all;
  }

  /// Deletes a persona. Always keeps at least one.
  Future<List<Persona>> delete(String id) async {
    final all = await loadPersonas();
    Persona? removed;
    for (final p in all) {
      if (p.id == id) {
        removed = p;
        break;
      }
    }
    if (all.length <= 1) {
      return all;
    }
    all.removeWhere((p) => p.id == id);
    if (removed?.avatarFileName != null) {
      await _avatarService.delete(removed!.avatarFileName);
    }
    final active = await getActivePersonaId();
    if (active == id) {
      await setActivePersonaId(all.first.id);
    }
    await savePersonas(all);
    return all;
  }

  String newId() => 'persona_${DateTime.now().millisecondsSinceEpoch}';
}
