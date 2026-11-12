// HERITAGEBOT - TEST CASE 085
// Proponent: James Stephen O. Ramos
// Module: Heritage Site Management
// Unit: Add Heritage Site
// Description: Enter valid site information
// Expected: Save new heritage site
//
// TEST TYPE: Flutter widget test (host VM, no device / live Firebase).
//
// REAL CODE UNDER TEST (lib/, unmodified)
//   AuthGate -> AdminShell -> "Sites" (AdminHeritageSitesScreen) ->
//   "Add Site" -> HeritageSiteEditorScreen -> "Save Heritage Site" ->
//   HeritageSiteService.createSite (_validateSite, _availableId slug,
//   heritage_sites/{id}.set, refreshRuntimeSites) -> back to the list.
//
// INPUT (valid site information)
//   Site Name: Basilica del Santo Nino
//   Location / Address: Osmena Boulevard, Cebu City
//   Latitude / Longitude: 10.29436 / 123.90207
//   Detection Radius: 500 m
//   Historical Information: >= 20 characters
//   Wikipedia / Reference Title: Basilica del Santo Nino
//
// MOCKED: Firebase platform layer only.

import 'package:flutter_test/flutter_test.dart';

import 'package:heritagebot/models/heritage_place.dart';

import '../support/admin_flow.dart';

const String kName = 'Basilica del Santo Nino';
const String kLocation = 'Osmena Boulevard, Cebu City';
const String kFacts =
    'The Basilica Minore del Santo Nino was founded in 1565 and is the oldest '
    'Roman Catholic church in the Philippines, built on the spot where the '
    'image of the Santo Nino was found.';
const String kExpectedId = 'basilica_del_santo_nino';

late HeritageBotTestBackend backend;

void main() {
  setUpAll(() async {
    backend = await HeritageBotTestBackend.install(accounts: [kAdminAccount]);
  });

  setUp(() async {
    await backend.reset();
    seedRegisteredSites(backend, [kMagellansCross, bundledSite('casa_gorordo')]);
  });

  testWidgets('CASE-085 - Enter valid site information', (
    WidgetTester tester,
  ) async {
    usePhoneSurface(tester);
    await openAdminShell(tester);
    await openAdminSites(tester);
    final countBefore = storedSites(backend).length;

    // STEP: "Add Site" and enter valid information.
    await openSiteEditor(tester);
    await enterEditorField(tester, 'Site Name', kName);
    await enterEditorField(tester, 'Location / Address', kLocation);
    await enterEditorField(tester, 'Latitude', '10.29436');
    await enterEditorField(tester, 'Longitude', '123.90207');
    await enterEditorField(tester, 'Detection Radius (meters)', '500');
    await enterEditorField(tester, 'Historical Information', kFacts);
    await enterEditorField(tester, 'Wikipedia / Reference Title', kName);

    // STEP: "Save Heritage Site".
    final closed = await saveSiteEditor(tester);
    final messages = shownSnackBarTexts(tester);
    final listed = await listedSites(tester);

    // ---- Observations -----------------------------------------------------
    final stored = storedSites(backend);
    final doc = stored['heritage_sites/$kExpectedId'];
    final savedCorrectly =
        doc != null &&
        doc['id'] == kExpectedId &&
        doc['name'] == kName &&
        doc['location'] == kLocation &&
        doc['lat'] == 10.29436 &&
        doc['lng'] == 123.90207 &&
        doc['detectionRadiusMeters'] == 500.0 &&
        doc['historicalFacts'] == kFacts &&
        doc['wikipediaTitle'] == kName &&
        doc['isActive'] == true &&
        doc['isTesting'] == false &&
        doc['createdAtMillis'] is int;

    final observed = <String, Object?>{
      'heritageSiteSaved':
          closed &&
          messages.contains('Heritage site added.') &&
          stored.length == countBefore + 1 &&
          savedCorrectly,
      'siteVisibleInRecords':
          listed.any((s) => s.name == kName && s.location == kLocation) &&
          heritagePlaces.any((p) => p.id == kExpectedId),
    };
    printOnFailure(
      'CASE-085 observed: $observed\nclosed=$closed messages=$messages\n'
      'storedDoc=$doc\ncountBefore=$countBefore countAfter=${stored.length}\n'
      'listed=$listed\nruntimeSites=${heritagePlaces.map((p) => p.id)}\n'
      'heroTagDefectsObserved=$heroTagDefectsObserved',
    );

    // ---- Expected result (unchanged from the original CASE-085) ----------
    expect(
      observed['heritageSiteSaved'],
      equals(true),
      reason: 'CASE-085: heritageSiteSaved does not match the real system result',
    );
    expect(
      observed['siteVisibleInRecords'],
      equals(true),
      reason: 'CASE-085: siteVisibleInRecords does not match the real system result',
    );

    await unmountApp(tester);
  });
}
