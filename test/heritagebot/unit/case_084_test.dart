// HERITAGEBOT - TEST CASE 084
// Proponent: James Stephen O. Ramos
// Module: Heritage Site Management
// Unit: Manage Heritage Sites
// Description: Open heritage site list
// Expected: Display site records
//
// TEST TYPE: Flutter widget test (host VM, no device / live Firebase).
//
// REAL CODE UNDER TEST (lib/, unmodified)
//   AuthGate -> AdminShell -> "Sites" tab (AdminHeritageSitesScreen) ->
//   HeritageSiteService.getAllSites (Firestore heritage_sites) ->
//   "Firestore Connected" card + one card per site record (name, OFFICIAL /
//   TEST SITE chip, location, coordinates, "Active in HeritageBot" switch,
//   Edit / Delete).
//
// CONTROLLED DATA (isolated in-memory Firestore)
//   heritage_sites: Magellan's Cross, Casa Gorordo Museum, Fort San Pedro
//   (inactive) and the UCLM testing site.
//
// MOCKED: Firebase platform layer only.

import 'package:flutter_test/flutter_test.dart';

import 'package:heritagebot/main.dart' as app;

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

  testWidgets('CASE-084 - Open heritage site list', (WidgetTester tester) async {
    usePhoneSurface(tester);

    // STEP: administrator -> "Sites" tab.
    await openAdminShell(tester);
    await openAdminSites(tester);
    final listed = await listedSites(tester);
    final connected = infoCardsTitled(tester, 'Firestore Connected');

    // Ground truth: heritage_sites records.
    final stored = storedSites(backend).values.toList();
    final listedByName = {for (final s in listed) s.name: s};
    final everyRecordShown = stored.every((doc) {
      final card = listedByName[doc['name']];
      return card != null &&
          card.location == doc['location'] &&
          card.typeChip == (doc['isTesting'] == true ? 'TEST SITE' : 'OFFICIAL') &&
          card.active == (doc['isActive'] != false) &&
          card.hasEdit &&
          card.hasDelete;
    });

    final observed = <String, Object?>{
      'heritageSiteListVisible':
          find.byType(app.AdminHeritageSitesScreen).evaluate().isNotEmpty &&
          textsUnder(tester, adminSitesScreen).contains('Heritage Site Management') &&
          connected.length == 1 &&
          connected.single.body.startsWith(
            '${stored.length} heritage-site records found.',
          ),
      'siteRecordsLoaded':
          stored.length == 4 &&
          listed.length == stored.length &&
          everyRecordShown,
    };
    printOnFailure(
      'CASE-084 observed: $observed\nlisted=$listed\n'
      'stored=${stored.map((d) => '${d['name']}|${d['location']}|testing=${d['isTesting']}|active=${d['isActive']}')}\n'
      'connectedCard=${connected.map((c) => c.body)}',
    );

    // ---- Expected result (unchanged from the original CASE-084) ----------
    expect(
      observed['heritageSiteListVisible'],
      equals(true),
      reason: 'CASE-084: heritageSiteListVisible does not match the real system result',
    );
    expect(
      observed['siteRecordsLoaded'],
      equals(true),
      reason: 'CASE-084: siteRecordsLoaded does not match the real system result',
    );

    await unmountApp(tester);
  });
}
