// HERITAGEBOT - TEST CASE 026
// Proponent: Reil Esdrelon
// Module: Tourist Heritage Access
// Unit: Live Geolocation Map
// Description: Deny location permission.
// Expected: Show permission guidance.
//
// TEST TYPE: Flutter widget test (host VM, no device / live Firebase).
//
// REAL CODE UNDER TEST (lib/, unmodified)
//   GeolocationScreen.startLiveTracking -> LocationService.ensurePermission:
//   `if (permission == LocationPermission.denied)
//        throw Exception('Location permission denied.')`
//   -> SnackBar "<failedLocation>: Location permission denied."
//
// SCOPE NOTE: for a one-time denial the app's message states that location
// permission was denied (the "Enable it in app settings" instruction is
// used only for a permanent denial). The test asserts the exact app text.
//
// MOCKED: Firebase platform layer and GeolocatorPlatform (the tourist taps
// "Don't allow" in the OS permission dialog).

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';

import 'package:heritagebot/main.dart' as app;

import '../support/heritagebot_test_harness.dart';

const FakeAuthAccount kTourist = FakeAuthAccount(
  uid: 'case026-tourist-uid',
  email: 'case026.tourist@heritagebot.test',
  password: 'Case026Pass!',
  displayName: 'Case 026 Tourist',
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
      ..serviceEnabled = true
      ..permission = LocationPermission.denied
      ..userResponseToPermissionDialog = LocationPermission.denied
      ..currentFix = fakeGpsFix(latitude: 10.29889, longitude: 123.90362);
  });

  testWidgets('CASE-026 - Deny location permission: permission guidance is '
      'shown', (WidgetTester tester) async {
    usePhoneSurface(tester);

    await signInBeforeLaunch(kTourist);
    await launchAuthGate(tester, until: app.MainShell);

    await tapNavDestination(tester, en('geolocation'));
    await pumpUntilFound(tester, find.byType(app.GeolocationScreen));
    await pumpUntilFound(tester, find.byType(SnackBar));
    await pumpFor(tester, const Duration(milliseconds: 500));

    // ---- Observations ---------------------------------------------------
    final userMarkers = tester
        .widgetList<MarkerLayer>(find.byType(MarkerLayer))
        .expand((layer) => layer.markers)
        .where((m) =>
            m.child is Icon &&
            (m.child as Icon).icon == Icons.navigation_rounded)
        .toList();
    final currentLocationVisible = userMarkers.isNotEmpty;
    final permissionGuidanceVisible = snackBarWithText(
      '${en('failedLocation')}: Location permission denied.',
    ).evaluate().isNotEmpty;

    // ---- Expected result -------------------------------------------------
    expect(currentLocationVisible, isFalse,
        reason: 'CASE-026: no location may be shown without permission.');
    expect(permissionGuidanceVisible, isTrue,
        reason: 'CASE-026: the permission-denied message must be shown.');

    // Supporting evidence: the OS dialog was shown once, the position was
    // never read, no narrative opened, and the user can try again.
    expect(backend.geolocator.requestPermissionCalls, 1);
    expect(backend.geolocator.getCurrentPositionCalls, 0);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text(en('mapReady')), findsOneWidget);
    final refresh = find.ancestor(
      of: find.text(en('refreshLocation')),
      matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
    );
    expect(tester.widget<ButtonStyleButton>(refresh).onPressed, isNotNull,
        reason: 'Refresh Location must be available to retry.');

    await unmountApp(tester);
  });
}
