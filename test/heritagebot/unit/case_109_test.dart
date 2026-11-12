// HERITAGEBOT - TEST CASE 109
// Proponent: AI Knowledge Base / System Team
// Module: AI Knowledge Base Management
// Unit: Vector Retrieval
// Description: Query knowledge base for site
// Expected: Return relevant site-specific chunks
//
// TEST TYPE: Flutter unit test (service level; host VM, no live Firebase /
// live Gemini).
//
// REAL CODE UNDER TEST (lib/, unmodified)
//   KnowledgeBaseService.retrieveForSite: where(siteId == place.id) ->
//   keep isApproved && hasEmbedding -> GeminiEmbeddingService.embedQuery
//   (RETRIEVAL_QUERY) -> _cosineSimilarity ranking -> top `limit` chunks ->
//   RagRetrievalResult (documents, context, retrievalMode "vector_rag").
//
// FIXTURE (fixtureId = CASE-109): the knowledge base is built through the
// real KnowledgeBaseService.addContent (so every vector is exactly what the
// app stores):
//   * Magellan's Cross: two approved chunks (planting of the cross; kiosk
//     ceiling mural) and one NOT approved chunk;
//   * Fort San Pedro: two approved chunks whose text also mentions the cross.
//   The query is about the planting of the cross.
//
// MOCKED: Firebase platform layer and Gemini's embedContent endpoint
// (FakeGeminiApi: deterministic bag-of-words vectors, so texts sharing
// words are more similar). Needs the dummy GEMINI_API_KEY from
// support/unit_091_120_defines.json; otherwise SKIPPED.

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:heritagebot/main.dart' show geminiApiKey;
import 'package:heritagebot/models/heritage_place.dart';
import 'package:heritagebot/services/knowledge_base_service.dart';

import '../support/admin_operations_flow.dart';
import '../support/fake_gemini_api.dart';

const String kQuery = 'Who planted the cross in 1521 and why was the cross planted in Cebu?';

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

  test('CASE-109 - Query knowledge base for site', () async {
    await http.runWithClient(() async {
      final kb = KnowledgeBaseService(geminiApiKey: geminiApiKey);
      final fort = bundledSite('fort_san_pedro');
      final ids = <String, String>{};

      Future<void> add(String key, HeritagePlace site, String title, String content, {bool approved = true}) async {
        final item = await kb.addContent(siteId: site.id, siteName: site.name, title: title, content: content, sourceTitle: 'Verified source for $title', sourceUrl: '', category: 'historical_record', languageCode: 'en', isApproved: approved);
        ids[key] = item.id;
      }

      await add('planting', kMagellansCross, 'Planting of the Cross', 'The cross was planted in 1521 by the Magellan expedition in Cebu to mark the baptism of Rajah Humabon; the cross planted that day is the origin of the landmark.');
      await add('mural', kMagellansCross, 'The Kiosk Ceiling Mural', 'The octagonal kiosk has a ceiling mural painted by local artists showing the first baptism ceremony.');
      await add('unapproved', kMagellansCross, 'Unreviewed Claim', 'An unreviewed note claims the cross was planted in 1521 by a different expedition entirely.', approved: false);
      await add('fortA', fort, 'Fort and the Cross', 'Soldiers of the fort escorted processions to the cross planted in 1521 near the plaza.');
      await add('fortB', fort, 'Triangular Bastion', 'Fort San Pedro is a triangular bastion fort built by Spanish colonists.');
      gemini.clear(); // observe only the retrieval request below

      final result = await kb.retrieveForSite(place: kMagellansCross, query: kQuery);

      // ---- Observations ---------------------------------------------------
      final stored = storedHistorical(backend);
      final siteChunks = stored.entries
          .where((e) => e.value['siteId'] == kMagellansCross.id && e.value['isApproved'] == true)
          .map((e) => e.key.split('/').last)
          .toSet();
      final queryCall = gemini.embedRequests.where((r) => r.taskType == 'RETRIEVAL_QUERY').firstOrNull;

      final observed = <String, Object?>{
        'chunksRetrieved':
            result.retrievalMode == 'vector_rag' &&
            result.documents.isNotEmpty &&
            queryCall != null &&
            queryCall.text == kQuery &&
            // most relevant chunk ranked first
            result.documents.first.id == ids['planting'] &&
            result.context.contains('TITLE: Planting of the Cross'),
      'correctSiteSourcesOnly':
            result.documents.every((d) => d.siteId == kMagellansCross.id && d.isApproved) &&
            result.documentIds.toSet().difference(siteChunks).isEmpty &&
            !result.documentIds.contains(ids['unapproved']) &&
            !result.documentIds.contains(ids['fortA']) &&
            !result.documentIds.contains(ids['fortB']) &&
            !result.context.contains('different expedition') &&
            !result.context.contains('Soldiers of the fort'),
      };
      printOnFailure(
        'CASE-109 observed: $observed\nids=$ids\nresult=${result.retrievalMode} ${result.documentIds}\n'
        'context=${result.context}\nembedRequests=${gemini.embedRequests}',
      );
      // ignore: avoid_print
      print('CASE-109 evidence: observed=$observed mode=${result.retrievalMode} '
          'retrieved=${result.documents.map((d) => d.title).toList()}');

      // ---- Expected result (unchanged from the original CASE-109) ---------
      expect(
        observed['chunksRetrieved'],
        equals(true),
        reason: 'CASE-109: chunksRetrieved does not match the real system result',
      );
      expect(
        observed['correctSiteSourcesOnly'],
        equals(true),
        reason: 'CASE-109: correctSiteSourcesOnly does not match the real system result',
      );
    }, gemini.client);
  }, skip: geminiTestSkip);
}
