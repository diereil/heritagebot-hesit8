// HERITAGEBOT - TEST CASE 104
// Proponent: AI Knowledge Base / System Team
// Module: AI Knowledge Base Management
// Unit: Add Historical Data
// Description: Add historical data without source
// Expected: Require source information
//
// TEST TYPE: Flutter widget test (host VM, no device / live Firebase /
// live Gemini).
//
// REAL CODE UNDER TEST (lib/, unmodified)
//   AuthGate -> AdminShell -> "AI Base" -> FAB "Add Historical Data" ->
//   HistoricalContentEditorScreen -> "Save & Generate Embedding" with an
//   empty "Source / Reference" -> KnowledgeBaseService.addContent ->
//   _validate (sourceTitle >= 3 chars) -> error SnackBar.
//
// INPUT (historicalSource = ''): valid title and content, no source.
// The dummy Gemini key is compiled in, so a rejection cannot come from a
// missing API key - only from HeritageBot's own source validation.
//
// MOCKED: Firebase platform layer and Gemini's embedContent endpoint
// (FakeGeminiApi). Needs the dummy GEMINI_API_KEY from
// support/unit_091_120_defines.json; otherwise SKIPPED.

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../support/admin_operations_flow.dart';
import '../support/fake_gemini_api.dart';

const String kTitle = 'Arrival of the Magellan Expedition';
const String kContent =
    'On 7 April 1521 the Magellan expedition arrived in Cebu and a wooden '
    'cross was planted near the shore.';

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
  });

  group('', () {
    testWidgets('CASE-104 - Add historical data without source', (WidgetTester tester) async {
      await http.runWithClient(() async {
        usePhoneSurface(tester);

        await openAdminShell(tester);
        await openKnowledgeBaseTab(tester);
        await openAddHistoricalData(tester);

        // STEP: fill everything except the source, then save.
        await enterHistoricalField(tester, 'Historical Data Title', kTitle);
        await enterHistoricalField(tester, 'Verified Historical Content', kContent);
        await enterHistoricalField(tester, 'Source / Reference', '');
        final closed = await saveHistoricalEditor(tester);
        final messages = shownSnackBarTexts(tester);

        // ---- Observations -------------------------------------------------
        final stored = storedHistorical(backend);
        final observed = <String, Object?>{
          'sourceSaved': stored.isNotEmpty || gemini.embedRequests.isNotEmpty || closed,
          'sourceRequiredVisible':
              !closed &&
              historicalEditorScreen.evaluate().isNotEmpty &&
              messages.any((m) => RegExp(r'source', caseSensitive: false).hasMatch(m)),
        };
        printOnFailure(
          'CASE-104 observed: $observed\nclosed=$closed messages=$messages\n'
          'stored=${stored.keys} embedRequests=${gemini.embedRequests}',
        );
        // ignore: avoid_print
        print('CASE-104 evidence: observed=$observed messages=$messages');

        // ---- Expected result (unchanged from the original CASE-104) -------
        expect(
          observed['sourceSaved'],
          equals(false),
          reason: 'CASE-104: sourceSaved does not match the real system result',
        );
        expect(
          observed['sourceRequiredVisible'],
          equals(true),
          reason: 'CASE-104: sourceRequiredVisible does not match the real system result',
        );

        await unmountApp(tester);
      }, gemini.client);
    });
  }, skip: geminiTestSkip);
}
