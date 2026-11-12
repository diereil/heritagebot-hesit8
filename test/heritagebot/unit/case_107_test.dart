// HERITAGEBOT - TEST CASE 107
// Proponent: AI Knowledge Base / System Team
// Module: AI Knowledge Base Management
// Unit: Vector Embeddings
// Description: Generate embedding for valid text chunk
// Expected: Store embedding linked to chunk
//
// TEST TYPE: Flutter unit test (service level; host VM, no live Firebase /
// live Gemini).
//
// REAL CODE UNDER TEST (lib/, unmodified)
//   KnowledgeBaseService.addContent -> _validate -> _embeddingInput ->
//   GeminiEmbeddingService.embedDocument (POST models/gemini-embedding-001:
//   embedContent, taskType RETRIEVAL_DOCUMENT, outputDimensionality 768) ->
//   HistoricalContent(embedding, embeddingModel) -> historical_contents/{id}.set.
//
// FIXTURE (fixtureId = CASE-107): two valid text chunks for two different
// sites are added one after the other, so a mix-up between chunk and vector
// would be detected.
//
// MOCKED: Firebase platform layer and Gemini's embedContent endpoint
// (FakeGeminiApi returns a distinct, deterministic vector per text). Needs
// the dummy GEMINI_API_KEY from support/unit_091_120_defines.json;
// otherwise SKIPPED.

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:heritagebot/main.dart' show geminiApiKey;
import 'package:heritagebot/models/heritage_place.dart';
import 'package:heritagebot/models/historical_content.dart';
import 'package:heritagebot/services/gemini_embedding_service.dart';
import 'package:heritagebot/services/knowledge_base_service.dart';

import '../support/admin_operations_flow.dart';
import '../support/fake_gemini_api.dart';

const String kChunkA =
    'Magellan\'s Cross was planted on 21 April 1521 on the orders of Ferdinand '
    'Magellan to mark the baptism of the first Filipino Christians in Cebu.';
const String kChunkB =
    'Fort San Pedro served as the nucleus of the first Spanish settlement in '
    'the Philippines and later as an American military barracks.';

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

  test('CASE-107 - Generate embedding for valid text chunk', () async {
    await http.runWithClient(() async {
      final kb = KnowledgeBaseService(geminiApiKey: geminiApiKey);
      final fort = bundledSite('fort_san_pedro');

      Future<Object> add(HeritagePlace site, String title, String chunk, String source) async {
        try {
          return await kb.addContent(siteId: site.id, siteName: site.name, title: title, content: chunk, sourceTitle: source, sourceUrl: '', category: 'historical_record', languageCode: 'en', isApproved: true);
        } catch (e) {
          return e;
        }
      }

      final itemA = await add(kMagellansCross, 'Planting of the Cross', kChunkA, 'Cebu City Tourism Office');
      final itemB = await add(fort, 'First Spanish Settlement', kChunkB, 'National Historical Commission of the Philippines');

      // ---- Observations ---------------------------------------------------
      final stored = storedHistorical(backend);
      Map<String, dynamic>? docWith(String chunk) =>
          stored.values.where((d) => d['content'] == chunk).firstOrNull;
      List<double>? vec(Map<String, dynamic>? d) =>
          (d?['embedding'] as List?)?.cast<num>().map((v) => v.toDouble()).toList();
      FakeEmbedRequest? callFor(String chunk) =>
          gemini.embedRequests.where((r) => r.text.contains(chunk)).firstOrNull;
      final docA = docWith(kChunkA);
      final docB = docWith(kChunkB);
      final callA = callFor(kChunkA);
      final callB = callFor(kChunkB);

      final observed = <String, Object?>{
        'embeddingCreated':
            stored.length == 2 &&
            gemini.embedRequests.length == 2 &&
            gemini.embedRequests.every((r) => r.taskType == 'RETRIEVAL_DOCUMENT' && r.apiKey == kDummyGeminiApiKey) &&
            vec(docA)?.length == GeminiEmbeddingService.outputDimensions &&
            vec(docB)?.length == GeminiEmbeddingService.outputDimensions &&
            docA?['embeddingModel'] == GeminiEmbeddingService.modelName &&
            docB?['embeddingModel'] == GeminiEmbeddingService.modelName,
        'correctChunkLinked':
            callA != null &&
            callB != null &&
            '${vec(docA)}' == '${callA.values}' &&
            '${vec(docB)}' == '${callB.values}' &&
            '${vec(docA)}' != '${vec(docB)}' &&
            itemA is HistoricalContent &&
            itemB is HistoricalContent &&
            '${itemA.embedding}' == '${callA.values}' &&
            stored['historical_contents/${itemA.id}']?['content'] == kChunkA &&
            stored['historical_contents/${itemB.id}']?['content'] == kChunkB &&
            docA?['siteId'] == kMagellansCross.id &&
            docB?['siteId'] == fort.id,
      };
      printOnFailure(
        'CASE-107 observed: $observed\nitemA=$itemA itemB=$itemB\nstored=${stored.keys}\n'
        'embedRequests=${gemini.embedRequests}',
      );
      // ignore: avoid_print
      print('CASE-107 evidence: observed=$observed docs=${stored.keys.toList()} '
          'dims=${vec(docA)?.length}/${vec(docB)?.length}');

      // ---- Expected result (unchanged from the original CASE-107) ---------
      expect(
        observed['embeddingCreated'],
        equals(true),
        reason: 'CASE-107: embeddingCreated does not match the real system result',
      );
      expect(
        observed['correctChunkLinked'],
        equals(true),
        reason: 'CASE-107: correctChunkLinked does not match the real system result',
      );
    }, gemini.client);
  }, skip: geminiTestSkip);
}
