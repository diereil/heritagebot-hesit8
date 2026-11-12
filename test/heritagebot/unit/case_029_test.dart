// HERITAGEBOT - TEST CASE 029
// Proponent: Reil Esdrelon
// Module: Tourist Heritage Access
// Unit: Geolocation Detection
// Description: Remain outside site radius.
// Expected: Do not trigger incorrect site narrative.
//
// TEST TYPE: Flutter widget test (host VM, no device / live Firebase).
//
// REAL CODE UNDER TEST (lib/, unmodified)
//   GeolocationScreen.startLiveTracking / live position stream ->
//   handleNewPosition -> nearestPlace / distanceToPlace -> radius check.
//
// FIXTURE: the tourist is in Bogo City, northern Cebu, and stays there
// (initial fix + a later live-stream fix). Every bundled site is farther
// away than its 20 km detectionRadiusMeters - verified below with the same
// Geolocator.distanceBetween the app uses.
//
// MOCKED: Firebase platform layer, GeolocatorPlatform, flutter_tts channel.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

import 'package:heritagebot/main.dart' as app;
import 'package:heritagebot/models/heritage_place.dart';

import '../support/heritagebot_test_harness.dart';

const FakeAuthAccount kTourist = FakeAuthAccount(
  uid: 'case029-tourist-uid',
  email: 'case029.tourist@heritagebot.test',
  password: 'Case029Pass!',
  displayName: 'Case 029 Tourist',
);

const double kLat = 11.05170; // Bogo City, Cebu
const double kLng = 124.00550;

late HeritageBotTestBackend backend;

void main() {
  setUpAll(() async {
    backend = await HeritageBotTestBackend.install(accounts: [kTourist]);
  });

  setUp(() async {
    await backend.reset();
    backend.seedTourist(kTourist);
    backend.geolocator
      ..serviceEnabled = true
      ..permission = LocationPermission.whileInUse
      ..currentFix = fakeGpsFix(latitude: kLat, longitude: kLng, accuracy: 5);
  });

  testWidgets('CASE-029 - Remain outside every site radius: no site narrative '
      'is triggered', (WidgetTester tester) async {
    usePhoneSurface(tester);

    // Fixture check: outside every configured radius.
    for (final site in heritagePlaces) {
      final d = Geolocator.distanceBetween(kLat, kLng, site.lat, site.lng);
      expect(d, greaterThan(site.detectionRadiusMeters),
          reason: 'Fixture must be outside ${site.name}');
    }

    await signInBeforeLaunch(kTourist);
    await launchAuthGate(tester, until: app.MainShell);

    await tapNavDestination(tester, en('geolocation'));
    await pumpUntilFound(tester, find.byType(app.GeolocationScreen));
    await pumpUntilFound(tester, find.textContaining('${en('nearest')}: '));

    // A later live update, still outside the radius.
    backend.geolocator.liveFixes.add(
        fakeGpsFix(latitude: kLat + 0.0005, longitude: kLng, accuracy: 5));
    await pumpFor(tester, const Duration(seconds: 2));

    // ---- Observations ---------------------------------------------------
    final siteDetected = find.byType(BottomSheet).evaluate().isNotEmpty ||
        find.byType(app.NarrativeAutoPlaybackPanel).evaluate().isNotEmpty;
    final incorrectNarrativeTriggered = siteDetected ||
        backend.channels.spokenTexts.isNotEmpty;

    // ---- Expected result -------------------------------------------------
    expect(siteDetected, isFalse,
        reason: 'CASE-029: no site may be detected outside its radius.');
    expect(incorrectNarrativeTriggered, isFalse,
        reason: 'CASE-029: no narrative may be shown or spoken.');

    // Supporting evidence: tracking still works (status shows the nearest
    // site and its distance; the user marker is on the map).
    expect(find.textContaining('${en('nearest')}: '), findsOneWidget);
    expect(find.byIcon(Icons.navigation_rounded), findsOneWidget);
    expect(find.textContaining(en('failedLocation')), findsNothing);

    await unmountApp(tester);
  });
}
