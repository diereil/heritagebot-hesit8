// HERITAGEBOT - TEST CASE 110
// Proponent: AI Knowledge Base / System Team
// Module: AI Knowledge Base Management
// Unit: RAG Pipeline
// Description: Generate narrative with retrieved context
// Expected: Use retrieved verified context
//
// TEST TYPE: Flutter unit test (service level; host VM, no live Firebase /
// live Gemini).
//
// REAL CODE UNDER TEST (lib/, unmodified)
//   GeminiStoryService.generateContextAwareStory (lib/main.dart) ->
//   KnowledgeBaseService.retrieveForSite (vector retrieval) -> prompt with
//   "RETRIEVED VERIFIED CONTEXT" + "Retrieved source titles" -> POST
//   models/gemini-3.6-flash:generateContent -> AiNarrativeService
//   .recordGeneratedNarrative (retrievalMode, retrievedContentIds,
//   retrievedSourceTitles).
//
// FIXTURE (fixtureId = CASE-110): verified (approved) chunks for Magellan's
// Cross and for Fort San Pedro, created through the real
// KnowledgeBaseService.addContent; a signed-in tourist requests the
// narrative for Magellan's Cross. The model reply is canned by the fake -
// what is tested is HeritageBot's retrieval-augmented pipeline (what it
// retrieves, sends as grounding context, and records), not the wording of
// the language model.
//
// MOCKED: Firebase platform layer and Gemini's embedContent /
// generateContent endpoints (FakeGeminiApi). Needs the dummy GEMINI_API_KEY
// from support/unit_091_120_defines.json; otherwise SKIPPED.

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:heritagebot/main.dart' show GeminiStoryService, geminiApiKey, geminiModel;
import 'package:heritagebot/services/knowledge_base_service.dart';
import 'package:heritagebot/services/language_service.dart';

import '../support/admin_operations_flow.dart';
import '../support/fake_gemini_api.dart';

const FakeAuthAccount kTourist = FakeAuthAccount(
  uid: 'case110-tourist-uid',
  email: 'case110.tourist@heritagebot.test',
  password: 'Case110Pass!',
  displayName: 'Tess Tourist',
);

const String kCrossChunk =
    'The cross was planted on 21 April 1521 by the Magellan expedition in Cebu '
    'to mark the baptism of Rajah Humabon and about 800 of his people.';
const String kCrossSource = 'Antonio Pigafetta, First Voyage Around the World';
const String kKioskChunk =
    'The octagonal kiosk that houses the cross was built in 1834 and its ceiling '
    'mural shows the planting of the cross.';
const String kKioskSource = 'Basilica Minore del Santo Nino Museum';
const String kFortChunk =
    'Fort San Pedro is a triangular bastion fort first built of wood in 1565 under '
    'Miguel Lopez de Legazpi.';

late HeritageBotTestBackend backend;
final FakeGeminiApi gemini = FakeGeminiApi();

void main() {
  setUpAll(() async {
    backend = await HeritageBotTestBackend.install(accounts: [kTourist]);
  });

  setUp(() async {
    await backend.reset();
    gemini.clear();
    backend.seedTourist(kTourist);
  });

  test('CASE-110 - Generate narrative with retrieved context', () async {
    await http.runWithClient(() async {
      final kb = KnowledgeBaseService(geminiApiKey: geminiApiKey);
      final fort = bundledSite('fort_san_pedro');
      final cross = await kb.addContent(siteId: kMagellansCross.id, siteName: kMagellansCross.name, title: 'Planting of the Cross', content: kCrossChunk, sourceTitle: kCrossSource, sourceUrl: '', category: 'historical_record', languageCode: 'en', isApproved: true);
      final kiosk = await kb.addContent(siteId: kMagellansCross.id, siteName: kMagellansCross.name, title: 'The Kiosk', content: kKioskChunk, sourceTitle: kKioskSource, sourceUrl: '', category: 'historical_record', languageCode: 'en', isApproved: true);
      await kb.addContent(siteId: fort.id, siteName: fort.name, title: 'Triangular Bastion', content: kFortChunk, sourceTitle: 'National Historical Commission of the Philippines', sourceUrl: '', category: 'historical_record', languageCode: 'en', isApproved: true);
      gemini.clear();
      gemini.narrativeReply =
          'Standing near Magellan\'s Cross, you are where the Magellan expedition '
          'planted a cross in 1521 to mark the baptism of Rajah Humabon.';

      // STEP: the signed-in tourist requests the narrative.
      await signInBeforeLaunch(kTourist);
      final narrative = await GeminiStoryService().generateContextAwareStory(
        place: kMagellansCross,
        distanceMeters: 35,
        speedMetersPerSecond: 0.8,
        memories: const [],
        preferredLanguage: languageByCode('en'),
      );

      // ---- Observations ---------------------------------------------------
      final prompt = gemini.generatePrompts.isEmpty ? '' : gemini.generatePrompts.single;
      final contextStart = prompt.indexOf('RETRIEVED VERIFIED CONTEXT:');
      final contextEnd = prompt.indexOf('Retrieved source titles:');
      final contextBlock = contextStart >= 0 && contextEnd > contextStart
          ? prompt.substring(contextStart, contextEnd)
          : '';
      final records = backend.firestore.documents.entries
          .where((e) => e.key.startsWith('ai_narratives/'))
          .map((e) => e.value)
          .toList();
      final record = records.isEmpty ? null : records.single;
      final recordedIds = ((record?['retrievedContentIds'] as List?) ?? const []).cast<String>();
      final recordedSources = ((record?['retrievedSourceTitles'] as List?) ?? const []).cast<String>();

      final observed = <String, Object?>{
        'narrativeGenerated':
            narrative == gemini.narrativeReply &&
            gemini.generatePrompts.length == 1 &&
            record != null &&
            record['narrative'] == narrative &&
            record['userId'] == kTourist.uid &&
            record['siteId'] == kMagellansCross.id &&
            record['modelName'] == geminiModel,
        'retrievedContextUsed':
            gemini.embedRequests.any((r) => r.taskType == 'RETRIEVAL_QUERY') &&
            contextBlock.contains(kCrossChunk) &&
            contextBlock.contains(kKioskChunk) &&
            contextBlock.contains('SOURCE: $kCrossSource') &&
            !contextBlock.contains(kFortChunk) &&
            prompt.contains('Base historical claims only on the RETRIEVED VERIFIED CONTEXT above.') &&
            record?['retrievalMode'] == 'vector_rag' &&
            recordedIds.toSet().containsAll({cross.id, kiosk.id}) &&
            recordedIds.length == 2 &&
            recordedSources.toSet().containsAll({kCrossSource, kKioskSource}),
      };
      printOnFailure(
        'CASE-110 observed: $observed\nnarrative=$narrative\nrecord=$record\n'
        'contextBlock=$contextBlock\nembedRequests=${gemini.embedRequests}\n'
        'unexpected=${gemini.unexpectedRequests}',
      );
      // ignore: avoid_print
      print('CASE-110 evidence: observed=$observed retrievalMode=${record?['retrievalMode']} '
          'retrievedSources=$recordedSources');

      // ---- Expected result (unchanged from the original CASE-110) ---------
      expect(
        observed['narrativeGenerated'],
        equals(true),
        reason: 'CASE-110: narrativeGenerated does not match the real system result',
      );
      expect(
        observed['retrievedContextUsed'],
        equals(true),
        reason: 'CASE-110: retrievedContextUsed does not match the real system result',
      );
    }, gemini.client);
  }, skip: geminiTestSkip);
}
