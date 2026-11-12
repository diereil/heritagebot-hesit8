// HERITAGEBOT - TEST CASE 027
// Proponent: Reil Esdrelon
// Module: Tourist Heritage Access
// Unit: Live Geolocation Map
// Description: Disable device GPS.
// Expected: Show location unavailable message.
//
// TEST TYPE: Flutter widget test (host VM, no device / live Firebase).
//
// REAL CODE UNDER TEST (lib/, unmodified)
//   GeolocationScreen.startLiveTracking -> LocationService.ensurePermission:
//   `if (!enabled) throw Exception('Please turn on your GPS/location service.')`
//   -> SnackBar "<failedLocation>: Please turn on your GPS/location service."
//
// MOCKED: Firebase platform layer and GeolocatorPlatform (device location
// service switched off; permission already granted).

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';

import 'package:heritagebot/main.dart' as app;

import '../support/heritagebot_test_harness.dart';

const FakeAuthAccount kTourist = FakeAuthAccount(
  uid: 'case027-tourist-uid',
  email: 'case027.tourist@heritagebot.test',
  password: 'Case027Pass!',
  displayName: 'Case 027 Tourist',
);

late HeritageBotTestBackend backend;

void main() {
  setUpAll(() async {
    backend = await HeritageBotTestBackend.install(accounts: [kTourist]);
  });

  setUp(() async {
    await backend.reset();
    backend.seedTourist(kTourist);
    backend.geolocator
      ..serviceEnabled = false // GPS switched off
      ..permission = LocationPermission.whileInUse
      ..currentFix = fakeGpsFix(latitude: 10.29889, longitude: 123.90362);
  });

  testWidgets('CASE-027 - Device GPS disabled: location unavailable message '
      'is shown', (WidgetTester tester) async {
    usePhoneSurface(tester);

    await signInBeforeLaunch(kTourist);
    await launchAuthGate(tester, until: app.MainShell);

    await tapNavDestination(tester, en('geolocation'));
    await pumpUntilFound(tester, find.byType(app.GeolocationScreen));
    await pumpUntilFound(tester, find.byType(SnackBar));
    await pumpFor(tester, const Duration(milliseconds: 500));

    // ---- Observations ---------------------------------------------------
    final currentLocationVisible = tester
        .widgetList<MarkerLayer>(find.byType(MarkerLayer))
        .expand((layer) => layer.markers)
        .any((m) =>
            m.child is Icon &&
            (m.child as Icon).icon == Icons.navigation_rounded);
    final locationUnavailableVisible = snackBarWithText(
      '${en('failedLocation')}: Please turn on your GPS/location service.',
    ).evaluate().isNotEmpty;

    // ---- Expected result -------------------------------------------------
    expect(currentLocationVisible, isFalse,
        reason: 'CASE-027: no location may be shown with GPS off.');
    expect(locationUnavailableVisible, isTrue,
        reason: 'CASE-027: the "turn on your GPS" message must be shown.');

    // Supporting evidence: the app stopped before asking for permission or
    // a position, and no narrative opened.
    expect(backend.geolocator.requestPermissionCalls, 0);
    expect(backend.geolocator.getCurrentPositionCalls, 0);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text(en('mapReady')), findsOneWidget);

    await unmountApp(tester);
  });
}
