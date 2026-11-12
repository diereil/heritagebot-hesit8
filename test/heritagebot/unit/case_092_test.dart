// HERITAGEBOT - TEST CASE 092
// Proponent: Shawn Guillmar C. Morales
// Module: Heritage Site Management
// Unit: Manage Location Coordinates
// Description: Save valid site coordinates
// Expected: Store site latitude and longitude
//
// TEST TYPE: Flutter widget test (host VM, no device / live Firebase).
//
// REAL CODE UNDER TEST (lib/, unmodified)
//   AuthGate -> AdminShell -> "Sites" -> "Edit" on Magellan's Cross ->
//   HeritageSiteEditorScreen ("Latitude" / "Longitude" fields) ->
//   "Save Heritage Site" -> _save (double.tryParse) ->
//   HeritageSiteService.updateSite (_validateSite: -90..90 / -180..180) ->
//   heritage_sites/{id}.update -> refreshRuntimeSites -> site list card
//   ("Lat .. • Lng .. • Radius .. m").
//
// INPUT: latitude 10.2964, longitude 123.9025 (Cebu City).
//
// MOCKED: Firebase platform layer only (in-memory Firestore).

import 'package:flutter_test/flutter_test.dart';

import 'package:heritagebot/models/heritage_place.dart';

import '../support/admin_flow.dart';

const double kLatitude = 10.2964;
const double kLongitude = 123.9025;

late HeritageBotTestBackend backend;

void main() {
  setUpAll(() async {
    backend = await HeritageBotTestBackend.install(accounts: [kAdminAccount]);
  });

  setUp(() async {
    await backend.reset();
    seedRegisteredSites(backend, [kMagellansCross, bundledSite('casa_gorordo')]);
  });

  testWidgets('CASE-092 - Save valid site coordinates', (WidgetTester tester) async {
    usePhoneSurface(tester);
    final path = 'heritage_sites/${kMagellansCross.id}';
    final otherPath = 'heritage_sites/casa_gorordo';
    final otherBefore = '${storedSites(backend)[otherPath]}';

    await openAdminShell(tester);
    await openAdminSites(tester);
    await openSiteEditor(tester, siteName: kMagellansCross.name);

    // STEP: enter the new coordinates and save.
    await enterEditorField(tester, 'Latitude', '$kLatitude');
    await enterEditorField(tester, 'Longitude', '$kLongitude');
    final closed = await saveSiteEditor(tester);
    final messages = shownSnackBarTexts(tester);
    final listed = await listedSites(tester);

    // ---- Observations -----------------------------------------------------
    final doc = storedSites(backend)[path];
    final lat = (doc?['lat'] as num?)?.toDouble();
    final lng = (doc?['lng'] as num?)?.toDouble();
    final card = listed.where((s) => s.name == kMagellansCross.name).firstOrNull;
    final runtime = heritagePlaces.where((p) => p.id == kMagellansCross.id).firstOrNull;

    final observed = <String, Object?>{
      'coordinatesSaved':
          closed &&
          messages.contains('Heritage site updated.') &&
          lat == kLatitude &&
          lng == kLongitude &&
          card != null &&
          card.coordinates.contains('Lat ${kLatitude.toStringAsFixed(5)}') &&
          card.coordinates.contains('Lng ${kLongitude.toStringAsFixed(5)}') &&
          runtime?.lat == kLatitude &&
          runtime?.lng == kLongitude &&
          '${storedSites(backend)[otherPath]}' == otherBefore,
      'coordinatesInValidRange':
          lat != null &&
          lng != null &&
          lat >= -90 &&
          lat <= 90 &&
          lng >= -180 &&
          lng <= 180,
    };
    printOnFailure(
      'CASE-092 observed: $observed\nclosed=$closed messages=$messages\n'
      'storedLat=$lat storedLng=$lng\ncard=$card\nruntime=${runtime?.lat},${runtime?.lng}',
    );

    // ignore: avoid_print
    print('CASE-092 evidence: observed=$observed');
    // ---- Expected result (unchanged from the original CASE-092) ----------
    expect(
      observed['coordinatesSaved'],
      equals(true),
      reason: 'CASE-092: coordinatesSaved does not match the real system result',
    );
    expect(
      observed['coordinatesInValidRange'],
      equals(true),
      reason: 'CASE-092: coordinatesInValidRange does not match the real system result',
    );

    await unmountApp(tester);
  });
}
