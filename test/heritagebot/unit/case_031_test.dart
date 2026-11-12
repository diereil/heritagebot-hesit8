// HERITAGEBOT - TEST CASE 031
// Proponent: Reil Esdrelon
// Module: Tourist Heritage Access
// Unit: Interactive Map
// Description: Select heritage map marker.
// Expected: Open corresponding heritage site.
//
// TEST TYPE: Flutter widget test (host VM, no device / live Firebase).
//
// REAL CODE UNDER TEST (lib/, unmodified)
//   HeritageSiteService.initializeRuntimeSites (start-up call from main()) ->
//   MainShell -> GeolocationScreen (FlutterMap + MarkerLayer built from
//   heritagePlaces) -> marker GestureDetector -> _showMapSiteOptions ->
//   "View Details" -> HeritageSiteDetailScreen.
//
// FIXTURE (siteFixture = magellans_cross)
// The administrator-registered Magellan's Cross record (same as CASE-022),
// configured with a 50 m narrative trigger radius. The tourist stands
// ~150 m south of it, so the site is on the map but the automatic
// location narrative does not pop up over the map (geometry checked below
// with the same Geolocator.distanceBetween the app uses).
//
// MOCKED: Firebase platform layer, GeolocatorPlatform, flutter_tts channel.

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'package:heritagebot/main.dart' as app;
import 'package:heritagebot/models/heritage_place.dart';
import 'package:heritagebot/services/heritage_site_service.dart';

import '../support/heritagebot_fixtures.dart';

const FakeAuthAccount kTourist = FakeAuthAccount(
  uid: 'case031-tourist-uid',
  email: 'case031.tourist@heritagebot.test',
  password: 'Case031Pass!',
  displayName: 'Case 031 Tourist',
);

final HeritagePlace kSite = kMagellansCross.copyWith(detectionRadiusMeters: 50);
const double kTouristLat = 10.29218; // ~150 m south of Magellan's Cross
const double kTouristLng = 123.90187;

late HeritageBotTestBackend backend;

void main() {
  setUpAll(() async {
    backend = await HeritageBotTestBackend.install(accounts: [kTourist]);
  });

  setUp(() async {
    await backend.reset();
    backend.seedTourist(kTourist);
    seedRegisteredSites(backend, [...defaultHeritagePlaces, kSite]);
    placeTouristAt(backend, lat: kTouristLat, lng: kTouristLng);
  });

  testWidgets('CASE-031 - Select heritage map marker: the corresponding '
      'heritage site opens', (WidgetTester tester) async {
    usePhoneSurface(tester);

    // App start-up loads the administrator-registered sites (as main() does).
    await HeritageSiteService().initializeRuntimeSites();
    expect(heritagePlaces.map((s) => s.id), contains(kSite.id));

    // Fixture check: Magellan's Cross is the nearest site but outside its
    // trigger radius, so no automatic narrative covers the map.
    final distance = Geolocator.distanceBetween(
        kTouristLat, kTouristLng, kSite.lat, kSite.lng);
    expect(distance, greaterThan(kSite.detectionRadiusMeters));
    for (final other in heritagePlaces.where((s) => s.id != kSite.id)) {
      expect(
          Geolocator.distanceBetween(
              kTouristLat, kTouristLng, other.lat, other.lng),
          greaterThan(distance));
    }

    await signInBeforeLaunch(kTourist);
    await launchAuthGate(tester, until: app.MainShell);
    await openGeolocationTab(tester);
    await pumpUntilFound(
        tester, find.textContaining('${en('nearest')}: ${kSite.name}'));
    expect(find.byType(app.NarrativeAutoPlaybackPanel), findsNothing);

    // Locate the marker drawn at Magellan's Cross's coordinates.
    final camera = MapCamera.of(tester.element(find.byType(MarkerLayer)));
    final mapOrigin = tester.getTopLeft(find.byType(FlutterMap));
    final expectedPoint =
        mapOrigin + camera.latLngToScreenOffset(LatLng(kSite.lat, kSite.lng));
    final siteMarkers = find
        .descendant(
            of: find.byType(MarkerLayer),
            matching: find.byIcon(Icons.location_on_rounded))
        .evaluate()
        .where((e) =>
            (tester.getCenter(find.byElementPredicate((x) => x == e)) -
                    expectedPoint)
                .distance <
            3)
        .toList();
    expect(siteMarkers, hasLength(1),
        reason: "Exactly one site marker must be drawn at Magellan's Cross.");

    // STEP: tourist taps the marker, then "View Details".
    await tester.tap(find.byElementPredicate((e) => e == siteMarkers.single));
    await tester.pump();
    await pumpUntilFound(tester, find.text('View Details'));
    await pumpFor(tester, const Duration(milliseconds: 600)); // sheet slide-in
    final optionsSheetTitle = find
        .descendant(of: find.byType(BottomSheet), matching: find.text(kSite.name))
        .evaluate()
        .isNotEmpty;
    await tapVisible(tester, find.text('View Details'));
    await pumpUntilFound(tester, find.byType(app.HeritageSiteDetailScreen));
    await pumpFor(tester, const Duration(milliseconds: 300));

    // ---- Observations ---------------------------------------------------
    final detailFinder = find.byType(app.HeritageSiteDetailScreen);
    final detail = tester.widget<app.HeritageSiteDetailScreen>(detailFinder);
    final historyCards = infoCardsTitled(tester, 'Historical Information');

    final observed = <String, Object?>{
      'siteDetailsVisible': detailFinder.evaluate().isNotEmpty &&
          find
              .descendant(
                  of: find.byType(AppBar), matching: find.text(kSite.name))
              .evaluate()
              .isNotEmpty &&
          historyCards.isNotEmpty,
      'correctMarkerSiteOpened': detail.site.id == kSite.id &&
          historyCards.isNotEmpty &&
          historyCards.single.body == kSite.historicalFacts,
    };
    printOnFailure('CASE-031 observed: $observed, '
        'optionsSheetShowedSite=$optionsSheetTitle, '
        'openedSiteId=${detail.site.id}');

    // ---- Expected result (unchanged from the original CASE-031) ---------
    expect(observed['siteDetailsVisible'], equals(true),
        reason: 'CASE-031: siteDetailsVisible does not match the real system result');
    expect(observed['correctMarkerSiteOpened'], equals(true),
        reason: 'CASE-031: correctMarkerSiteOpened does not match the real system result');

    await unmountApp(tester);
  });
}
