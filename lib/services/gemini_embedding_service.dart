import 'dart:convert';

import 'package:http/http.dart' as http;

class GeminiEmbeddingService {
  static const String modelName = 'gemini-embedding-001';
  static const int outputDimensions = 768;

  final String apiKey;

  const GeminiEmbeddingService({required this.apiKey});

  Future<List<double>> embedDocument(String text) {
    return _embed(text: text, taskType: 'RETRIEVAL_DOCUMENT');
  }

  Future<List<double>> embedQuery(String text) {
    return _embed(text: text, taskType: 'RETRIEVAL_QUERY');
  }

  Future<List<double>> _embed({
    required String text,
    required String taskType,
  }) async {
    final safeText = text.trim();

    if (apiKey.trim().isEmpty) {
      throw StateError(
        'Gemini API key is required to generate vector embeddings.',
      );
    }

    if (safeText.isEmpty) {
      throw ArgumentError('Cannot generate an embedding for empty text.');
    }

    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/$modelName:embedContent',
    );

    final response = await http
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'x-goog-api-key': apiKey,
          },
          body: jsonEncode({
            'model': 'models/$modelName',
            'content': {
              'parts': [
                {'text': safeText},
              ],
            },
            'taskType': taskType,
            'outputDimensionality': outputDimensions,
          }),
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Embedding request failed with HTTP ${response.statusCode}.',
      );
    }

    final decoded = jsonDecode(response.body);
    final values = decoded['embedding']?['values'];

    if (values is! List || values.isEmpty) {
      throw Exception('Gemini did not return a usable vector embedding.');
    }

    return values.whereType<num>().map((value) => value.toDouble()).toList();
  }
}
