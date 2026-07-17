import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'api_key_service.dart';
import 'settings_service.dart';

/// One text model from NanoGPT's `/models` catalog.
class NanoGptModelInfo {
  const NanoGptModelInfo({
    required this.id,
    required this.ownedBy,
    required this.name,
  });

  /// Value sent as `model` on chat completions.
  final String id;

  /// Provider / org (e.g. `anthropic`, `meta`) — from `owned_by`.
  final String ownedBy;

  /// Human-friendly label when NanoGPT provides one.
  final String name;

  String get displayName => name.trim().isEmpty ? id : name.trim();

  /// NanoGPT's automatic router models (`auto-model`, etc.).
  static bool isAutoModelId(String id) {
    final lower = id.trim().toLowerCase();
    return lower == 'auto-model' || lower.startsWith('auto-model-');
  }
}

/// Talks to the NanoGPT chat API (OpenAI-compatible).
///
/// Docs: https://docs.nano-gpt.com/api-reference/endpoint/chat-completion
class NanoGptService {
  NanoGptService({
    required this._apiKeyService,
    http.Client? httpClient,
    this.defaultBaseUrl = SettingsService.defaultBaseUrl,
  }) : _http = httpClient ?? http.Client();

  final ApiKeyService _apiKeyService;
  final http.Client _http;
  final String defaultBaseUrl;

  /// Provider label shown first in the model catalog for Auto Model.
  static const autoProviderLabel = 'Auto';

  /// Fallback Auto entries if the catalog omits them.
  static const List<NanoGptModelInfo> autoModelFallbacks = [
    NanoGptModelInfo(
      id: 'auto-model',
      ownedBy: autoProviderLabel,
      name: 'Auto model',
    ),
    NanoGptModelInfo(
      id: 'auto-model-basic',
      ownedBy: autoProviderLabel,
      name: 'Auto model (Basic)',
    ),
    NanoGptModelInfo(
      id: 'auto-model-standard',
      ownedBy: autoProviderLabel,
      name: 'Auto model (Standard)',
    ),
    NanoGptModelInfo(
      id: 'auto-model-premium',
      ownedBy: autoProviderLabel,
      name: 'Auto model (Premium)',
    ),
  ];

  /// Client used for the in-flight stream — closed by [cancelActiveStream].
  http.Client? _streamClient;
  bool _cancelRequested = false;

  /// Fetches available text models, optionally from the subscription catalog.
  ///
  /// Uses `GET …/models?detailed=true` so we get display names + `owned_by`.
  Future<List<NanoGptModelInfo>> listModels({String? baseUrl}) async {
    final root =
        (baseUrl ?? defaultBaseUrl).trim().replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse('$root/models').replace(
      queryParameters: const {'detailed': 'true'},
    );

    final headers = <String, String>{
      'Accept': 'application/json',
    };
    final apiKey = await _apiKeyService.getApiKey();
    if (apiKey != null) {
      headers['Authorization'] = 'Bearer $apiKey';
    }

    late final http.Response response;
    try {
      response = await _http
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 45));
    } on SocketException {
      throw NanoGptException(
        'Could not reach NanoGPT to load models. Check your internet and try again.',
      );
    } on TimeoutException {
      throw NanoGptException(
        'Loading models took too long. Try again in a moment.',
      );
    } on http.ClientException {
      throw NanoGptException(
        'Could not reach NanoGPT to load models. Check your internet and try again.',
      );
    }

    if (response.statusCode == 401) {
      throw NanoGptException(
        'NanoGPT rejected the API key while loading models. Check Settings.',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw NanoGptException(
        'Could not load NanoGPT models (${response.statusCode}). '
        '${_shortBody(response.body)}',
      );
    }

    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        throw NanoGptException('NanoGPT returned an unexpected models list.');
      }
      final data = decoded['data'];
      if (data is! List) {
        throw NanoGptException('NanoGPT returned an unexpected models list.');
      }

      final models = <NanoGptModelInfo>[];
      final seenIds = <String>{};
      for (final item in data) {
        if (item is! Map) continue;
        final map = Map<String, dynamic>.from(item);
        final id = '${map['id'] ?? ''}'.trim();
        if (id.isEmpty || !seenIds.add(id)) continue;
        final rawOwner = '${map['owned_by'] ?? 'other'}'.trim();
        final name = '${map['name'] ?? ''}'.trim();
        // Surface NanoGPT Auto Model under its own "Auto" provider (top of list).
        final ownedBy = NanoGptModelInfo.isAutoModelId(id)
            ? autoProviderLabel
            : (rawOwner.isEmpty ? 'other' : rawOwner);
        models.add(
          NanoGptModelInfo(
            id: id,
            ownedBy: ownedBy,
            name: name.isEmpty ? id : name,
          ),
        );
      }

      for (final fallback in autoModelFallbacks) {
        if (seenIds.add(fallback.id)) {
          models.add(fallback);
        }
      }

      models.sort((a, b) {
        final byOwner = _compareProviders(a.ownedBy, b.ownedBy);
        if (byOwner != 0) return byOwner;
        return a.displayName
            .toLowerCase()
            .compareTo(b.displayName.toLowerCase());
      });
      return models;
    } on NanoGptException {
      rethrow;
    } catch (error) {
      throw NanoGptException('Could not read the NanoGPT models list: $error');
    }
  }

  /// Abort the current streaming reply (if any). Safe to call when idle.
  void cancelActiveStream() {
    _cancelRequested = true;
    final client = _streamClient;
    _streamClient = null;
    client?.close();
  }

  /// Streams an assistant reply as plain text chunks (SillyTavern-style live typing).
  ///
  /// [messages] should already include optional system + conversation turns.
  /// Call [cancelActiveStream] to stop mid-reply.
  Stream<String> streamCompletion({
    required String model,
    required List<Map<String, String>> messages,
    String? baseUrl,
    SamplingSettings sampling = const SamplingSettings(),
  }) async* {
    final apiKey = await _apiKeyService.getApiKey();
    if (apiKey == null) {
      throw NanoGptException(
        'No NanoGPT API key saved yet. Open Settings and paste your key first.',
      );
    }
    if (messages.isEmpty) {
      throw NanoGptException('Nothing to send to NanoGPT yet.');
    }

    final root =
        (baseUrl ?? defaultBaseUrl).trim().replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse('$root/chat/completions');

    final body = <String, dynamic>{
      'model': model,
      'messages': messages,
      'stream': true,
      ...sampling.toApiBody(),
    };

    final request = http.Request('POST', uri)
      ..headers.addAll({
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
        'Accept': 'text/event-stream',
      })
      ..body = jsonEncode(body);

    // Dedicated client so Stop can close only this request.
    cancelActiveStream();
    _cancelRequested = false;
    final streamClient = http.Client();
    _streamClient = streamClient;

    late final http.StreamedResponse response;
    try {
      response =
          await streamClient.send(request).timeout(const Duration(seconds: 90));
    } on SocketException {
      _clearStreamClient(streamClient);
      if (_cancelRequested) throw NanoGptCancelledException();
      throw NanoGptException(
        'Could not reach NanoGPT. Check your internet connection and try again.',
      );
    } on TimeoutException {
      _clearStreamClient(streamClient);
      if (_cancelRequested) throw NanoGptCancelledException();
      throw NanoGptException(
        'NanoGPT took too long to reply. Try again in a moment.',
      );
    } on http.ClientException {
      _clearStreamClient(streamClient);
      if (_cancelRequested) throw NanoGptCancelledException();
      throw NanoGptException(
        'Could not reach NanoGPT. Check your internet connection and try again.',
      );
    } on NanoGptException {
      _clearStreamClient(streamClient);
      rethrow;
    } on Exception catch (error) {
      _clearStreamClient(streamClient);
      if (_cancelRequested) throw NanoGptCancelledException();
      throw NanoGptException(
        'Something went wrong while contacting NanoGPT: $error',
      );
    }

    if (_cancelRequested) {
      _clearStreamClient(streamClient);
      throw NanoGptCancelledException();
    }

    if (response.statusCode == 401) {
      _clearStreamClient(streamClient);
      throw NanoGptException(
        'NanoGPT rejected the API key. Open Settings and check that it is correct.',
      );
    }
    if (response.statusCode == 402) {
      _clearStreamClient(streamClient);
      throw NanoGptException(
        'NanoGPT says payment is needed. Check your NanoGPT account balance or plan.',
      );
    }
    if (response.statusCode == 429) {
      _clearStreamClient(streamClient);
      throw NanoGptException(
        'Too many requests right now. Wait a moment and try again.',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final errBody = await response.stream.bytesToString();
      _clearStreamClient(streamClient);
      throw NanoGptException(
        'NanoGPT returned an error (${response.statusCode}). '
        'If this keeps happening, try a different model name in Settings.\n\n'
        '${_shortBody(errBody)}',
      );
    }

    var produced = false;
    final buffer = StringBuffer();

    try {
      await for (final chunk in response.stream.transform(utf8.decoder)) {
        if (_cancelRequested) {
          throw NanoGptCancelledException();
        }
        buffer.write(chunk);
        var content = buffer.toString();

        while (true) {
          final sep = content.indexOf('\n');
          if (sep < 0) {
            buffer
              ..clear()
              ..write(content);
            break;
          }
          var line = content.substring(0, sep);
          content = content.substring(sep + 1);
          if (line.endsWith('\r')) {
            line = line.substring(0, line.length - 1);
          }
          if (line.isEmpty) continue;
          if (!line.startsWith('data:')) continue;

          final data = line.substring(5).trimLeft();
          if (data == '[DONE]') {
            return;
          }

          try {
            final decoded = jsonDecode(data);
            if (decoded is! Map) continue;
            final choices = decoded['choices'];
            if (choices is! List || choices.isEmpty) continue;
            final first = choices.first;
            if (first is! Map) continue;
            final delta = first['delta'];
            if (delta is! Map) continue;
            final piece = delta['content'];
            if (piece is String && piece.isNotEmpty) {
              produced = true;
              yield piece;
            }
          } catch (error) {
            if (error is NanoGptCancelledException) rethrow;
            // Ignore malformed SSE lines and keep reading.
          }
        }
      }
    } on NanoGptCancelledException {
      rethrow;
    } on http.ClientException {
      if (_cancelRequested) throw NanoGptCancelledException();
      rethrow;
    } finally {
      _clearStreamClient(streamClient);
    }

    if (_cancelRequested) {
      throw NanoGptCancelledException();
    }
    if (!produced) {
      throw NanoGptException('NanoGPT returned an empty reply. Try again.');
    }
  }

  void _clearStreamClient(http.Client client) {
    if (_streamClient == client) {
      _streamClient = null;
    }
    client.close();
  }

  /// Auto first, then A–Z (case-insensitive).
  static int _compareProviders(String a, String b) {
    if (a == autoProviderLabel && b != autoProviderLabel) return -1;
    if (b == autoProviderLabel && a != autoProviderLabel) return 1;
    return a.toLowerCase().compareTo(b.toLowerCase());
  }

  /// Non-streaming helper kept for simple one-shot calls.
  Future<String> complete({
    required String model,
    required List<Map<String, String>> messages,
    String? baseUrl,
    SamplingSettings sampling = const SamplingSettings(),
  }) async {
    final parts = <String>[];
    await for (final chunk in streamCompletion(
      model: model,
      messages: messages,
      baseUrl: baseUrl,
      sampling: sampling,
    )) {
      parts.add(chunk);
    }
    final text = parts.join().trim();
    if (text.isEmpty) {
      throw NanoGptException('NanoGPT returned an empty reply. Try again.');
    }
    return text;
  }

  String _shortBody(String body) {
    final trimmed = body.trim();
    if (trimmed.length <= 280) return trimmed;
    return '${trimmed.substring(0, 280)}…';
  }

  void dispose() {
    cancelActiveStream();
    _http.close();
  }
}

/// User stopped a streaming reply.
class NanoGptCancelledException implements Exception {
  @override
  String toString() => 'Generation stopped.';
}

/// A plain-English error from NanoGPT or the network.
class NanoGptException implements Exception {
  NanoGptException(this.message);

  final String message;

  @override
  String toString() => message;
}
