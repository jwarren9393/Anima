import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;

import '../models/persona.dart';
import 'app_data_root.dart';
import 'app_paths.dart';
import 'avatar_service.dart';
import 'settings_service.dart';

/// Saves multiple personas on this device and tracks the default active one.
///
/// File: Anima library folder / `anima_personas.json`
/// Default id: `anima_active_persona_id.txt` in that folder
class PersonaService {
  PersonaService({
    Future<Directory> Function()? documentsDirectory,
    FlutterSecureStorage? storage,
    AvatarService? avatarService,
    SettingsService? settingsService,
  })  : _documentsDirectory =
            documentsDirectory ?? appDocumentsDirectory,
        _storage = storage ?? const FlutterSecureStorage(),
        _avatarService = avatarService ??
            AvatarService(documentsDirectory: documentsDirectory),
        _settingsService = settingsService ??
            SettingsService(
              storage: storage,
              documentsDirectory: documentsDirectory,
            );

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

  /// Loads all personas. Migrates legacy Settings persona once if the file is
  /// missing and old fields were filled in.
  Future<List<Persona>> loadPersonas() async {
    final file = await _file();
    if (!await file.exists()) {
      return _migrateFromLegacySettings();
    }

    try {
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) {
        return const [];
      }
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return const [];
      }
      return decoded
          .whereType<Map>()
          .map((item) => Persona.fromJson(Map<String, dynamic>.from(item)))
          .where((p) => p.id.isNotEmpty && p.name.isNotEmpty && !p.isAnonymous)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<List<Persona>> _migrateFromLegacySettings() async {
    final name = await _settingsService.getUserName();
    final description = await _settingsService.getUserPersona();
    final avatar = await _settingsService.getPersonaAvatarFileName();
    final hasLegacy = description.trim().isNotEmpty ||
        (avatar != null && avatar.isNotEmpty) ||
        (name.trim().isNotEmpty &&
            name.trim() != SettingsService.defaultUserName);
    if (!hasLegacy) {
      await savePersonas(const []);
      return const [];
    }
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
    try {
      final file = await _activeIdFile();
      if (await file.exists()) {
        final value = (await file.readAsString()).trim();
        if (value.isNotEmpty) return value;
      }
    } catch (_) {}
    final value = await _storage.read(key: _activeIdKey);
    if (value == null || value.trim().isEmpty) return null;
    await setActivePersonaId(value.trim());
    return value.trim();
  }

  Future<void> setActivePersonaId(String? id) async {
    final file = await _activeIdFile();
    if (id == null || id.trim().isEmpty) {
      if (await file.exists()) {
        try {
          await file.delete();
        } catch (_) {}
      }
      await _storage.delete(key: _activeIdKey);
      return;
    }
    await file.writeAsString(id.trim(), flush: true);
    await _storage.write(key: _activeIdKey, value: id.trim());
  }

  Future<File> _activeIdFile() async {
    final dir = await _documentsDirectory();
    return File(p.join(dir.path, AppDataRoot.activePersonaFileName));
  }

  /// Saved default persona, or null when the list is empty.
  Future<Persona?> tryGetActivePersona() async {
    final all = await loadPersonas();
    if (all.isEmpty) return null;
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

  /// Default for new chats — active persona, first saved, or generic User.
  Future<Persona> defaultForNewChat() async {
    return (await tryGetActivePersona()) ?? Persona.anonymous();
  }

  /// Default persona for new chats (falls back to [Persona.anonymous]).
  Future<Persona> getActivePersona() async {
    return defaultForNewChat();
  }

  /// Resolve a persona by id, or the active default if missing.
  Future<Persona> resolve(String? personaId) async {
    if (personaId != null &&
        personaId.trim().isNotEmpty &&
        personaId != Persona.anonymousId) {
      final all = await loadPersonas();
      for (final p in all) {
        if (p.id == personaId) return p;
      }
    }
    return getActivePersona();
  }

  Future<Persona?> getById(String id) async {
    if (id == Persona.anonymousId) return Persona.anonymous();
    final all = await loadPersonas();
    for (final p in all) {
      if (p.id == id) return p;
    }
    return null;
  }

  Future<List<Persona>> upsert(Persona persona) async {
    final all = List<Persona>.from(await loadPersonas());
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

  /// Deletes a persona. The list may end up empty.
  Future<List<Persona>> delete(String id) async {
    final all = await loadPersonas();
    all.removeWhere((p) => p.id == id);
    await _avatarService.deleteAllForStem(id);
    final active = await getActivePersonaId();
    if (active == id) {
      if (all.isEmpty) {
        await setActivePersonaId(null);
      } else {
        await setActivePersonaId(all.first.id);
      }
    }
    await savePersonas(all);
    return all;
  }

  String newId() => 'persona_${DateTime.now().millisecondsSinceEpoch}';

  /// Deep copy of [source] with a new id, name suffix, and separate avatar file.
  Future<Persona> duplicate(Persona source) async {
    final id = newId();
    String? avatar;
    final avatarName = source.avatarFileName?.trim();
    if (avatarName != null && avatarName.isNotEmpty) {
      final bytes = await _avatarService.readBytes(avatarName);
      if (bytes != null) {
        avatar = await _avatarService.saveHistoryBytes(
          stem: id,
          bytes: bytes,
          extension: p.extension(avatarName),
        );
      }
    }

    final baseName = source.name.trim().isEmpty ? 'User' : source.name.trim();
    return source.copyWith(
      id: id,
      name: '$baseName (copy)',
      avatarFileName: avatar,
      clearSourceWorkshopId: true,
    );
  }
}
