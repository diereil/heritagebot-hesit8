// HERITAGEBOT - TEST CASE 102
// Proponent: AI Knowledge Base / System Team
// Module: AI Knowledge Base Management
// Unit: Manage AI Knowledge Base
// Description: Open historical data records
// Expected: Display stored historical records
//
// TEST TYPE: Flutter widget test (host VM, no device / live Firebase).
//
// REAL CODE UNDER TEST (lib/, unmodified)
//   AuthGate -> AdminShell -> "AI Base" (AdminKnowledgeBaseScreen) ->
//   KnowledgeBaseService.getAllContent (historical_contents) -> statusFrom ->
//   summary boxes ("Records", "Approved", "Vector Ready", "Community") and one
//   card per record (title, site, content, "Source: ...", type line).
//
// FIXTURE (fixtureId = CASE-102): three historical_contents records stored
// exactly as KnowledgeBaseService.addContent / syncApprovedCommunityStories
// write them - two curated records (Magellan's Cross, Fort San Pedro) and
// one synced community story - each with a 768-dimension embedding.
// Opening the list makes no Gemini request.
//
// MOCKED: Firebase platform layer only (in-memory Firestore).

import 'package:flutter_test/flutter_test.dart';

import 'package:heritagebot/models/historical_content.dart';

import '../support/admin_operations_flow.dart';
import '../support/fake_gemini_api.dart' show fakeEmbeddingOf;

late HeritageBotTestBackend backend;

final List<HistoricalContent> kRecords = [
  historicalRecord(
    id: 'case102-cross',
    site: kMagellansCross,
    title: 'Planting of the Cross in 1521',
    content: 'The cross was planted by the Magellan expedition on the orders of '
        'Ferdinand Magellan when the expedition arrived in Cebu in April 1521.',
    sourceTitle: 'Cebu City Tourism Office heritage marker',
    embedding: fakeEmbeddingOf('planting cross 1521'),
    updatedAtMillis: 1767398400000,
  ),
  historicalRecord(
    id: 'case102-fort',
    site: bundledSite('fort_san_pedro'),
    title: 'Triangular Bastion Fort',
    content: 'Fort San Pedro is a triangular bastion fort built by Spanish '
        'colonists under Miguel Lopez de Legazpi and later rebuilt in stone.',
    sourceTitle: 'National Historical Commission of the Philippines',
    sourceUrl: 'https://nhcp.gov.ph/',
    embedding: fakeEmbeddingOf('triangular bastion fort'),
    updatedAtMillis: 1767312000000,
  ),
  historicalRecord(
    id: 'community_case102-story',
    site: kMagellansCross,
    title: 'Candles at the Cross',
    content: 'Every Friday my grandmother lit candles at the kiosk of the cross '
        'and told us how her own mother had done the same before the war.',
    sourceTitle: 'Approved community story by Maria Santos',
    category: 'community_story',
    sourceType: 'community',
    sourceRefId: 'case102-story',
    embedding: fakeEmbeddingOf('candles kiosk grandmother'),
    updatedAtMillis: 1767225600000,
  ),
];

void main() {
  setUpAll(() async {
    backend = await HeritageBotTestBackend.install(accounts: [kAdminAccount]);
  });

  setUp(() async {
    await backend.reset();
    seedRegisteredSites(backend, [kMagellansCross, bundledSite('fort_san_pedro')]);
    for (final record in kRecords) {
      seedHistorical(backend, record);
    }
  });

  testWidgets('CASE-102 - Open historical data records', (WidgetTester tester) async {
    usePhoneSurface(tester);

    await openAdminShell(tester);
    await openKnowledgeBaseTab(tester);
    final cards = await knowledgeCards(tester);
    final summary = <String, int?>{
      for (final label in ['Records', 'Approved', 'Vector Ready', 'Community'])
        label: knowledgeSummaryValue(tester, label),
    };
    final errorShown = infoCardsTitled(tester, 'Could Not Load Knowledge Base').isNotEmpty;
    final emptyShown = infoCardsTitled(tester, 'Knowledge Base Is Empty').isNotEmpty;

    // ---- Observations -----------------------------------------------------
    bool cardMatches(HistoricalContent r) => cards.any(
      (c) =>
          c.title == r.title &&
          c.siteName == r.siteName &&
          c.content == r.content &&
          c.sourceLine == 'Source: ${r.sourceTitle}' &&
          (c.detailLine?.contains('${r.embedding.length}-dimension vector') ?? false) &&
          (c.detailLine?.contains(r.sourceType == 'community' ? 'Community source' : 'Curated source') ?? false),
    );
    final stored = storedHistorical(backend);

    final observed = <String, Object?>{
      'historicalRecordsVisible':
          !errorShown &&
          !emptyShown &&
          cards.length == kRecords.length &&
          kRecords.every((r) => cards.any((c) => c.title == r.title)),
      'recordsLoaded':
          stored.length == kRecords.length &&
          kRecords.every(cardMatches) &&
          summary['Records'] == 3 &&
          summary['Approved'] == 3 &&
          summary['Vector Ready'] == 3 &&
          summary['Community'] == 1 &&
          // newest first (KnowledgeBaseService sorts by updatedAtMillis desc)
          cards.first.title == kRecords.first.title,
    };
    printOnFailure(
      'CASE-102 observed: $observed\ncards=$cards\nsummary=$summary '
      'errorShown=$errorShown emptyShown=$emptyShown',
    );
    // ignore: avoid_print
    print('CASE-102 evidence: observed=$observed summary=$summary titles=${cards.map((c) => c.title).toList()}');

    // ---- Expected result (unchanged from the original CASE-102) ----------
    expect(
      observed['historicalRecordsVisible'],
      equals(true),
      reason: 'CASE-102: historicalRecordsVisible does not match the real system result',
    );
    expect(
      observed['recordsLoaded'],
      equals(true),
      reason: 'CASE-102: recordsLoaded does not match the real system result',
    );

    await unmountApp(tester);
  });
}
