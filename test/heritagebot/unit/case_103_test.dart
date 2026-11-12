// HERITAGEBOT - TEST CASE 103
// Proponent: AI Knowledge Base / System Team
// Module: AI Knowledge Base Management
// Unit: Add Historical Data
// Description: Add verified site source
// Expected: Save source and site association
//
// TEST TYPE: Flutter widget test (host VM, no device / live Firebase /
// live Gemini).
//
// REAL CODE UNDER TEST (lib/, unmodified)
//   AuthGate -> AdminShell -> "AI Base" -> FAB "Add Historical Data" ->
//   HistoricalContentEditorScreen ("Heritage Site" dropdown, title, content,
//   "Source / Reference", "Source URL") -> "Save & Generate Embedding" ->
//   KnowledgeBaseService.addContent (_validate -> GeminiEmbeddingService
//   .embedDocument -> historical_contents/{id}.set) -> list refresh.
//
// FIXTURE (fixtureId = CASE-103): three registered sites; the administrator
// picks Magellan's Cross (NOT the dropdown's default first site) and enters
// a verified source.
//
// MOCKED: Firebase platform layer and Gemini's embedContent endpoint
// (FakeGeminiApi via package:http runWithClient). Needs the dummy
// GEMINI_API_KEY from support/unit_091_120_defines.json; otherwise SKIPPED.

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:heritagebot/services/gemini_embedding_service.dart';

import '../support/admin_operations_flow.dart';
import '../support/fake_gemini_api.dart';

const String kTitle = 'Arrival of the Magellan Expedition';
const String kContent =
    'On 7 April 1521 the Magellan expedition arrived in Cebu. A wooden cross '
    'was planted to mark the baptism of Rajah Humabon and his wife, Hara Amihan.';
const String kSource = 'Antonio Pigafetta, Relazione del primo viaggio intorno al mondo';
const String kSourceUrl = 'https://www.loc.gov/item/2021666208/';

late HeritageBotTestBackend backend;
final FakeGeminiApi gemini = FakeGeminiApi();

void main() {
  setUpAll(() async {
    backend = await HeritageBotTestBackend.install(accounts: [kAdminAccount]);
  });

  setUp(() async {
    await backend.reset();
    gemini.clear();
    seedRegisteredSites(backend, [bundledSite('casa_gorordo'), bundledSite('fort_san_pedro'), kMagellansCross]);
  });

  group('', () {
    testWidgets('CASE-103 - Add verified site source', (WidgetTester tester) async {
      await http.runWithClient(() async {
        usePhoneSurface(tester);

        await openAdminShell(tester);
        await openKnowledgeBaseTab(tester);
        await openAddHistoricalData(tester);

        // STEP: choose the site and enter the verified source.
        await chooseHistoricalSite(tester, kMagellansCross.name);
        await enterHistoricalField(tester, 'Historical Data Title', kTitle);
        await enterHistoricalField(tester, 'Verified Historical Content', kContent);
        await enterHistoricalField(tester, 'Source / Reference', kSource);
        await enterHistoricalField(tester, 'Source URL', kSourceUrl);
        final closed = await saveHistoricalEditor(tester);
        final messages = shownSnackBarTexts(tester);
        final cards = await knowledgeCards(tester);

        // ---- Observations -------------------------------------------------
        final stored = storedHistorical(backend);
        final doc = stored.values.where((d) => d['title'] == kTitle).firstOrNull;
        final embedding = (doc?['embedding'] as List?)?.cast<num>().map((v) => v.toDouble()).toList();
        final embedCall = gemini.embedRequests.where((r) => r.text.contains(kContent)).firstOrNull;
        final card = cards.where((c) => c.title == kTitle).firstOrNull;

        final observed = <String, Object?>{
          'sourceSaved':
              closed &&
              messages.contains('Historical data added and vectorized.') &&
              stored.length == 1 &&
              doc != null &&
              doc['sourceTitle'] == kSource &&
              doc['sourceUrl'] == kSourceUrl &&
              doc['content'] == kContent &&
              doc['isApproved'] == true &&
              doc['embeddingModel'] == GeminiEmbeddingService.modelName &&
              embedCall != null &&
              embedCall.taskType == 'RETRIEVAL_DOCUMENT' &&
              embedding != null &&
              embedding.length == GeminiEmbeddingService.outputDimensions &&
              '$embedding' == '${embedCall.values}' &&
              card?.sourceLine == 'Source: $kSource',
          'correctSiteLinked':
              doc?['siteId'] == kMagellansCross.id &&
              doc?['siteName'] == kMagellansCross.name &&
              card?.siteName == kMagellansCross.name &&
              (embedCall?.text.contains('Heritage Site: ${kMagellansCross.name}') ?? false),
        };
        printOnFailure(
          'CASE-103 observed: $observed\nclosed=$closed messages=$messages\n'
          'doc=${doc == null ? null : (Map.of(doc)..remove('embedding'))}\n'
          'embedRequests=${gemini.embedRequests}\ncard=$card\n'
          'unexpectedRequests=${gemini.unexpectedRequests}',
        );
        // ignore: avoid_print
        print('CASE-103 evidence: observed=$observed siteId=${doc?['siteId']} '
            'source="${doc?['sourceTitle']}" embeddingDims=${embedding?.length}');

        // ---- Expected result (unchanged from the original CASE-103) -------
        expect(
          observed['sourceSaved'],
          equals(true),
          reason: 'CASE-103: sourceSaved does not match the real system result',
        );
        expect(
          observed['correctSiteLinked'],
          equals(true),
          reason: 'CASE-103: correctSiteLinked does not match the real system result',
        );

        await unmountApp(tester);
      }, gemini.client);
    });
  }, skip: geminiTestSkip);
}
