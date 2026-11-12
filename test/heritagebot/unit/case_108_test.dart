// HERITAGEBOT - TEST CASE 108
// Proponent: AI Knowledge Base / System Team
// Module: AI Knowledge Base Management
// Unit: Vector Embeddings
// Description: Process empty text chunk
// Expected: Skip or reject invalid chunk
//
// TEST TYPE: Flutter unit test (service level; host VM, no live Firebase /
// live Gemini).
//
// REAL CODE UNDER TEST (lib/, unmodified)
//   1. GeminiEmbeddingService.embedDocument('') and ('   ') - the embedding
//      unit itself (safeText.isEmpty -> ArgumentError before any request).
//   2. KnowledgeBaseService.addContent with an empty content chunk - the
//      path that stores chunks (_validate -> ArgumentError before
//      embedding / storing).
//
// INPUT (textChunk = ''). The dummy Gemini key is compiled in, so a
// rejection cannot come from a missing API key.
//
// MOCKED: Firebase platform layer and Gemini's embedContent endpoint
// (FakeGeminiApi records every request). Needs the dummy GEMINI_API_KEY
// from support/unit_091_120_defines.json; otherwise SKIPPED.

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:heritagebot/main.dart' show geminiApiKey;
import 'package:heritagebot/services/gemini_embedding_service.dart';
import 'package:heritagebot/services/knowledge_base_service.dart';

import '../support/admin_operations_flow.dart';
import '../support/fake_gemini_api.dart';

const String kTextChunk = '';

late HeritageBotTestBackend backend;
final FakeGeminiApi gemini = FakeGeminiApi();

void main() {
  setUpAll(() async {
    backend = await HeritageBotTestBackend.install();
  });

  setUp(() async {
    await backend.reset();
    gemini.clear();
  });

  test('CASE-108 - Process empty text chunk', () async {
    await http.runWithClient(() async {
      final embedder = GeminiEmbeddingService(apiKey: geminiApiKey);
      final kb = KnowledgeBaseService(geminiApiKey: geminiApiKey);

      Future<Object?> attempt(Future<Object?> Function() run) async {
        try {
          return await run();
        } catch (e) {
          return e;
        }
      }

      final emptyResult = await attempt(() => embedder.embedDocument(kTextChunk));
      final blankResult = await attempt(() => embedder.embedDocument('   \n  '));
      final addResult = await attempt(() => kb.addContent(
            siteId: kMagellansCross.id,
            siteName: kMagellansCross.name,
            title: 'Empty chunk',
            content: kTextChunk,
            sourceTitle: 'Cebu City Tourism Office',
            sourceUrl: '',
            category: 'historical_record',
            languageCode: 'en',
            isApproved: true,
          ));

      // ---- Observations ---------------------------------------------------
      final stored = storedHistorical(backend);
      final observed = <String, Object?>{
        'embeddingCreated':
            emptyResult is List ||
            blankResult is List ||
            gemini.embedRequests.isNotEmpty ||
            stored.isNotEmpty,
        'emptyChunkRejected':
            emptyResult is ArgumentError &&
            blankResult is ArgumentError &&
            addResult is ArgumentError &&
            gemini.embedRequests.isEmpty &&
            stored.isEmpty,
      };
      printOnFailure(
        'CASE-108 observed: $observed\nembedDocument("") -> $emptyResult\n'
        'embedDocument(blank) -> $blankResult\naddContent(empty) -> $addResult\n'
        'embedRequests=${gemini.embedRequests} stored=${stored.keys}',
      );
      // ignore: avoid_print
      print('CASE-108 evidence: observed=$observed\n  embedDocument("") -> $emptyResult\n'
          '  addContent(content: "") -> $addResult');

      // ---- Expected result (unchanged from the original CASE-108) ---------
      expect(
        observed['embeddingCreated'],
        equals(false),
        reason: 'CASE-108: embeddingCreated does not match the real system result',
      );
      expect(
        observed['emptyChunkRejected'],
        equals(true),
        reason: 'CASE-108: emptyChunkRejected does not match the real system result',
      );
    }, gemini.client);
  }, skip: geminiTestSkip);
}
