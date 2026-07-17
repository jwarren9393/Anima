import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'api_key_service.dart';

/// Talks to the NanoGPT chat API (OpenAI-compatible).
///
/// Docs: https://docs.nano-gpt.com/api-reference/endpoint/chat-completion
class NanoGptService {
  NanoGptService({
    required this._apiKeyService,
    http.Client? httpClient,
    this.baseUrl = 'https://nano-gpt.com/api/v1',
  }) : _http = httpClient ?? http.Client();

  final ApiKeyService _apiKeyService;
  final http.Client _http;
  final String baseUrl;

  /// Streams an assistant reply as plain text chunks (SillyTavern-style live typing).
  ///
  /// [messages] should already include optional system + conversation turns.
  Stream<String> streamCompletion({
    required String model,
    required List<Map<String, String>> messages,
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

    final uri = Uri.parse('$baseUrl/chat/completions');
    final request = http.Request('POST', uri)
      ..headers.addAll({
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
        'Accept': 'text/event-stream',
      })
      ..body = jsonEncode({
        'model': model,
        'messages': messages,
        'stream': true,
      });

    late final http.StreamedResponse response;
    try {
      response = await _http.send(request).timeout(const Duration(seconds: 90));
    } on SocketException {
      throw NanoGptException(
        'Could not reach NanoGPT. Check your internet connection and try again.',
      );
    } on TimeoutException {
      throw NanoGptException(
        'NanoGPT took too long to reply. Try again in a moment.',
      );
    } on http.ClientException {
      throw NanoGptException(
        'Could not reach NanoGPT. Check your internet connection and try again.',
      );
    } on NanoGptException {
      rethrow;
    } on Exception catch (error) {
      throw NanoGptException(
        'Something went wrong while contacting NanoGPT: $error',
      );
    }

    if (response.statusCode == 401) {
      throw NanoGptException(
        'NanoGPT rejected the API key. Open Settings and check that it is correct.',
      );
    }
    if (response.statusCode == 402) {
      throw NanoGptException(
        'NanoGPT says payment is needed. Check your NanoGPT account balance or plan.',
      );
    }
    if (response.statusCode == 429) {
      throw NanoGptException(
        'Too many requests right now. Wait a moment and try again.',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = await response.stream.bytesToString();
      throw NanoGptException(
        'NanoGPT returned an error (${response.statusCode}). '
        'If this keeps happening, try a different model name in Settings.\n\n'
        '${_shortBody(body)}',
      );
    }

    var produced = false;
    final buffer = StringBuffer();

    await for (final chunk in response.stream.transform(utf8.decoder)) {
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
        } catch (_) {
          // Ignore malformed SSE lines and keep reading.
        }
      }
    }

    if (!produced) {
      throw NanoGptException('NanoGPT returned an empty reply. Try again.');
    }
  }

  /// Non-streaming helper kept for simple one-shot calls.
  Future<String> complete({
    required String model,
    required List<Map<String, String>> messages,
  }) async {
    final parts = <String>[];
    await for (final chunk in streamCompletion(model: model, messages: messages)) {
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
    _http.close();
  }
}

/// A plain-English error from NanoGPT or the network.
class NanoGptException implements Exception {
  NanoGptException(this.message);

  final String message;

  @override
  String toString() => message;
}
