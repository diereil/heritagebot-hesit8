// HERITAGEBOT - TEST CASE 025
// Proponent: Reil Esdrelon
// Module: Tourist Heritage Access
// Unit: Live Geolocation Map
// Description: Grant location permission.
// Expected: Show current location on map.
//
// TEST TYPE: Flutter widget test (host VM, no device / live Firebase).
//
// REAL CODE UNDER TEST (lib/, unmodified)
//   MainShell "Geolocation" tab -> GeolocationScreen.startLiveTracking ->
//   LocationService (main.dart) ensurePermission / getCurrentPosition ->
//   handleNewPosition -> FlutterMap MarkerLayer (user marker) + status text.
//
// MOCKED: Firebase platform layer and the device location layer
// (GeolocatorPlatform): GPS on, permission not yet granted, user taps
// "Allow" in the OS dialog, device reports one GPS fix.
//
// FIXTURE: the fix is in Bogo City, northern Cebu - farther than every
// site's 20 km trigger radius - so this case isolates the map display and
// no narrative pop-up is involved (that is CASE-028).

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';

import 'package:heritagebot/main.dart' as app;

import '../support/heritagebot_test_harness.dart';

const FakeAuthAccount kTourist = FakeAuthAccount(
  uid: 'case025-tourist-uid',
  email: 'case025.tourist@heritagebot.test',
  password: 'Case025Pass!',
  displayName: 'Case 025 Tourist',
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
      ..permission = LocationPermission.denied // not granted yet
      ..userResponseToPermissionDialog = LocationPermission.whileInUse
      ..currentFix = fakeGpsFix(latitude: kLat, longitude: kLng, accuracy: 5);
  });

  testWidgets('CASE-025 - Grant location permission: current location is '
      'shown on the map', (WidgetTester tester) async {
    usePhoneSurface(tester);

    await signInBeforeLaunch(kTourist);
    await launchAuthGate(tester, until: app.MainShell);

    // STEP 1: Open the real Geolocation tab; the tourist allows location.
    await tapNavDestination(tester, en('geolocation'));
    await pumpUntilFound(tester, find.byType(app.GeolocationScreen));
    await pumpUntilFound(
        tester, find.textContaining('${en('nearest')}: '));
    await pumpFor(tester, const Duration(milliseconds: 500));

    // ---- Observations ---------------------------------------------------
    final markers = tester
        .widgetList<MarkerLayer>(find.byType(MarkerLayer))
        .expand((layer) => layer.markers)
        .toList();
    final userMarkerAtFix = markers.any((m) =>
        m.point.latitude == kLat &&
        m.point.longitude == kLng &&
        m.child is Icon &&
        (m.child as Icon).icon == Icons.navigation_rounded);
    final currentLocationVisible = userMarkerAtFix &&
        find.byIcon(Icons.navigation_rounded).evaluate().isNotEmpty;
    final locationPermissionGranted =
        backend.geolocator.requestPermissionCalls == 1 &&
            backend.geolocator.permission == LocationPermission.whileInUse;

    // ---- Expected result -------------------------------------------------
    expect(currentLocationVisible, isTrue,
        reason: 'CASE-025: the user marker must be drawn at the GPS fix.');
    expect(locationPermissionGranted, isTrue,
        reason: 'CASE-025: the app must request and obtain permission.');

    // Supporting evidence: position was read once, status text updated, no
    // error shown.
    expect(backend.geolocator.getCurrentPositionCalls, 1);
    expect(find.textContaining(en('failedLocation')), findsNothing);
    expect(find.byType(BottomSheet), findsNothing);

    await unmountApp(tester);
  });
}
