// HERITAGEBOT - TEST CASE 106
// Proponent: AI Knowledge Base / System Team
// Module: AI Knowledge Base Management
// Unit: Update Knowledge Base
// Description: Process new or changed historical data
// Expected: Update searchable knowledge index
//
// TEST TYPE: Flutter widget test (host VM, no device / live Firebase /
// live Gemini).
//
// REAL CODE UNDER TEST (lib/, unmodified)
//   AuthGate -> AdminShell -> "AI Base" -> "Update Knowledge Base" ->
//   _updateKnowledgeBase -> CommunitySubmissionService.getApprovedSubmissions
//   -> KnowledgeBaseService.syncApprovedCommunityStories (adds new approved
//   stories, removes stories that are no longer approved) ->
//   rebuildAllEmbeddings (re-embeds every record from its CURRENT text) ->
//   then KnowledgeBaseService.retrieveForSite queries the updated index.
//
// FIXTURE (fixtureId = CASE-106)
//   * NEW data: an approved community story for Fort San Pedro that is not
//     yet in the knowledge base;
//   * CHANGED data: a Magellan's Cross record whose content was corrected
//     after its embedding was generated (stored vector = vector of the OLD
//     text);
//   * WITHDRAWN data: a community record whose story has since been
//     rejected;
//   * an unchanged second Magellan's Cross record.
//
// MOCKED: Firebase platform layer and Gemini's embedContent endpoint
// (FakeGeminiApi). Needs the dummy GEMINI_API_KEY from
// support/unit_091_120_defines.json; otherwise SKIPPED.

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:heritagebot/main.dart' show geminiApiKey;
import 'package:heritagebot/models/community_submission.dart';
import 'package:heritagebot/services/knowledge_base_service.dart';

import '../support/admin_operations_flow.dart';
import '../support/fake_gemini_api.dart';

const String kOldContent =
    'The cross is said to contain the original wooden cross that was planted in 1521.';
const String kNewContent =
    'The original cross is encased inside a tindalo hardwood casing to protect it '
    'from devotees who chipped pieces off as relics.';
const String kStoryText =
    'My grandfather guarded the fort during the war and showed us the old '
    'watchtower where soldiers looked out over the harbour for enemy ships.';

late HeritageBotTestBackend backend;
final FakeGeminiApi gemini = FakeGeminiApi();

void main() {
  setUpAll(() async {
    backend = await HeritageBotTestBackend.install(accounts: [kAdminAccount]);
  });

  setUp(() async {
    await backend.reset();
    gemini.clear();
    final fort = bundledSite('fort_san_pedro');
    seedRegisteredSites(backend, [kMagellansCross, fort]);
    // CHANGED record: content corrected, embedding still of the old text.
    seedHistorical(backend, historicalRecord(id: 'case106-changed', site: kMagellansCross, title: 'The Tindalo Casing', content: kNewContent, sourceTitle: 'Basilica Minore del Santo Nino Museum', embedding: fakeEmbeddingOf(kOldContent)));
    seedHistorical(backend, historicalRecord(id: 'case106-unchanged', site: kMagellansCross, title: 'The Kiosk Ceiling Mural', content: 'The kiosk ceiling shows a painting of the first baptism of Rajah Humabon.', sourceTitle: 'Cebu City Tourism Office', embedding: fakeEmbeddingOf('kiosk ceiling painting baptism')));
    // WITHDRAWN community record.
    seedHistorical(backend, historicalRecord(id: 'community_case106-withdrawn', site: fort, title: 'Fort Ghost Stories', content: 'Rumours about ghosts in the fort that were later withdrawn by the administrator.', sourceTitle: 'Approved community story by Pedro Cruz', category: 'community_story', sourceType: 'community', sourceRefId: 'case106-withdrawn', embedding: fakeEmbeddingOf('ghost rumours fort')));
    seedStory(backend, storyFixture(id: 'case106-withdrawn', title: 'Fort Ghost Stories', status: CommunitySubmissionStatus.rejected, site: fort, contributorName: 'Pedro Cruz'));
    // NEW approved community story.
    seedStory(backend, storyFixture(id: 'case106-new', title: 'Grandfather at the Watchtower', status: CommunitySubmissionStatus.approved, site: fort, contributorName: 'Ana Reyes', story: kStoryText));
  });

  group('', () {
    testWidgets('CASE-106 - Process new or changed historical data', (WidgetTester tester) async {
      await http.runWithClient(() async {
        usePhoneSurface(tester);
        const changedPath = 'historical_contents/case106-changed';
        final staleEmbedding = '${storedHistorical(backend)[changedPath]!['embedding']}';

        await openAdminShell(tester);
        await openKnowledgeBaseTab(tester);
        final recordsBefore = knowledgeSummaryValue(tester, 'Records');

        // STEP: "Update Knowledge Base".
        await tapKnowledgeBaseAction(tester, 'Update Knowledge Base');
        final messages = shownSnackBarTexts(tester);
        final cards = await knowledgeCards(tester);
        final recordsAfter = knowledgeSummaryValue(tester, 'Records');

        // STEP: query the updated index the way the narrative generator does.
        final kb = KnowledgeBaseService(geminiApiKey: geminiApiKey);
        final crossResult = await kb.retrieveForSite(place: kMagellansCross, query: 'tindalo hardwood casing protect relics devotees');
        final fortResult = await kb.retrieveForSite(place: bundledSite('fort_san_pedro'), query: 'grandfather watchtower war soldiers harbour');

        // ---- Observations -------------------------------------------------
        final stored = storedHistorical(backend);
        final changed = stored[changedPath];
        final community = stored['historical_contents/community_case106-new'];
        List<double>? vec(Map<String, dynamic>? d) =>
            (d?['embedding'] as List?)?.cast<num>().map((v) => v.toDouble()).toList();
        final changedCall = gemini.embedRequests.where((r) => r.taskType == 'RETRIEVAL_DOCUMENT' && r.text.contains(kNewContent)).lastOrNull;
        final storyCall = gemini.embedRequests.where((r) => r.taskType == 'RETRIEVAL_DOCUMENT' && r.text.contains(kStoryText)).lastOrNull;

        final observed = <String, Object?>{
          'knowledgeIndexUpdated':
              messages.contains(
                'Knowledge base updated: 1 approved community stories synced and '
                '${stored.length} vector embeddings rebuilt.',
              ) &&
              changedCall != null &&
              '${vec(changed)}' == '${changedCall.values}' &&
              '${vec(changed)}' != staleEmbedding &&
              community != null &&
              community['sourceType'] == 'community' &&
              community['siteId'] == 'fort_san_pedro' &&
              community['content'] == kStoryText &&
              storyCall != null &&
              '${vec(community)}' == '${storyCall.values}' &&
              !stored.containsKey('historical_contents/community_case106-withdrawn') &&
              recordsBefore == 3 &&
              recordsAfter == stored.length &&
              cards.any((c) => c.title == 'Grandfather at the Watchtower'),
          'changedSourceQueryable':
              crossResult.retrievalMode == 'vector_rag' &&
              crossResult.documents.isNotEmpty &&
              crossResult.documents.first.id == 'case106-changed' &&
              crossResult.context.contains(kNewContent) &&
              fortResult.retrievalMode == 'vector_rag' &&
              fortResult.documentIds.contains('community_case106-new') &&
              !fortResult.documentIds.contains('community_case106-withdrawn'),
        };
        printOnFailure(
          'CASE-106 observed: $observed\nmessages=$messages\nrecords $recordsBefore -> $recordsAfter\n'
          'stored=${stored.keys}\ncrossResult=${crossResult.retrievalMode} ${crossResult.documentIds}\n'
          'fortResult=${fortResult.retrievalMode} ${fortResult.documentIds}\nembedRequests=${gemini.embedRequests}',
        );
        // ignore: avoid_print
        print('CASE-106 evidence: observed=$observed messages=$messages '
            'crossTop=${crossResult.documentIds} fort=${fortResult.documentIds}');

        // ---- Expected result (unchanged from the original CASE-106) -------
        expect(
          observed['knowledgeIndexUpdated'],
          equals(true),
          reason: 'CASE-106: knowledgeIndexUpdated does not match the real system result',
        );
        expect(
          observed['changedSourceQueryable'],
          equals(true),
          reason: 'CASE-106: changedSourceQueryable does not match the real system result',
        );

        await unmountApp(tester);
      }, gemini.client);
    });
  }, skip: geminiTestSkip);
}
