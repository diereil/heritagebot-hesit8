// HERITAGEBOT - TEST SUPPORT: offline stand-in for Google's Gemini REST API
// (generativelanguage.googleapis.com) for CASE-103..CASE-111.
//
// Like FakeCloudinary, this replaces ONLY what sits outside HeritageBot:
// the HTTP endpoint that the real GeminiEmbeddingService (embedContent) and
// GeminiStoryService (generateContent) call through package:http. It is
// installed with package:http's own runWithClient, so nothing leaves the
// machine.
//
//   * embedContent    -> answers like Gemini: {"embedding":{"values":[...]}}
//                        with a deterministic 768-dimension bag-of-words
//                        vector of the text HeritageBot sent. Texts that
//                        share words get similar vectors, so HeritageBot's
//                        own cosine-similarity ranking can be observed.
//   * generateContent -> records the prompt HeritageBot built and answers
//                        with [narrativeReply] (a canned model reply).
//   * anything else   -> HTTP 404 and recorded in [unexpectedRequests].
//
// The fake never decides what HeritageBot stores, retrieves or shows.
//
// GeminiEmbeddingService / GeminiStoryService read the API key at compile
// time (String.fromEnvironment('GEMINI_API_KEY') in lib/main.dart). These
// tests must therefore be started with the DUMMY key from
// support/unit_091_120_defines.json. If the key is missing - or is anything
// other than the dummy value (e.g. a real key) - the tests are SKIPPED and
// the skip reason says why.

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// The dummy key the tests expect (never a real credential).
const String kDummyGeminiApiKey = 'heritagebot-test-gemini-key';

const String _compiledGeminiKey = String.fromEnvironment('GEMINI_API_KEY');

bool get geminiConfiguredForTest => _compiledGeminiKey == kDummyGeminiApiKey;

/// Skip reason for tests that need HeritageBot's Gemini code paths.
Object get geminiTestSkip => geminiConfiguredForTest
    ? false
    : 'HeritageBot reads GEMINI_API_KEY at compile time. Run with '
          '--dart-define-from-file=test/heritagebot/support/unit_091_120_defines.json '
          '(dummy key "$kDummyGeminiApiKey"; requests go to FakeGeminiApi, '
          'not the internet). Compiled key present: '
          '${_compiledGeminiKey.isNotEmpty} (must equal the dummy value).';

/// Same dimension HeritageBot requests (GeminiEmbeddingService.outputDimensions).
const int kFakeEmbeddingDimensions = 768;

/// Deterministic bag-of-words vector for [text] (FNV-1a hashed words).
List<double> fakeEmbeddingOf(String text) {
  final vector = List<double>.filled(kFakeEmbeddingDimensions, 0);
  for (final word in RegExp(r'[a-z0-9]+').allMatches(text.toLowerCase())) {
    final token = word.group(0)!;
    if (token.length < 3) continue;
    var hash = 0x811c9dc5;
    for (final unit in token.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    vector[hash % kFakeEmbeddingDimensions] += 1;
  }
  return vector;
}

class FakeEmbedRequest {
  FakeEmbedRequest(this.text, this.taskType, this.apiKey, this.values);

  final String text;
  final String taskType; // RETRIEVAL_DOCUMENT / RETRIEVAL_QUERY
  final String apiKey;
  final List<double> values; // the vector returned to HeritageBot

  @override
  String toString() =>
      'FakeEmbedRequest($taskType, ${text.replaceAll('\n', ' | ')})';
}

class FakeGeminiApi {
  final List<FakeEmbedRequest> embedRequests = <FakeEmbedRequest>[];
  final List<String> generatePrompts = <String>[];
  final List<Uri> unexpectedRequests = <Uri>[];

  /// Text the fake model returns for generateContent.
  String narrativeReply =
      'Generated heritage narrative returned by the fake Gemini endpoint.';

  void clear() {
    embedRequests.clear();
    generatePrompts.clear();
    unexpectedRequests.clear();
  }

  http.Client client() => MockClient((http.Request request) async {
    final path = request.url.path;
    if (request.url.host != 'generativelanguage.googleapis.com') {
      unexpectedRequests.add(request.url);
      return http.Response('not found', 404);
    }
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    final apiKey = request.headers['x-goog-api-key'] ?? '';

    if (path.endsWith(':embedContent')) {
      final parts = (body['content']?['parts'] as List?) ?? const [];
      final text = parts.isEmpty ? '' : '${parts.first['text']}';
      final values = fakeEmbeddingOf(text);
      embedRequests.add(
        FakeEmbedRequest(text, '${body['taskType']}', apiKey, values),
      );
      return http.Response(
        jsonEncode({
          'embedding': {'values': values},
        }),
        200,
        headers: const {'content-type': 'application/json'},
      );
    }

    if (path.endsWith(':generateContent')) {
      final contents = (body['contents'] as List?) ?? const [];
      final parts = contents.isEmpty
          ? const []
          : (contents.first['parts'] as List?) ?? const [];
      generatePrompts.add(parts.isEmpty ? '' : '${parts.first['text']}');
      return http.Response(
        jsonEncode({
          'candidates': [
            {
              'content': {
                'parts': [
                  {'text': narrativeReply},
                ],
              },
            },
          ],
        }),
        200,
        headers: const {'content-type': 'application/json; charset=utf-8'},
      );
    }

    unexpectedRequests.add(request.url);
    return http.Response('not found', 404);
  });
}
