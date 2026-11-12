// HERITAGEBOT - TEST CASE 105
// Proponent: AI Knowledge Base / System Team
// Module: AI Knowledge Base Management
// Unit: Edit Historical Data
// Description: Edit verified historical record
// Expected: Save revised historical data
//
// TEST TYPE: Flutter widget test (host VM, no device / live Firebase /
// live Gemini).
//
// REAL CODE UNDER TEST (lib/, unmodified)
//   AuthGate -> AdminShell -> "AI Base" -> "Edit" on the record ->
//   HistoricalContentEditorScreen (pre-filled) -> revise content and source
//   -> "Save & Generate Embedding" -> KnowledgeBaseService.updateContent
//   (_validate -> embedDocument -> historical_contents/{id}.update) -> list
//   refresh.
//
// FIXTURE (fixtureId = CASE-105): a verified record for Fort San Pedro and a
// second record that must stay unchanged.
//
// MOCKED: Firebase platform layer and Gemini's embedContent endpoint
// (FakeGeminiApi). Needs the dummy GEMINI_API_KEY from
// support/unit_091_120_defines.json; otherwise SKIPPED.

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../support/admin_operations_flow.dart';
import '../support/fake_gemini_api.dart';

const String kTitle = 'Triangular Bastion Fort';
const String kOldContent =
    'Fort San Pedro is a triangular bastion fort built by Spanish colonists.';
const String kOldSource = 'Cebu City Tourism Office';
const String kNewContent =
    'Fort San Pedro is a triangular bastion fort first built of wood in 1565 '
    'under Miguel Lopez de Legazpi and rebuilt in coral stone in the 1700s.';
const String kNewSource = 'National Historical Commission of the Philippines marker';

late HeritageBotTestBackend backend;
final FakeGeminiApi gemini = FakeGeminiApi();

void main() {
  setUpAll(() async {
    backend = await HeritageBotTestBackend.install(accounts: [kAdminAccount]);
  });

  setUp(() async {
    await backend.reset();
    gemini.clear();
    seedRegisteredSites(backend, [kMagellansCross, bundledSite('fort_san_pedro')]);
    seedHistorical(backend, historicalRecord(id: 'case105-fort', site: bundledSite('fort_san_pedro'), title: kTitle, content: kOldContent, sourceTitle: kOldSource, embedding: fakeEmbeddingOf(kOldContent), updatedAtMillis: 1767225600000));
    seedHistorical(backend, historicalRecord(id: 'case105-other', site: kMagellansCross, title: 'Planting of the Cross', content: 'The cross was planted by the Magellan expedition in April 1521.', sourceTitle: 'Cebu City Tourism Office', embedding: fakeEmbeddingOf('cross planted'), updatedAtMillis: 1767139200000));
  });

  group('', () {
    testWidgets('CASE-105 - Edit verified historical record', (WidgetTester tester) async {
      await http.runWithClient(() async {
        usePhoneSurface(tester);
        const path = 'historical_contents/case105-fort';
        const otherPath = 'historical_contents/case105-other';
        final before = Map<String, dynamic>.of(storedHistorical(backend)[path]!);
        final otherBefore = '${storedHistorical(backend)[otherPath]}';

        await openAdminShell(tester);
        await openKnowledgeBaseTab(tester);
        await openEditHistoricalData(tester, kTitle);
        final prefilled = await readHistoricalField(tester, 'Verified Historical Content');

        // STEP: revise the content and the source, then save.
        await enterHistoricalField(tester, 'Verified Historical Content', kNewContent);
        await enterHistoricalField(tester, 'Source / Reference', kNewSource);
        final closed = await saveHistoricalEditor(tester);
        final messages = shownSnackBarTexts(tester);
        final cards = await knowledgeCards(tester);

        // ---- Observations -------------------------------------------------
        final stored = storedHistorical(backend);
        final after = stored[path];
        final embedding = (after?['embedding'] as List?)?.cast<num>().map((v) => v.toDouble()).toList();
        final embedCall = gemini.embedRequests.where((r) => r.text.contains(kNewContent)).firstOrNull;
        final card = cards.where((c) => c.title == kTitle).firstOrNull;

        final observed = <String, Object?>{
          'historicalDataUpdated':
              prefilled == kOldContent &&
              closed &&
              messages.contains('Historical data and embedding updated.') &&
              after?['content'] == kNewContent &&
              after?['sourceTitle'] == kNewSource &&
              embedCall != null &&
              '$embedding' == '${embedCall.values}' &&
              '$embedding' != '${before['embedding']}',
          'changesPersisted':
              stored.length == 2 &&
              after?['siteId'] == before['siteId'] &&
              after?['createdAtMillis'] == before['createdAtMillis'] &&
              (after?['updatedAtMillis'] as num) > (before['updatedAtMillis'] as num) &&
              card?.content == kNewContent &&
              card?.sourceLine == 'Source: $kNewSource' &&
              '${stored[otherPath]}' == otherBefore,
        };
        printOnFailure(
          'CASE-105 observed: $observed\nprefilled=$prefilled closed=$closed messages=$messages\n'
          'after=${after == null ? null : (Map.of(after)..remove('embedding'))}\n'
          'embedRequests=${gemini.embedRequests}\ncard=$card',
        );
        // ignore: avoid_print
        print('CASE-105 evidence: observed=$observed newSource="${after?['sourceTitle']}"');

        // ---- Expected result (unchanged from the original CASE-105) -------
        expect(
          observed['historicalDataUpdated'],
          equals(true),
          reason: 'CASE-105: historicalDataUpdated does not match the real system result',
        );
        expect(
          observed['changesPersisted'],
          equals(true),
          reason: 'CASE-105: changesPersisted does not match the real system result',
        );

        await unmountApp(tester);
      }, gemini.client);
    });
  }, skip: geminiTestSkip);
}
