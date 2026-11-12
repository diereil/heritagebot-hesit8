// HERITAGEBOT - TEST CASE 030
// Proponent: Reil Esdrelon
// Module: Tourist Heritage Access
// Unit: Geolocation Detection
// Description: Receive inaccurate GPS reading.
// Expected: Avoid false location confirmation (and warn about GPS accuracy).
//
// TEST TYPE: Flutter widget test (host VM, no device / live Firebase).
//
// REAL CODE UNDER TEST (lib/, unmodified)
//   GeolocationScreen.handleNewPosition -> nearestPlace / distanceToPlace ->
//   `if (distance <= place.detectionRadiusMeters)` -> showPlacePopup.
//
// FIXTURE (poor GPS accuracy)
// The device reports a fix 19.9 km west of the official site "Heritage of
// Cebu Monument" (its trigger radius is 20 km) with a horizontal accuracy
// of +/- 3,000 m (Position.accuracy). With that uncertainty the tourist may
// really be up to ~2.9 km OUTSIDE the radius, so the reading cannot confirm
// that the tourist is at the site. The fixture geometry is checked below
// with the same Geolocator.distanceBetween the app uses.
//
// The test only observes what the real screen does with such a reading.
//
// MOCKED: Firebase platform layer, GeolocatorPlatform, flutter_tts channel.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

import 'package:heritagebot/main.dart' as app;
import 'package:heritagebot/models/heritage_place.dart';

import '../support/heritagebot_test_harness.dart';

const FakeAuthAccount kTourist = FakeAuthAccount(
  uid: 'case030-tourist-uid',
  email: 'case030.tourist@heritagebot.test',
  password: 'Case030Pass!',
  displayName: 'Case 030 Tourist',
);

const double kAccuracyMeters = 3000;

late HeritageBotTestBackend backend;
late HeritagePlace site;
late double fixLat;
late double fixLng;

void main() {
  setUpAll(() async {
    backend = await HeritageBotTestBackend.install(accounts: [kTourist]);
  });

  setUp(() async {
    await backend.reset();
    backend.seedTourist(kTourist);
    site = defaultHeritagePlaces
        .singleWhere((s) => s.id == 'cebu_heritage_monument');
    fixLat = site.lat;
    fixLng = 123.72193; // ~19.9 km due west of the monument
    backend.geolocator
      ..serviceEnabled = true
      ..permission = LocationPermission.whileInUse
      ..currentFix = fakeGpsFix(
          latitude: fixLat, longitude: fixLng, accuracy: kAccuracyMeters);
  });

  testWidgets('CASE-030 - Inaccurate GPS reading: no false location '
      'confirmation', (WidgetTester tester) async {
    usePhoneSurface(tester);

    // Fixture check: reported point is inside the radius, but the accuracy
    // circle extends beyond it, and the monument is the nearest site.
    final reported =
        Geolocator.distanceBetween(fixLat, fixLng, site.lat, site.lng);
    expect(reported, inInclusiveRange(19500, 19999));
    expect(reported + kAccuracyMeters, greaterThan(site.detectionRadiusMeters));
    for (final other in heritagePlaces.where((s) => s.id != site.id)) {
      expect(Geolocator.distanceBetween(fixLat, fixLng, other.lat, other.lng),
          greaterThan(reported));
    }

    await signInBeforeLaunch(kTourist);
    await launchAuthGate(tester, until: app.MainShell);

    await tapNavDestination(tester, en('geolocation'));
    await pumpUntilFound(tester, find.byType(app.GeolocationScreen));
    await pumpFor(tester, const Duration(seconds: 3));

    // ---- Observations ---------------------------------------------------
    final narrativeOpened = find.byType(BottomSheet).evaluate().isNotEmpty &&
        find
            .descendant(
                of: find.byType(BottomSheet), matching: find.text(site.name))
            .evaluate()
            .isNotEmpty;
    final falsePositiveDetection =
        narrativeOpened || backend.channels.spokenTexts.isNotEmpty;
    final gpsAccuracyWarningVisible = find
        .textContaining(RegExp(
          r'accura|inaccurate|weak gps|gps signal|location uncertain',
          caseSensitive: false,
        ))
        .evaluate()
        .isNotEmpty;

    printOnFailure(
      'CASE-030 observed: reportedDistance=${reported.toStringAsFixed(0)} m, '
      'accuracy=±${kAccuracyMeters.toStringAsFixed(0)} m, '
      'narrativeOpenedFor="${narrativeOpened ? site.name : '-'}", '
      'spokenNarratives=${backend.channels.spokenTexts.length}, '
      'gpsAccuracyWarningVisible=$gpsAccuracyWarningVisible',
    );

    // ---- Expected result -------------------------------------------------
    expect(falsePositiveDetection, isFalse,
        reason: 'CASE-030: an inaccurate reading must not confirm the site.');
    expect(gpsAccuracyWarningVisible, isTrue,
        reason: 'CASE-030: the user must be warned about poor GPS accuracy.');

    await unmountApp(tester);
  });
}
