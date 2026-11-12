// HERITAGEBOT - TEST CASE 111
// Proponent: AI Knowledge Base / System Team
// Module: AI Knowledge Base Management
// Unit: RAG Pipeline
// Description: Query with no matching historical evidence
// Expected: Avoid unsupported historical claims
//
// TEST TYPE: Flutter unit test (service level; host VM, no live Firebase /
// live Gemini).
//
// REAL CODE UNDER TEST (lib/, unmodified)
//   GeminiStoryService.generateContextAwareStory -> KnowledgeBaseService
//   .retrieveForSite (no approved + embedded chunk for the site -> _fallback:
//   "SOURCE: HeritageBot site record") -> prompt -> generateContent ->
//   AiNarrativeService.recordGeneratedNarrative.
//
// FIXTURE (siteFixture = site_with_no_verified_sources): Magellan's Cross
// has NO verified (approved) knowledge-base chunk. Its only chunk is an
// unreviewed, unsupported claim ("carved from a meteorite in 1888 by Jose
// Rizal"), which HeritageBot must not use as evidence. Fort San Pedro has
// verified chunks that must not be borrowed either.
//
// WHAT IS OBSERVED: what HeritageBot hands to the language model as its
// only allowed evidence (the grounding context), the grounding rules in the
// prompt, and how the request is recorded. The model reply itself is canned
// by the fake; the language model's own behaviour is not tested.
//
// MOCKED: Firebase platform layer and Gemini's embedContent /
// generateContent endpoints (FakeGeminiApi). Needs the dummy GEMINI_API_KEY
// from support/unit_091_120_defines.json; otherwise SKIPPED.

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:heritagebot/main.dart' show GeminiStoryService, geminiApiKey;
import 'package:heritagebot/services/knowledge_base_service.dart';
import 'package:heritagebot/services/language_service.dart';

import '../support/admin_operations_flow.dart';
import '../support/fake_gemini_api.dart';

const FakeAuthAccount kTourist = FakeAuthAccount(
  uid: 'case111-tourist-uid',
  email: 'case111.tourist@heritagebot.test',
  password: 'Case111Pass!',
  displayName: 'Tess Tourist',
);

const String kUnsupportedClaim =
    'The cross was carved from a meteorite in 1888 by Jose Rizal during a secret visit to Cebu.';
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

  test('CASE-111 - Query with no matching historical evidence', () async {
    await http.runWithClient(() async {
      final kb = KnowledgeBaseService(geminiApiKey: geminiApiKey);
      final fort = bundledSite('fort_san_pedro');
      await kb.addContent(siteId: kMagellansCross.id, siteName: kMagellansCross.name, title: 'Unreviewed meteorite claim', content: kUnsupportedClaim, sourceTitle: 'Anonymous social media post', sourceUrl: '', category: 'historical_record', languageCode: 'en', isApproved: false);
      await kb.addContent(siteId: fort.id, siteName: fort.name, title: 'Triangular Bastion', content: kFortChunk, sourceTitle: 'National Historical Commission of the Philippines', sourceUrl: '', category: 'historical_record', languageCode: 'en', isApproved: true);
      gemini.clear();

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

      final observed = <String, Object?>{
        'unsupportedClaimsAvoided':
            prompt.isNotEmpty &&
            !prompt.contains('meteorite') &&
            !prompt.contains('Jose Rizal') &&
            !prompt.contains('Anonymous social media post') &&
            !prompt.contains(kFortChunk) &&
            prompt.contains('Base historical claims only on the RETRIEVED VERIFIED CONTEXT above.') &&
            prompt.contains('Do not invent fake dates, names, events, or unsupported historical claims.') &&
            prompt.contains('If the retrieved context does not support a detail, leave that detail out.'),
        'noEvidenceHandled':
            contextBlock.contains('SOURCE: HeritageBot site record') &&
            contextBlock.contains(kMagellansCross.historicalFacts) &&
            prompt.contains('Retrieved source titles:\nHeritageBot site record') &&
            narrative.trim().isNotEmpty &&
            record?['retrievalMode'] == 'site_facts_fallback' &&
            ((record?['retrievedContentIds'] as List?) ?? const ['x']).isEmpty &&
            ((record?['retrievedSourceTitles'] as List?) ?? const ['x']).isEmpty,
      };
      printOnFailure(
        'CASE-111 observed: $observed\nnarrative=$narrative\nrecord=$record\n'
        'prompt=$prompt\nembedRequests=${gemini.embedRequests}',
      );
      // ignore: avoid_print
      print('CASE-111 evidence: observed=$observed retrievalMode=${record?['retrievalMode']} '
          'retrievedContentIds=${record?['retrievedContentIds']}');

      // ---- Expected result (unchanged from the original CASE-111) ---------
      expect(
        observed['unsupportedClaimsAvoided'],
        equals(true),
        reason: 'CASE-111: unsupportedClaimsAvoided does not match the real system result',
      );
      expect(
        observed['noEvidenceHandled'],
        equals(true),
        reason: 'CASE-111: noEvidenceHandled does not match the real system result',
      );
    }, gemini.client);
  }, skip: geminiTestSkip);
}
