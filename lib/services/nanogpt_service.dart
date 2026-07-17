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

  /// Sends one user message and returns the assistant's reply text.
  ///
  /// [model] is a NanoGPT model id, e.g. "openai/gpt-4o-mini".
  /// [systemPrompt] is optional personality / character instructions.
  /// [priorMessages] are earlier turns in this chat (user + assistant only).
  Future<String> sendChatMessage({
    required String userMessage,
    required String model,
    String? systemPrompt,
    List<Map<String, String>> priorMessages = const [],
  }) async {
    final apiKey = await _apiKeyService.getApiKey();
    if (apiKey == null) {
      throw NanoGptException(
        'No NanoGPT API key saved yet. Open Settings and paste your key first.',
      );
    }

    final messages = <Map<String, String>>[
      if (systemPrompt != null && systemPrompt.trim().isNotEmpty)
        {'role': 'system', 'content': systemPrompt.trim()},
      ...priorMessages,
      {'role': 'user', 'content': userMessage},
    ];

    final uri = Uri.parse('$baseUrl/chat/completions');

    late final http.Response response;
    try {
      response = await _http
          .post(
            uri,
            headers: {
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({
              'model': model,
              'messages': messages,
              'stream': false,
            }),
          )
          .timeout(const Duration(seconds: 90));
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
      throw NanoGptException(
        'NanoGPT returned an error (${response.statusCode}). '
        'If this keeps happening, try a different model name in Settings.\n\n'
        '${_shortBody(response.body)}',
      );
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final choices = decoded['choices'] as List<dynamic>?;
    if (choices == null || choices.isEmpty) {
      throw NanoGptException('NanoGPT returned an empty reply. Try again.');
    }

    final message = choices.first['message'] as Map<String, dynamic>?;
    final content = message?['content'];
    if (content is! String || content.trim().isEmpty) {
      throw NanoGptException('NanoGPT returned an empty reply. Try again.');
    }

    return content.trim();
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
