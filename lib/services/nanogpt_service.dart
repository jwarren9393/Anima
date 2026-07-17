import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_key_service.dart';

/// Talks to the NanoGPT chat API (OpenAI-compatible).
///
/// Docs: https://docs.nano-gpt.com/api-reference/endpoint/chat-completion
///
/// This is a thin starter. Streaming and character prompts come in later phases.
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
  Future<String> sendChatMessage({
    required String userMessage,
    required String model,
    String? systemPrompt,
    List<Map<String, String>> priorMessages = const [],
  }) async {
    final apiKey = await _apiKeyService.getApiKey();
    if (apiKey == null) {
      throw StateError(
        'No NanoGPT API key saved. Open Settings and paste your key first.',
      );
    }

    final messages = <Map<String, String>>[
      if (systemPrompt != null && systemPrompt.trim().isNotEmpty)
        {'role': 'system', 'content': systemPrompt.trim()},
      ...priorMessages,
      {'role': 'user', 'content': userMessage},
    ];

    final uri = Uri.parse('$baseUrl/chat/completions');
    final response = await _http.post(
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
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        'NanoGPT request failed (${response.statusCode}): ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final choices = decoded['choices'] as List<dynamic>?;
    if (choices == null || choices.isEmpty) {
      throw StateError('NanoGPT returned no choices: ${response.body}');
    }

    final message = choices.first['message'] as Map<String, dynamic>?;
    final content = message?['content'] as String?;
    if (content == null || content.isEmpty) {
      throw StateError('NanoGPT returned an empty message: ${response.body}');
    }

    return content;
  }

  void dispose() {
    _http.close();
  }
}
