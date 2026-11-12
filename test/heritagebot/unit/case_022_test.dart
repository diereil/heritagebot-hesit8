// HERITAGEBOT - TEST CASE 022
// Proponent: Reil Esdrelon
// Module: Tourist Heritage Access
// Unit: Search Heritage Site
// Description: Search existing site name ('Magellan').
// Expected: Show matching heritage site.
//
// TEST TYPE: Flutter widget test (host VM, no device / live Firebase).
//
// REAL CODE UNDER TEST (lib/, unmodified)
//   HeritageSiteService.initializeRuntimeSites (the same start-up call made
//   in main()) loads the administrator-managed heritage_sites collection ->
//   Home -> "Explore Heritage by Location" -> HeritageSiteSearchScreen
//   instant registered-site matching (_registeredSiteScore) -> tap result ->
//   HeritageSiteDetailScreen.
//
// FIXTURE NOTE (important for the manuscript)
// The four sites bundled in lib/models/heritage_place.dart do NOT include a
// "Magellan" site. Such a site exists in HeritageBot only if an
// administrator registers it in Firestore. The test therefore seeds the
// in-memory Firestore 'heritage_sites' collection with the four bundled
// sites plus one administrator-registered "Magellan's Cross" record, and
// lets the real HeritageSiteService load them.
//
// MOCKED: Firebase platform layer only.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:heritagebot/main.dart' as app;
import 'package:heritagebot/models/heritage_place.dart';
import 'package:heritagebot/services/heritage_site_service.dart';

import '../support/heritagebot_test_harness.dart';

const FakeAuthAccount kTourist = FakeAuthAccount(
  uid: 'case022-tourist-uid',
  email: 'case022.tourist@heritagebot.test',
  password: 'Case022Pass!',
  displayName: 'Case 022 Tourist',
);

const String kQuery = 'Magellan';

const HeritagePlace kMagellansCross = HeritagePlace(
  id: 'magellans_cross',
  name: "Magellan's Cross",
  location: 'Magallanes Street, Cebu City',
  lat: 10.29353,
  lng: 123.90187,
  videoTitle: "Magellan's Cross Video",
  wikipediaTitle: "Magellan's Cross",
  detectionRadiusMeters: 20000,
  historicalFacts:
      "Magellan's Cross is a Christian cross planted by the expedition of "
      'Ferdinand Magellan upon arriving in Cebu in 1521. It is housed in a '
      'chapel beside the Basilica Minore del Santo Niño.',
);

late HeritageBotTestBackend backend;

void main() {
  setUpAll(() async {
    backend = await HeritageBotTestBackend.install(accounts: [kTourist]);
  });

  setUp(() async {
    await backend.reset();
    backend.seedTourist(kTourist);
    for (final site in [...defaultHeritagePlaces, kMagellansCross]) {
      backend.firestore.seedDocument('heritage_sites/${site.id}', site.toMap());
    }
  });

  testWidgets('CASE-022 - Search existing site "Magellan": matching heritage '
      'site is shown', (WidgetTester tester) async {
    usePhoneSurface(tester);

    // STEP 1: App start-up loads the registered sites (as main() does).
    await HeritageSiteService().initializeRuntimeSites();
    expect(heritagePlaces.map((s) => s.id), contains(kMagellansCross.id));

    // STEP 2: Signed-in tourist opens Explore Heritage from the home page.
    await signInBeforeLaunch(kTourist);
    await launchAuthGate(tester, until: app.HomeScreen);
    await tapVisible(tester, find.text('Explore Heritage by Location'));
    await pumpUntilFound(tester, find.byType(app.HeritageSiteSearchScreen));

    // STEP 3: Type the site name into the real search field.
    await tester.enterText(
        fieldsOf(app.HeritageSiteSearchScreen).first, kQuery);
    await tester.pump();

    // ---- Observations ---------------------------------------------------
    final resultsCard = find.ancestor(
      of: find.text('Matching Heritage Sites'),
      matching: find.byType(Card),
    );
    final resultTitles = resultsCard.evaluate().isEmpty
        ? <String>[]
        : tester
            .widgetList<ListTile>(
                find.descendant(of: resultsCard, matching: find.byType(ListTile)))
            .map((tile) => (tile.title as Text).data ?? '')
            .toList();

    final searchHasMatch = resultTitles.isNotEmpty;
    final correctSiteReturned = resultTitles.isNotEmpty &&
        resultTitles.first == kMagellansCross.name &&
        resultTitles.every((title) => title.toLowerCase().contains('magellan'));

    printOnFailure('Search results for "$kQuery": $resultTitles');

    // ---- Expected result -------------------------------------------------
    expect(searchHasMatch, isTrue,
        reason: 'CASE-022: the search must list a matching site.');
    expect(correctSiteReturned, isTrue,
        reason: "CASE-022: Magellan's Cross must be the result, without "
            'unrelated sites.');

    // Supporting evidence: tapping the result opens that site's details.
    await tapVisible(tester, find.text(kMagellansCross.name));
    await pumpUntilFound(tester, find.byType(app.HeritageSiteDetailScreen));
    final detail = tester.widget<app.HeritageSiteDetailScreen>(
        find.byType(app.HeritageSiteDetailScreen));
    expect(detail.site.id, kMagellansCross.id);

    await unmountApp(tester);
  });
}
