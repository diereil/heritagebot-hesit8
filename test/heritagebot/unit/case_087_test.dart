// HERITAGEBOT - TEST CASE 087
// Proponent: James Stephen O. Ramos
// Module: Heritage Site Management
// Unit: Edit Heritage Site
// Description: Update existing site details
// Expected: Save edited heritage site
//
// TEST TYPE: Flutter widget test (host VM, no device / live Firebase).
//
// REAL CODE UNDER TEST (lib/, unmodified)
//   AuthGate -> AdminShell -> "Sites" (AdminHeritageSitesScreen) -> "Edit"
//   on Magellan's Cross -> HeritageSiteEditorScreen (pre-filled) ->
//   "Save Heritage Site" -> HeritageSiteService.updateSite
//   (heritage_sites/{id}.update, refreshRuntimeSites) -> back to the list.
//
// INPUT: new Location / Address, Detection Radius and Historical
// Information for the existing "magellans_cross" record.
//
// MOCKED: Firebase platform layer only.

import 'package:flutter_test/flutter_test.dart';

import 'package:heritagebot/models/heritage_place.dart';

import '../support/admin_flow.dart';

const String kNewLocation = 'Magallanes corner P. Burgos Street, Cebu City';
const String kNewRadius = '750';
const String kNewFacts =
    "Magellan's Cross was planted in 1521 by Ferdinand Magellan's expedition. "
    'The original cross is said to be encased in the tindalo wood cross that '
    'visitors see today inside the octagonal chapel.';

late HeritageBotTestBackend backend;

void main() {
  setUpAll(() async {
    backend = await HeritageBotTestBackend.install(accounts: [kAdminAccount]);
  });

  setUp(() async {
    await backend.reset();
    seedRegisteredSites(backend, [kMagellansCross, bundledSite('casa_gorordo')]);
  });

  testWidgets('CASE-087 - Update existing site details', (
    WidgetTester tester,
  ) async {
    usePhoneSurface(tester);
    await openAdminShell(tester);
    await openAdminSites(tester);
    final path = 'heritage_sites/${kMagellansCross.id}';
    final before = Map<String, dynamic>.of(storedSites(backend)[path]!);
    final countBefore = storedSites(backend).length;

    // STEP: "Edit" Magellan's Cross; the editor shows the stored values.
    await openSiteEditor(tester, siteName: kMagellansCross.name);
    final prefilledName = await readEditorField(tester, 'Site Name');
    final prefilledLocation = await readEditorField(tester, 'Location / Address');

    // STEP: change details and save.
    await enterEditorField(tester, 'Location / Address', kNewLocation);
    await enterEditorField(tester, 'Detection Radius (meters)', kNewRadius);
    await enterEditorField(tester, 'Historical Information', kNewFacts);
    final closed = await saveSiteEditor(tester);
    final messages = shownSnackBarTexts(tester);
    final listed = await listedSites(tester);

    // ---- Observations -----------------------------------------------------
    final stored = storedSites(backend);
    final after = stored[path];
    final runtime = heritagePlaces.where((p) => p.id == kMagellansCross.id);

    final observed = <String, Object?>{
      'heritageSiteUpdated':
          prefilledName == before['name'] &&
          prefilledLocation == before['location'] &&
          closed &&
          messages.contains('Heritage site updated.') &&
          stored.length == countBefore &&
          after != null,
      'changesPersisted':
          after != null &&
          after['location'] == kNewLocation &&
          after['detectionRadiusMeters'] == 750.0 &&
          after['historicalFacts'] == kNewFacts &&
          after['name'] == before['name'] &&
          after['lat'] == before['lat'] &&
          after['lng'] == before['lng'] &&
          after['createdAtMillis'] == before['createdAtMillis'] &&
          (after['updatedAtMillis'] as int) > (before['updatedAtMillis'] as int) &&
          listed.any((s) => s.name == kMagellansCross.name && s.location == kNewLocation) &&
          runtime.length == 1 &&
          runtime.single.location == kNewLocation,
    };
    printOnFailure(
      'CASE-087 observed: $observed\nprefilled name=$prefilledName '
      'location=$prefilledLocation\nclosed=$closed messages=$messages\n'
      'before=$before\nafter=$after\nlisted=$listed',
    );

    // ---- Expected result (unchanged from the original CASE-087) ----------
    expect(
      observed['heritageSiteUpdated'],
      equals(true),
      reason: 'CASE-087: heritageSiteUpdated does not match the real system result',
    );
    expect(
      observed['changesPersisted'],
      equals(true),
      reason: 'CASE-087: changesPersisted does not match the real system result',
    );

    await unmountApp(tester);
  });
}
