import 'dart:convert';

import 'package:http/http.dart' as http;

class GeneratedHeritageImage {
  final String base64Data;
  final String mimeType;
  final String promptSummary;
  final bool isFallback;

  const GeneratedHeritageImage({
    required this.base64Data,
    required this.mimeType,
    required this.promptSummary,
    this.isFallback = false,
  });
}

class GeminiImageService {
  final String apiKey;
  final String model;

  GeminiImageService({required this.apiKey, required this.model});

  static final Map<String, GeneratedHeritageImage> _sessionCache = {};

  Future<GeneratedHeritageImage?> generateLocationImage({
    required String placeId,
    required String placeName,
    required String location,
    required String historicalFacts,
    required String story,
    required String languageName,
  }) async {
    final cacheKey = '$placeId-$languageName';
    if (_sessionCache.containsKey(cacheKey)) return _sessionCache[cacheKey];

    if (apiKey.trim().isEmpty) {
      final fallback = _fallbackImage(placeName);
      _sessionCache[cacheKey] = fallback;
      return fallback;
    }

    final prompt = '''Create a respectful educational heritage-tourism illustration for a mobile application.
Place: $placeName
Location: $location
Language selected by user: $languageName
Verified historical context: $historicalFacts
Narrative context: ${story.length > 900 ? story.substring(0, 900) : story}
Requirements: cinematic heritage tourism scene, warm historical colors, realistic lighting, no text, no labels, no logos, no watermarks, no identifiable real people.''';

    try {
      final uri = Uri.parse('https://generativelanguage.googleapis.com/v1beta/interactions');
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json', 'x-goog-api-key': apiKey},
        body: jsonEncode({
          'model': model,
          'input': [{'type': 'text', 'text': prompt}],
        }),
      ).timeout(const Duration(seconds: 60));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        final fallback = _fallbackImage(placeName);
        _sessionCache[cacheKey] = fallback;
        return fallback;
      }

      final imageData = _extractImageData(jsonDecode(response.body));
      if (imageData == null || imageData.base64Data.trim().isEmpty) {
        final fallback = _fallbackImage(placeName);
        _sessionCache[cacheKey] = fallback;
        return fallback;
      }

      final generated = GeneratedHeritageImage(
        base64Data: imageData.base64Data,
        mimeType: imageData.mimeType,
        promptSummary: 'Generated based on your nearby location: $placeName.',
      );
      _sessionCache[cacheKey] = generated;
      return generated;
    } catch (_) {
      final fallback = _fallbackImage(placeName);
      _sessionCache[cacheKey] = fallback;
      return fallback;
    }
  }

  GeneratedHeritageImage _fallbackImage(String placeName) {
    return GeneratedHeritageImage(
      base64Data: '',
      mimeType: 'application/x-heritagebot-fallback',
      promptSummary: 'Local illustrated preview for $placeName.',
      isFallback: true,
    );
  }

  _ImageData? _extractImageData(dynamic value) {
    if (value is Map) {
      final directOutput = value['output_image'] ?? value['outputImage'];
      if (directOutput is Map) {
        final data = directOutput['data'];
        final mimeType = directOutput['mime_type'] ?? directOutput['mimeType'] ?? directOutput['mime'] ?? 'image/png';
        if (data is String && data.trim().isNotEmpty) return _ImageData(base64Data: data, mimeType: mimeType.toString());
      }
      final inlineData = value['inlineData'] ?? value['inline_data'];
      if (inlineData is Map) {
        final data = inlineData['data'];
        final mimeType = inlineData['mimeType'] ?? inlineData['mime_type'] ?? 'image/png';
        if (data is String && data.trim().isNotEmpty) return _ImageData(base64Data: data, mimeType: mimeType.toString());
      }
      final type = value['type'];
      if (type is String && type.toLowerCase().contains('image')) {
        final data = value['data'];
        final mimeType = value['mime_type'] ?? value['mimeType'] ?? value['mime'] ?? 'image/png';
        if (data is String && data.trim().isNotEmpty) return _ImageData(base64Data: data, mimeType: mimeType.toString());
      }
      for (final item in value.values) {
        final found = _extractImageData(item);
        if (found != null) return found;
      }
    }
    if (value is List) {
      for (final item in value) {
        final found = _extractImageData(item);
        if (found != null) return found;
      }
    }
    return null;
  }
}

class _ImageData {
  final String base64Data;
  final String mimeType;
  const _ImageData({required this.base64Data, required this.mimeType});
}
