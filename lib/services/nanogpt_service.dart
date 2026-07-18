import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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

/// One image model from NanoGPT's image-model catalog.
class NanoGptImageModelInfo {
  const NanoGptImageModelInfo({
    required this.id,
    required this.ownedBy,
    required this.name,
    this.resolutions = const [],
    this.nsfw = false,
    this.supportsGeneration = true,
    this.subscriptionIncluded = false,
    this.pricePerImageUsd,
  });

  final String id;
  final String ownedBy;
  final String name;
  final List<String> resolutions;
  final bool nsfw;
  final bool supportsGeneration;

  /// True when loaded from NanoGPT's subscription image catalog.
  final bool subscriptionIncluded;

  /// Cheapest public per-image USD price when NanoGPT provides pricing.
  final double? pricePerImageUsd;

  String get displayName => name.trim().isEmpty ? id : name.trim();

  /// Prefer a square size when the model lists one.
  String? get preferredSquareResolution {
    for (final value in resolutions) {
      final lower = value.toLowerCase();
      if (lower == '1024x1024' || lower == '1024*1024') return '1024x1024';
      if (lower == 'square' || lower == 'square_hd') return value;
    }
    for (final value in resolutions) {
      final parts = value.toLowerCase().split(RegExp(r'[x*]'));
      if (parts.length == 2 && parts[0] == parts[1]) return value;
    }
    return resolutions.isEmpty ? null : resolutions.first;
  }
}

/// Bytes returned from a successful image generation.
class NanoGptGeneratedImage {
  const NanoGptGeneratedImage({
    required this.bytes,
    this.mimeType = 'image/png',
  });

  final Uint8List bytes;
  final String mimeType;

  String get fileExtension {
    final mime = mimeType.toLowerCase();
    if (mime.contains('jpeg') || mime.contains('jpg')) return '.jpg';
    if (mime.contains('webp')) return '.webp';
    return '.png';
  }
}

/// One allowance window returned by NanoGPT subscription usage.
class NanoGptUsageWindow {
  const NanoGptUsageWindow({
    required this.used,
    required this.remaining,
    required this.limit,
    this.resetAt,
  });

  final double used;
  final double remaining;
  final double limit;
  final DateTime? resetAt;

  double get percentUsed => limit <= 0 ? 0 : (used / limit).clamp(0, 1);
}

/// Wallet and subscription credit information for the saved NanoGPT key.
class NanoGptCredits {
  const NanoGptCredits({
    this.usdBalance,
    this.nanoBalance,
    this.subscriptionActive = false,
    this.subscriptionState = '',
    this.weeklyTokens,
    this.dailyTokens,
    this.dailyImages,
    this.monthlyUsage,
    this.currentPeriodEnd,
    this.balanceUnavailable = false,
    this.subscriptionUnavailable = false,
  });

  final double? usdBalance;
  final double? nanoBalance;
  final bool subscriptionActive;
  final String subscriptionState;
  final NanoGptUsageWindow? weeklyTokens;
  final NanoGptUsageWindow? dailyTokens;
  final NanoGptUsageWindow? dailyImages;
  final NanoGptUsageWindow? monthlyUsage;
  final DateTime? currentPeriodEnd;
  final bool balanceUnavailable;
  final bool subscriptionUnavailable;
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

  /// Loads wallet dollars and subscription allowance usage for the saved key.
  ///
  /// NanoGPT currently exposes these from two endpoints. A missing/inactive
  /// subscription does not prevent the wallet balance from being displayed.
  Future<NanoGptCredits> getCredits() async {
    final apiKey = await _apiKeyService.getApiKey();
    if (apiKey == null) {
      throw NanoGptException(
        'Add your NanoGPT API key in Settings before checking credits.',
      );
    }

    final headers = <String, String>{
      'Accept': 'application/json',
      'Authorization': 'Bearer $apiKey',
      'x-api-key': apiKey,
    };

    late final List<http.Response> responses;
    try {
      responses = await Future.wait([
        _http
            .post(
              Uri.parse('https://nano-gpt.com/api/check-balance'),
              headers: headers,
            )
            .timeout(const Duration(seconds: 30)),
        _http
            .get(
              Uri.parse('https://nano-gpt.com/api/subscription/v1/usage'),
              headers: headers,
            )
            .timeout(const Duration(seconds: 30)),
      ]);
    } on SocketException {
      throw NanoGptException(
        'Could not reach NanoGPT to check credits. Check your internet.',
      );
    } on TimeoutException {
      throw NanoGptException(
        'Checking NanoGPT credits took too long. Try again.',
      );
    } on http.ClientException {
      throw NanoGptException(
        'Could not reach NanoGPT to check credits. Check your internet.',
      );
    }

    final balanceResponse = responses[0];
    final subscriptionResponse = responses[1];
    if (balanceResponse.statusCode == 401 ||
        subscriptionResponse.statusCode == 401) {
      throw NanoGptException(
        'NanoGPT rejected the API key. Check the saved key in Settings.',
      );
    }

    Map<String, dynamic>? balance;
    Map<String, dynamic>? subscription;
    if (_isSuccess(balanceResponse.statusCode)) {
      balance = _decodeJsonMap(balanceResponse.body);
    }
    if (_isSuccess(subscriptionResponse.statusCode)) {
      subscription = _decodeJsonMap(subscriptionResponse.body);
    }
    if (balance == null && subscription == null) {
      throw NanoGptException(
        'NanoGPT could not return credit information right now.',
      );
    }

    final limits = _mapAt(subscription, 'limits');
    return NanoGptCredits(
      usdBalance: _numberAt(balance, 'usd_balance'),
      nanoBalance: _numberAt(balance, 'nano_balance'),
      subscriptionActive: subscription?['active'] == true,
      subscriptionState: '${subscription?['state'] ?? ''}'.trim(),
      weeklyTokens: _usageWindow(
        subscription,
        'weeklyInputTokens',
        limit: _numberAt(limits, 'weeklyInputTokens'),
      ),
      dailyTokens:
          _usageWindow(
            subscription,
            'dailyInputTokens',
            limit: _numberAt(limits, 'dailyInputTokens'),
          ) ??
          _usageWindow(
            subscription,
            'daily',
            limit: _numberAt(limits, 'daily'),
          ),
      dailyImages: _usageWindow(
        subscription,
        'dailyImages',
        limit: _numberAt(limits, 'dailyImages'),
      ),
      // Supports NanoGPT's documented generic daily/monthly response too.
      monthlyUsage: _usageWindow(
        subscription,
        'monthly',
        limit: _numberAt(limits, 'monthly'),
      ),
      currentPeriodEnd: _dateValue(
        _mapAt(subscription, 'period')?['currentPeriodEnd'],
      ),
      balanceUnavailable: balance == null,
      subscriptionUnavailable: subscription == null,
    );
  }

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

  /// Live image-model catalog for avatar generation.
  ///
  /// When [subscriptionOnly] is true, uses NanoGPT's subscription image
  /// catalog (`GET /api/subscription/v1/image-models`) so only models that
  /// draw from subscription image allowance are listed.
  ///
  /// Otherwise loads the full public catalog and marks models that also
  /// appear in the subscription catalog.
  Future<List<NanoGptImageModelInfo>> listImageModels({
    bool subscriptionOnly = false,
  }) async {
    final apiKey = await _apiKeyService.getApiKey();
    final headers = <String, String>{
      'Accept': 'application/json',
    };
    if (apiKey != null) {
      headers['Authorization'] = 'Bearer $apiKey';
      headers['x-api-key'] = apiKey;
    }

    if (subscriptionOnly) {
      return _fetchImageModels(
        uri: Uri.parse('https://nano-gpt.com/api/subscription/v1/image-models'),
        headers: headers,
        subscriptionIncluded: true,
      );
    }

    // Full catalog + subscription ids for Paid / Included labels.
    Set<String> includedIds = {};
    try {
      final included = await _fetchImageModels(
        uri: Uri.parse('https://nano-gpt.com/api/subscription/v1/image-models'),
        headers: headers,
        subscriptionIncluded: true,
      );
      includedIds = {for (final m in included) m.id};
    } catch (_) {
      // Labels degrade gracefully if the subscription catalog is unavailable.
    }

    NanoGptException? lastError;
    for (final uri in [
      Uri.parse('https://nano-gpt.com/api/v1/images/models'),
      Uri.parse('https://nano-gpt.com/api/v1/image-models')
          .replace(queryParameters: const {'detailed': 'true'}),
    ]) {
      try {
        final models = await _fetchImageModels(
          uri: uri,
          headers: headers,
          subscriptionIncluded: false,
        );
        return [
          for (final model in models)
            NanoGptImageModelInfo(
              id: model.id,
              ownedBy: model.ownedBy,
              name: model.name,
              resolutions: model.resolutions,
              nsfw: model.nsfw,
              supportsGeneration: model.supportsGeneration,
              subscriptionIncluded: includedIds.contains(model.id),
              pricePerImageUsd: model.pricePerImageUsd,
            ),
        ];
      } on NanoGptException catch (error) {
        lastError = error;
      }
    }

    throw lastError ??
        NanoGptException('Could not load NanoGPT image models.');
  }

  Future<List<NanoGptImageModelInfo>> _fetchImageModels({
    required Uri uri,
    required Map<String, String> headers,
    required bool subscriptionIncluded,
  }) async {
    late final http.Response response;
    try {
      response = await _http
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 45));
    } on SocketException {
      throw NanoGptException(
        'Could not reach NanoGPT to load image models. Check your internet.',
      );
    } on TimeoutException {
      throw NanoGptException(
        'Loading image models took too long. Try again.',
      );
    } on http.ClientException {
      throw NanoGptException(
        'Could not reach NanoGPT to load image models. Check your internet.',
      );
    }

    if (response.statusCode == 401) {
      throw NanoGptException(
        'NanoGPT rejected the API key while loading image models. Check Settings.',
      );
    }
    if (!_isSuccess(response.statusCode)) {
      throw NanoGptException(
        'Could not load image models (${response.statusCode}). '
        '${_shortBody(response.body)}',
      );
    }
    return _parseImageModels(
      response.body,
      subscriptionIncluded: subscriptionIncluded,
    );
  }

  /// Text-to-image generation via NanoGPT Image API.
  ///
  /// Tries `POST /api/v1/images` first, then the OpenAI-compatible
  /// `POST /api/v1/images/generations` for broader response compatibility.
  Future<NanoGptGeneratedImage> generateImage({
    required String model,
    required String prompt,
    String? resolution,
    bool subscriptionOnly = false,
  }) async {
    final trimmedPrompt = prompt.trim();
    if (trimmedPrompt.isEmpty) {
      throw NanoGptException('Enter a prompt before generating an image.');
    }
    final trimmedModel = model.trim();
    if (trimmedModel.isEmpty) {
      throw NanoGptException('Choose an image model in Settings first.');
    }

    if (subscriptionOnly) {
      final included = await listImageModels(subscriptionOnly: true);
      final allowed = included.any((m) => m.id == trimmedModel);
      if (!allowed) {
        throw NanoGptException(
          '“$trimmedModel” is not on NanoGPT’s subscription image list. '
          'Turn off Use subscription API, or pick a subscription image model.',
        );
      }
    }

    final apiKey = await _apiKeyService.getApiKey();
    if (apiKey == null) {
      throw NanoGptException(
        'Add your NanoGPT API key in Settings before generating images.',
      );
    }

    final headers = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $apiKey',
      'x-api-key': apiKey,
    };

    final size = (resolution == null || resolution.trim().isEmpty)
        ? '1024x1024'
        : resolution.trim();

    // Prefer the dedicated Image API.
    try {
      final body = <String, dynamic>{
        'model': trimmedModel,
        'prompt': trimmedPrompt,
        'n': 1,
        'resolution': size,
      };
      final response = await _http
          .post(
            Uri.parse('https://nano-gpt.com/api/v1/images'),
            headers: headers,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 120));
      if (_isSuccess(response.statusCode)) {
        return await _parseGeneratedImage(response.body);
      }
      // Fall through to OpenAI-compatible route for some models/errors.
      if (response.statusCode == 401) {
        throw NanoGptException(
          'NanoGPT rejected the API key while generating an image. Check Settings.',
        );
      }
      if (response.statusCode == 402) {
        throw NanoGptException(
          'NanoGPT says payment or image allowance is required for this model.',
        );
      }
    } on NanoGptException {
      rethrow;
    } on SocketException {
      throw NanoGptException(
        'Could not reach NanoGPT to generate an image. Check your internet.',
      );
    } on TimeoutException {
      throw NanoGptException(
        'Image generation took too long. Try again.',
      );
    } on http.ClientException {
      throw NanoGptException(
        'Could not reach NanoGPT to generate an image. Check your internet.',
      );
    }

    // OpenAI-compatible fallback.
    try {
      final body = <String, dynamic>{
        'model': trimmedModel,
        'prompt': trimmedPrompt,
        'n': 1,
        'size': size,
        'response_format': 'b64_json',
      };
      final response = await _http
          .post(
            Uri.parse('https://nano-gpt.com/api/v1/images/generations'),
            headers: headers,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 120));
      if (response.statusCode == 401) {
        throw NanoGptException(
          'NanoGPT rejected the API key while generating an image. Check Settings.',
        );
      }
      if (response.statusCode == 402) {
        throw NanoGptException(
          'NanoGPT says payment or image allowance is required for this model.',
        );
      }
      if (!_isSuccess(response.statusCode)) {
        throw NanoGptException(
          'Image generation failed (${response.statusCode}). '
          '${_shortBody(response.body)}',
        );
      }
      return await _parseGeneratedImage(response.body);
    } on NanoGptException {
      rethrow;
    } on SocketException {
      throw NanoGptException(
        'Could not reach NanoGPT to generate an image. Check your internet.',
      );
    } on TimeoutException {
      throw NanoGptException(
        'Image generation took too long. Try again.',
      );
    } on http.ClientException {
      throw NanoGptException(
        'Could not reach NanoGPT to generate an image. Check your internet.',
      );
    }
  }

  List<NanoGptImageModelInfo> _parseImageModels(
    String body, {
    bool subscriptionIncluded = false,
  }) {
    final decoded = jsonDecode(body);
    if (decoded is! Map) {
      throw NanoGptException('NanoGPT returned an unexpected image models list.');
    }
    final data = decoded['data'];
    if (data is! List) {
      throw NanoGptException('NanoGPT returned an unexpected image models list.');
    }

    final models = <NanoGptImageModelInfo>[];
    final seen = <String>{};
    for (final item in data) {
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);
      final id = '${map['id'] ?? ''}'.trim();
      if (id.isEmpty || !seen.add(id)) continue;

      final capabilities = map['capabilities'];
      final caps = capabilities is Map
          ? Map<String, dynamic>.from(capabilities)
          : const <String, dynamic>{};
      final supportsGeneration = caps['image_generation'] != false;
      if (!supportsGeneration) continue;

      final params = map['supported_parameters'];
      final paramMap = params is Map
          ? Map<String, dynamic>.from(params)
          : const <String, dynamic>{};
      final resolutions = <String>[];
      void addResolutions(Object? raw) {
        if (raw is List) {
          for (final value in raw) {
            final text = '$value'.trim();
            if (text.isNotEmpty) resolutions.add(text);
          }
        } else if (raw is Map) {
          final values = raw['values'];
          if (values is List) {
            for (final value in values) {
              final text = '$value'.trim();
              if (text.isNotEmpty) resolutions.add(text);
            }
          }
        }
      }

      addResolutions(paramMap['resolutions']);
      addResolutions(paramMap['resolution']);

      final ownedBy = '${map['owned_by'] ?? 'other'}'.trim();
      final name = '${map['name'] ?? ''}'.trim();
      models.add(
        NanoGptImageModelInfo(
          id: id,
          ownedBy: ownedBy.isEmpty ? 'other' : ownedBy,
          name: name.isEmpty ? id : name,
          resolutions: resolutions,
          nsfw: caps['nsfw'] == true,
          supportsGeneration: supportsGeneration,
          subscriptionIncluded: subscriptionIncluded,
          pricePerImageUsd: _cheapestImagePriceUsd(map['pricing']),
        ),
      );
    }

    models.sort((a, b) {
      // Subscription-included models first when the full catalog is shown.
      if (a.subscriptionIncluded != b.subscriptionIncluded) {
        return a.subscriptionIncluded ? -1 : 1;
      }
      final byOwner = a.ownedBy.toLowerCase().compareTo(b.ownedBy.toLowerCase());
      if (byOwner != 0) return byOwner;
      return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
    });
    return models;
  }

  double? _cheapestImagePriceUsd(Object? pricing) {
    if (pricing is! Map) return null;
    final nums = <double>[];
    void walk(Object? value) {
      if (value is num) {
        nums.add(value.toDouble());
      } else if (value is Map) {
        for (final child in value.values) {
          walk(child);
        }
      } else if (value is List) {
        for (final child in value) {
          walk(child);
        }
      }
    }

    walk(pricing);
    if (nums.isEmpty) return null;
    nums.sort();
    return nums.first;
  }

  Future<NanoGptGeneratedImage> _parseGeneratedImage(String body) async {
    late final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } catch (_) {
      throw NanoGptException('NanoGPT returned an unreadable image response.');
    }
    if (decoded is! Map) {
      throw NanoGptException('NanoGPT returned an unexpected image response.');
    }
    final map = Map<String, dynamic>.from(decoded);

    // OpenAI-style: data: [{ b64_json / url }]
    final data = map['data'];
    if (data is List && data.isNotEmpty) {
      final first = data.first;
      if (first is Map) {
        final item = Map<String, dynamic>.from(first);
        final b64 = '${item['b64_json'] ?? item['b64'] ?? ''}'.trim();
        if (b64.isNotEmpty) {
          return NanoGptGeneratedImage(
            bytes: Uint8List.fromList(base64Decode(_stripDataUrl(b64))),
            mimeType: _mimeFromDataUrl(b64) ?? 'image/png',
          );
        }
        final url = '${item['url'] ?? ''}'.trim();
        if (url.isNotEmpty) {
          return _downloadImage(url);
        }
      }
    }

    // Alternate shapes: images / output / result
    for (final key in ['images', 'output', 'result']) {
      final value = map[key];
      if (value is String && value.trim().isNotEmpty) {
        final text = value.trim();
        if (text.startsWith('http')) {
          return _downloadImage(text);
        }
        return NanoGptGeneratedImage(
          bytes: Uint8List.fromList(base64Decode(_stripDataUrl(text))),
          mimeType: _mimeFromDataUrl(text) ?? 'image/png',
        );
      }
      if (value is List && value.isNotEmpty) {
        final first = value.first;
        if (first is String && first.trim().isNotEmpty) {
          final text = first.trim();
          if (text.startsWith('http')) {
            return _downloadImage(text);
          }
          return NanoGptGeneratedImage(
            bytes: Uint8List.fromList(base64Decode(_stripDataUrl(text))),
            mimeType: _mimeFromDataUrl(text) ?? 'image/png',
          );
        }
        if (first is Map) {
          final item = Map<String, dynamic>.from(first);
          final b64 = '${item['b64_json'] ?? item['b64'] ?? item['base64'] ?? ''}'
              .trim();
          if (b64.isNotEmpty) {
            return NanoGptGeneratedImage(
              bytes: Uint8List.fromList(base64Decode(_stripDataUrl(b64))),
              mimeType: _mimeFromDataUrl(b64) ?? 'image/png',
            );
          }
          final url = '${item['url'] ?? ''}'.trim();
          if (url.isNotEmpty) return _downloadImage(url);
        }
      }
    }

    throw NanoGptException(
      'NanoGPT returned no image data. Try another image model.',
    );
  }

  Future<NanoGptGeneratedImage> _downloadImage(String url) async {
    try {
      final response = await _http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 60));
      if (!_isSuccess(response.statusCode) || response.bodyBytes.isEmpty) {
        throw NanoGptException(
          'Could not download the generated image from NanoGPT.',
        );
      }
      final contentType = response.headers['content-type'] ?? 'image/png';
      return NanoGptGeneratedImage(
        bytes: response.bodyBytes,
        mimeType: contentType.split(';').first.trim(),
      );
    } on NanoGptException {
      rethrow;
    } catch (_) {
      throw NanoGptException(
        'Could not download the generated image from NanoGPT.',
      );
    }
  }

  String _stripDataUrl(String value) {
    final comma = value.indexOf(',');
    if (value.startsWith('data:') && comma > 0) {
      return value.substring(comma + 1).trim();
    }
    return value.trim();
  }

  String? _mimeFromDataUrl(String value) {
    if (!value.startsWith('data:')) return null;
    final semi = value.indexOf(';');
    if (semi <= 5) return null;
    return value.substring(5, semi).trim();
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

  bool _isSuccess(int statusCode) =>
      statusCode >= 200 && statusCode < 300;

  Map<String, dynamic>? _decodeJsonMap(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      // Treat malformed optional credit data as unavailable.
    }
    return null;
  }

  Map<String, dynamic>? _mapAt(
    Map<String, dynamic>? source,
    String key,
  ) {
    final value = source?[key];
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }

  double? _numberAt(Map<String, dynamic>? source, String key) {
    final value = source?[key];
    if (value is num) return value.toDouble();
    return double.tryParse('$value');
  }

  NanoGptUsageWindow? _usageWindow(
    Map<String, dynamic>? source,
    String key, {
    double? limit,
  }) {
    final window = _mapAt(source, key);
    if (window == null) return null;
    final used = _numberAt(window, 'used') ?? 0;
    final explicitRemaining = _numberAt(window, 'remaining');
    final explicitLimit = _numberAt(window, 'limit') ?? limit;
    final resolvedLimit =
        explicitLimit ?? (explicitRemaining == null ? 0 : used + explicitRemaining);
    final remaining =
        explicitRemaining ?? (resolvedLimit - used).clamp(0, double.infinity);
    return NanoGptUsageWindow(
      used: used,
      remaining: remaining,
      limit: resolvedLimit,
      resetAt: _dateValue(window['resetAt']),
    );
  }

  DateTime? _dateValue(Object? value) {
    if (value is num) {
      return DateTime.fromMillisecondsSinceEpoch(value.toInt(), isUtc: true);
    }
    final raw = '${value ?? ''}'.trim();
    if (raw.isEmpty) return null;
    final epoch = int.tryParse(raw);
    if (epoch != null) {
      return DateTime.fromMillisecondsSinceEpoch(epoch, isUtc: true);
    }
    return DateTime.tryParse(raw);
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
