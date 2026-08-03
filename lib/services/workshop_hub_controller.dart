import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/character.dart';
import '../models/chat_session.dart';
import '../models/global_lorebook.dart';
import '../models/lorebook.dart';
import '../models/persona.dart';
import '../models/world_workshop.dart';
import '../models/workshop_chat_import_options.dart';
import '../models/workshop_hub_models.dart';
import 'nanogpt_service.dart';
import 'settings_service.dart';
import 'world_workshop_builder.dart';
import 'workshop_hub_service.dart';

/// API + navigation helpers for Creation Center hub features.
class WorkshopHubController {
  WorkshopHubController({
    WorldWorkshopBuilder? builder,
    WorkshopHubService? hub,
  }) : _builder = builder ?? WorldWorkshopBuilder(),
       _hub = hub ?? WorkshopHubService();

  final WorldWorkshopBuilder _builder;
  final WorkshopHubService _hub;

  WorkshopHubService get hub => _hub;
  WorldWorkshopBuilder get builder => _builder;

  WorkshopHubStatus statusFor({
    required WorldWorkshop workshop,
    required List<Character> allCharacters,
    required List<ChatSession> workshopChats,
    GlobalLorebook? linkedLorebook,
  }) {
    return _hub.computeStatus(
      workshop: workshop,
      allCharacters: allCharacters,
      workshopChats: workshopChats,
      linkedLorebook: linkedLorebook,
    );
  }

  Future<String?> summarizeWorld({
    required WorldWorkshop workshop,
    required NanoGptService nanoGpt,
    required SettingsService settings,
    Lorebook? sourceLorebook,
  }) async {
    final collaborator = await settings.getCollaboratorSettings();
    final model = await settings.getModel();
    final sampling = WorldWorkshopBuilder.workshopExportSampling(
      await settings.getSampling(),
    );
    final baseUrl = await settings.getApiBaseUrl();
    final guidance = workshop.workshopGuidanceNote.trim().isNotEmpty
        ? workshop.workshopGuidanceNote
        : collaborator.guidanceNote;
    final raw = await nanoGpt.complete(
      model: model,
      messages: _builder.buildWorldSummaryMessages(
        conversation: workshop.messages,
        existingSummary: workshop.worldSummary,
        guidanceNote: guidance,
        importedSource: workshop.importedSource,
        sourceLorebook: sourceLorebook,
        canonPinMessageIds: workshop.canonPinMessageIds,
      ),
      baseUrl: baseUrl,
      sampling: sampling,
    );
    return raw.trim();
  }

  Future<String?> generateOverview({
    required WorldWorkshop workshop,
    required NanoGptService nanoGpt,
    required SettingsService settings,
    Lorebook? sourceLorebook,
  }) async {
    final model = await settings.getModel();
    final sampling = WorldWorkshopBuilder.workshopExportSampling(
      await settings.getSampling(),
    );
    final baseUrl = await settings.getApiBaseUrl();
    final raw = await nanoGpt.complete(
      model: model,
      messages: _builder.buildWorldOverviewMessages(
        conversation: workshop.messages,
        worldSummary: workshop.worldSummary,
        importedSource: workshop.importedSource,
        sourceLorebook: sourceLorebook,
        canonPinMessageIds: workshop.canonPinMessageIds,
      ),
      baseUrl: baseUrl,
      sampling: sampling,
    );
    return raw.trim();
  }

  Future<List<String>> aiChecklist({
    required WorldWorkshop workshop,
    required NanoGptService nanoGpt,
    required SettingsService settings,
    Lorebook? sourceLorebook,
  }) async {
    final model = await settings.getModel();
    final sampling = WorldWorkshopBuilder.workshopExportSampling(
      await settings.getSampling(),
    );
    final baseUrl = await settings.getApiBaseUrl();
    final raw = await nanoGpt.complete(
      model: model,
      messages: _builder.buildPreExportChecklistMessages(
        conversation: workshop.messages,
        importedSource: workshop.importedSource,
        sourceLorebook: sourceLorebook,
        worldSummary: workshop.worldSummary,
        canonPinMessageIds: workshop.canonPinMessageIds,
      ),
      baseUrl: baseUrl,
      sampling: sampling,
    );
    return _builder.parseChecklistJson(raw);
  }

  Future<List<GlossaryEntry>> extractGlossary({
    required WorldWorkshop workshop,
    required NanoGptService nanoGpt,
    required SettingsService settings,
    Lorebook? sourceLorebook,
  }) async {
    final model = await settings.getModel();
    final sampling = WorldWorkshopBuilder.workshopExportSampling(
      await settings.getSampling(),
    );
    final baseUrl = await settings.getApiBaseUrl();
    final raw = await nanoGpt.complete(
      model: model,
      messages: _builder.buildGlossaryExportMessages(
        conversation: workshop.messages,
        importedSource: workshop.importedSource,
        sourceLorebook: sourceLorebook,
        canonPinMessageIds: workshop.canonPinMessageIds,
      ),
      baseUrl: baseUrl,
      sampling: sampling,
    );
    return _builder.parseGlossaryJson(raw);
  }

  Lorebook mergeGlossaryIntoBook(Lorebook book, List<GlossaryEntry> entries) {
    final existing = List<LorebookEntry>.from(book.entries);
    var order = existing.isEmpty
        ? 100
        : existing.map((e) => e.insertionOrder).reduce((a, b) => a > b ? a : b);
    for (final g in entries) {
      order += 10;
      existing.add(
        LorebookEntry(
          name: g.term,
          keys: g.keywords,
          content: g.definition,
          insertionOrder: order,
        ),
      );
    }
    return book.copyWith(entries: existing);
  }

  Future<List<WorkshopSceneIdea>> generateSceneIdeas({
    required WorldWorkshop workshop,
    required NanoGptService nanoGpt,
    required SettingsService settings,
  }) async {
    final model = await settings.getModel();
    final sampling = WorldWorkshopBuilder.workshopExportSampling(
      await settings.getSampling(),
    );
    final baseUrl = await settings.getApiBaseUrl();
    final raw = await nanoGpt.complete(
      model: model,
      messages: _builder.buildSceneIdeasMessages(
        conversation: workshop.messages,
        importedSource: workshop.importedSource,
      ),
      baseUrl: baseUrl,
      sampling: sampling,
    );
    return _builder.parseSceneIdeasJson(raw);
  }

  Future<(List<WorkshopLocation>, List<WorkshopRelationship>)> extractSheets({
    required WorldWorkshop workshop,
    required NanoGptService nanoGpt,
    required SettingsService settings,
  }) async {
    final model = await settings.getModel();
    final sampling = WorldWorkshopBuilder.workshopExportSampling(
      await settings.getSampling(),
    );
    final baseUrl = await settings.getApiBaseUrl();
    final raw = await nanoGpt.complete(
      model: model,
      messages: _builder.buildSheetsExtractMessages(
        conversation: workshop.messages,
        importedSource: workshop.importedSource,
      ),
      baseUrl: baseUrl,
      sampling: sampling,
    );
    return _builder.parseSheetsJson(raw);
  }

  Future<List<String>> generateGreetings({
    required WorldWorkshop workshop,
    required String characterName,
    required NanoGptService nanoGpt,
    required SettingsService settings,
    Lorebook? sourceLorebook,
  }) async {
    final model = await settings.getModel();
    final sampling = WorldWorkshopBuilder.workshopExportSampling(
      await settings.getSampling(),
    );
    final baseUrl = await settings.getApiBaseUrl();
    final raw = await nanoGpt.complete(
      model: model,
      messages: _builder.buildGreetingsExportMessages(
        conversation: workshop.messages,
        characterName: characterName,
        importedSource: workshop.importedSource,
        sourceLorebook: sourceLorebook,
      ),
      baseUrl: baseUrl,
      sampling: sampling,
    );
    return _builder.parseGreetingsJson(raw);
  }

  Future<void> exportBundleFile({
    required BuildContext context,
    required WorldWorkshop workshop,
    GlobalLorebook? lorebook,
    List<Character> characters = const [],
    Persona? persona,
  }) async {
    final bundle = _hub.exportBundle(
      workshop: workshop,
      lorebook: lorebook,
      characters: characters,
      persona: persona,
    );
    final text = _hub.encodeBundle(bundle);
    final dir = await getApplicationDocumentsDirectory();
    final safeTitle = workshop.title
        .replaceAll(RegExp(r'[^\w\s-]'), '')
        .trim()
        .replaceAll(RegExp(r'\s+'), '_');
    final file = File(
      '${dir.path}/anima_world_${safeTitle.isEmpty ? workshop.id : safeTitle}.json',
    );
    await file.writeAsString(text);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        text: 'Anima world bundle',
      ),
    );
  }

  Future<WorkshopBundleImport?> importBundleFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['json'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;
    final file = result.files.first;
    var bytes = file.bytes;
    if (bytes == null && file.path != null) {
      bytes = await File(file.path!).readAsBytes();
    }
    if (bytes == null) {
      throw const FormatException('Could not read bundle file.');
    }
    return _hub.parseBundle(utf8.decode(bytes));
  }

  Future<PlayWorldPlan> playPlan({
    required WorldWorkshop workshop,
    required List<Character> allCharacters,
    required Persona? defaultPersona,
    GlobalLorebook? linkedLorebook,
  }) {
    return _hub.buildPlayWorldPlan(
      workshop: workshop,
      allCharacters: allCharacters,
      defaultPersona: defaultPersona,
      linkedLorebook: linkedLorebook,
    );
  }

  Future<WorldWorkshop?> refreshWorkshopSource({
    required WorldWorkshop workshop,
    required ChatSession chat,
    required List<Character> characters,
    Persona? persona,
    List<GlobalLorebook> linkedLorebooks = const [],
  }) async {
    final source = _hub.refreshSourceFromChat(
      workshop: workshop,
      chat: chat,
      characters: characters,
      persona: persona,
      linkedLorebooks: linkedLorebooks,
      options: WorkshopChatImportOptions.defaults,
    );
    if (source == null || !source.hasContent) return null;
    return workshop.copyWith(importedSource: source);
  }
}
