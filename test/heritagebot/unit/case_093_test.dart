// HERITAGEBOT - TEST CASE 093
// Proponent: Shawn Guillmar C. Morales
// Module: Heritage Site Management
// Unit: Manage Location Coordinates
// Description: Save invalid coordinates
// Expected: Reject out-of-range coordinates
//
// TEST TYPE: Flutter widget test (host VM, no device / live Firebase).
//
// REAL CODE UNDER TEST (lib/, unmodified)
//   AuthGate -> AdminShell -> "Sites" -> "Edit" on Magellan's Cross ->
//   HeritageSiteEditorScreen ("Latitude" / "Longitude") -> "Save Heritage
//   Site" -> _save -> HeritageSiteService.updateSite -> _validateSite
//   (latitude -90..90, longitude -180..180) -> error SnackBar.
//
// INPUT: latitude 123.0, longitude 240.0 (both outside the valid range).
//
// MOCKED: Firebase platform layer only (in-memory Firestore).

import 'package:flutter_test/flutter_test.dart';

import 'package:heritagebot/models/heritage_place.dart';

import '../support/admin_flow.dart';

const double kLatitude = 123.0;
const double kLongitude = 240.0;

/// A message that explains the coordinate is out of range / invalid.
final RegExp kCoordinateError = RegExp(
  r'(latitude|longitude).*(between|range|invalid|valid)|'
  r'(between|range|invalid|valid).*(latitude|longitude)',
  caseSensitive: false,
);

late HeritageBotTestBackend backend;

void main() {
  setUpAll(() async {
    backend = await HeritageBotTestBackend.install(accounts: [kAdminAccount]);
  });

  setUp(() async {
    await backend.reset();
    seedRegisteredSites(backend, [kMagellansCross, bundledSite('casa_gorordo')]);
  });

  testWidgets('CASE-093 - Save invalid coordinates', (WidgetTester tester) async {
    usePhoneSurface(tester);
    final path = 'heritage_sites/${kMagellansCross.id}';
    final before = '${storedSites(backend)[path]}';

    await openAdminShell(tester);
    await openAdminSites(tester);
    await openSiteEditor(tester, siteName: kMagellansCross.name);

    // STEP: enter out-of-range coordinates and save.
    await enterEditorField(tester, 'Latitude', '$kLatitude');
    await enterEditorField(tester, 'Longitude', '$kLongitude');
    final closed = await saveSiteEditor(tester);
    final messages = shownSnackBarTexts(tester);

    // ---- Observations -----------------------------------------------------
    final doc = storedSites(backend)[path];
    final runtime = heritagePlaces.where((p) => p.id == kMagellansCross.id).firstOrNull;
    final observed = <String, Object?>{
      'coordinatesSaved':
          (doc?['lat'] as num?)?.toDouble() == kLatitude ||
          (doc?['lng'] as num?)?.toDouble() == kLongitude ||
          '$doc' != before ||
          runtime?.lat == kLatitude ||
          runtime?.lng == kLongitude ||
          messages.contains('Heritage site updated.'),
      'coordinateErrorVisible':
          !closed && messages.any(kCoordinateError.hasMatch),
    };
    printOnFailure(
      'CASE-093 observed: $observed\nclosed=$closed messages=$messages\n'
      'before=$before\nafter=$doc',
    );

    // ignore: avoid_print
    print('CASE-093 evidence: observed=$observed');
    // ---- Expected result (unchanged from the original CASE-093) ----------
    expect(
      observed['coordinatesSaved'],
      equals(false),
      reason: 'CASE-093: coordinatesSaved does not match the real system result',
    );
    expect(
      observed['coordinateErrorVisible'],
      equals(true),
      reason: 'CASE-093: coordinateErrorVisible does not match the real system result',
    );

    await unmountApp(tester);
  });
}
