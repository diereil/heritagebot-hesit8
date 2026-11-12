// HERITAGEBOT - TEST CASE 112
// Proponent: AI Knowledge Base / System Team
// Module: AI Knowledge Base Management
// Unit: View Vector Data Status
// Description: Open vector index status
// Expected: Show current indexing state
//
// TEST TYPE: Flutter widget test (host VM, no device / live Firebase).
//
// REAL CODE UNDER TEST (lib/, unmodified)
//   AuthGate -> AdminShell -> "AI Base" (AdminKnowledgeBaseScreen) ->
//   KnowledgeBaseService.getAllContent -> statusFrom -> "Vector Data Status"
//   InfoCard ("N/M records have embeddings. ...") + "Vector Ready" summary +
//   per-record vector line ("768-dimension vector" / "No vector").
//
// FIXTURE (fixtureId = CASE-112): four historical_contents records - three
// already vectorised (768 dimensions) and one record whose embedding has not
// been generated yet (empty embedding, e.g. created while the embedding API
// was unavailable). The expected status is computed from the stored records
// by the test, independently of the screen.
//
// MOCKED: Firebase platform layer only (in-memory Firestore).

import 'package:flutter_test/flutter_test.dart';

import 'package:heritagebot/models/historical_content.dart';

import '../support/admin_operations_flow.dart';
import '../support/fake_gemini_api.dart' show fakeEmbeddingOf, kFakeEmbeddingDimensions;

late HeritageBotTestBackend backend;

final List<HistoricalContent> kRecords = [
  historicalRecord(id: 'case112-a', site: kMagellansCross, title: 'Planting of the Cross', content: 'The cross was planted by the Magellan expedition in Cebu in April 1521.', sourceTitle: 'Cebu City Tourism Office', embedding: fakeEmbeddingOf('planting cross')),
  historicalRecord(id: 'case112-b', site: kMagellansCross, title: 'The Kiosk Ceiling Mural', content: 'The ceiling of the kiosk housing the cross shows a painting of the first baptism.', sourceTitle: 'Basilica Minore del Santo Nino Museum', embedding: fakeEmbeddingOf('kiosk ceiling mural')),
  historicalRecord(id: 'case112-c', site: bundledSite('fort_san_pedro'), title: 'Triangular Bastion Fort', content: 'Fort San Pedro is a triangular bastion fort built by Spanish colonists.', sourceTitle: 'National Historical Commission of the Philippines', embedding: fakeEmbeddingOf('triangular bastion')),
  historicalRecord(id: 'case112-d', site: bundledSite('fort_san_pedro'), title: 'Fort Under American Rule', content: 'During the American period the fort served as a military barracks and later a zoo.', sourceTitle: 'Cebu Provincial History Archive'),
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

  testWidgets('CASE-112 - Open vector index status', (WidgetTester tester) async {
    usePhoneSurface(tester);

    await openAdminShell(tester);
    await openKnowledgeBaseTab(tester);

    // Expected state from the stored records (independent of the UI).
    final stored = storedHistorical(backend).values.toList();
    final total = stored.length;
    final ready = stored.where((d) => (d['embedding'] as List?)?.isNotEmpty ?? false).length;
    final missing = total - ready;

    final statusCard = infoCardsTitled(tester, 'Vector Data Status').firstOrNull;
    final vectorReadyBox = knowledgeSummaryValue(tester, 'Vector Ready');
    final cards = await knowledgeCards(tester);
    final pending = cards.where((c) => c.title == 'Fort Under American Rule').firstOrNull;
    final vectorised = cards.where((c) => c.detailLine?.contains('$kFakeEmbeddingDimensions-dimension vector') ?? false).length;

    // ---- Observations -----------------------------------------------------
    final observed = <String, Object?>{
      'vectorIndexStatusVisible':
          statusCard != null && statusCard.body.contains('records have embeddings'),
      'currentStatusShown':
          statusCard != null &&
          statusCard.body ==
              '$ready/$total records have embeddings. $missing record(s) require embedding generation.' &&
          vectorReadyBox == ready &&
          vectorised == ready &&
          (pending?.detailLine?.endsWith('No vector') ?? false),
    };
    printOnFailure(
      'CASE-112 observed: $observed\nstatusCard=${statusCard?.body}\n'
      'expected ready=$ready total=$total missing=$missing vectorReadyBox=$vectorReadyBox\n'
      'cards=$cards',
    );
    // ignore: avoid_print
    print('CASE-112 evidence: observed=$observed status="${statusCard?.body}"');

    // ---- Expected result (unchanged from the original CASE-112) ----------
    expect(
      observed['vectorIndexStatusVisible'],
      equals(true),
      reason: 'CASE-112: vectorIndexStatusVisible does not match the real system result',
    );
    expect(
      observed['currentStatusShown'],
      equals(true),
      reason: 'CASE-112: currentStatusShown does not match the real system result',
    );

    await unmountApp(tester);
  });
}
