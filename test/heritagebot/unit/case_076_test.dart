// HERITAGEBOT - TEST CASE 076
// Proponent: James Stephen O. Ramos
// Module: Administrator Dashboard
// Unit: View Total Heritage Sites
// Description: Open site count metric
// Expected: Display count from heritage records
//
// TEST TYPE: Flutter widget test (host VM, no device / live Firebase).
//
// REAL CODE UNDER TEST (lib/, unmodified)
//   AuthGate -> AdminShell -> "Summary" (AdminAnalyticsScreen) ->
//   AdminAnalyticsService.loadSnapshot -> HeritageSiteService.getAllSites
//   (Firestore heritage_sites) -> "Total Heritage Sites" metric card and
//   the "Heritage Site Status" section.
//
// CONTROLLED DATA (isolated in-memory Firestore)
//   heritage_sites: 5 records - Magellan's Cross, Casa Gorordo Museum,
//   Fort San Pedro (inactive), Heritage of Cebu Monument (official) and the
//   UCLM testing site. The app also ships 4 bundled fallback sites; the
//   metric must reflect the 5 Firestore records, not the bundled list.
//
// MOCKED: Firebase platform layer only.

import 'package:flutter_test/flutter_test.dart';

import 'package:heritagebot/models/heritage_place.dart';

import '../support/admin_flow.dart';

late HeritageBotTestBackend backend;

void main() {
  setUpAll(() async {
    backend = await HeritageBotTestBackend.install(accounts: [kAdminAccount]);
  });

  setUp(() async {
    await backend.reset();
    seedRegisteredSites(backend, [
      kMagellansCross,
      bundledSite('casa_gorordo'),
      bundledSite('cebu_heritage_monument'),
      bundledSite('uclm'),
    ]);
    final fort = bundledSite('fort_san_pedro');
    backend.firestore.seedDocument('heritage_sites/${fort.id}', {
      ...fort.toMap(),
      'isActive': false,
      'createdAtMillis': 1,
      'updatedAtMillis': 1,
    });
  });

  testWidgets('CASE-076 - Open site count metric', (WidgetTester tester) async {
    usePhoneSurface(tester);

    // STEP: administrator opens the dashboard summary.
    await openAdminShell(tester);
    final view = await readAdminSummary(tester);

    // ---- Ground truth: the heritage_sites records -------------------------
    final sites = storedSites(backend).values.toList();
    final testing = sites.where((s) => s['isTesting'] == true).length;
    final official = sites.length - testing;
    final active = sites.where((s) => s['isActive'] != false).length;
    final status = view.breakdown('Heritage Site Status');

    final observed = <String, Object?>{
      'heritageSiteCountAccurate':
          sites.length == 5 &&
          sites.length != defaultHeritagePlaces.length &&
          view.metricValue('Total Heritage Sites') == '${sites.length}' &&
          view.metricSubtitle('Total Heritage Sites') ==
              '$official official • $testing testing' &&
          status['Active Sites'] == active &&
          status['Inactive Sites'] == sites.length - active &&
          status['Official Sites'] == official &&
          status['Testing Sites'] == testing,
      'siteMetricVisible':
          adminSummaryScreen.evaluate().isNotEmpty &&
          view.metrics.containsKey('Total Heritage Sites'),
    };
    printOnFailure(
      'CASE-076 observed: $observed\nstoredSites=${sites.length} '
      'official=$official testing=$testing active=$active\n'
      'metric=${view.metrics['Total Heritage Sites']} status=$status',
    );

    // ---- Expected result (unchanged from the original CASE-076) ----------
    expect(
      observed['heritageSiteCountAccurate'],
      equals(true),
      reason: 'CASE-076: heritageSiteCountAccurate does not match the real system result',
    );
    expect(
      observed['siteMetricVisible'],
      equals(true),
      reason: 'CASE-076: siteMetricVisible does not match the real system result',
    );

    await unmountApp(tester);
  });
}
