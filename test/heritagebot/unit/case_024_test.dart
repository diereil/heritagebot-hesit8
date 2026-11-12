// HERITAGEBOT - TEST CASE 024
// Proponent: Reil Esdrelon
// Module: Tourist Heritage Access
// Unit: View Heritage Site Information
// Description: Select listed heritage site.
// Expected: Display verified site details.
//
// TEST TYPE: Flutter widget test (host VM, no device / live Firebase).
//
// REAL CODE UNDER TEST (lib/, unmodified)
//   Home -> Explore Heritage -> registered-site result list -> tap ->
//   HeritageSiteDetailScreen (badge, location card, historical information,
//   learning/visit cards, bookmark button) + UsageAnalyticsService
//   site_view event.
//
// FIXTURE: "Heritage of Cebu Monument", one of the official research sites
// bundled in lib/models/heritage_place.dart (defaultHeritagePlaces). The
// expected details are read from that real record, not retyped here.
//
// MOCKED: Firebase platform layer only.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:heritagebot/main.dart' as app;
import 'package:heritagebot/models/heritage_place.dart';

import '../support/heritagebot_test_harness.dart';

const FakeAuthAccount kTourist = FakeAuthAccount(
  uid: 'case024-tourist-uid',
  email: 'case024.tourist@heritagebot.test',
  password: 'Case024Pass!',
  displayName: 'Case 024 Tourist',
);

late HeritageBotTestBackend backend;

void main() {
  setUpAll(() async {
    backend = await HeritageBotTestBackend.install(accounts: [kTourist]);
  });

  setUp(() async {
    await backend.reset();
    backend.seedTourist(kTourist);
  });

  testWidgets('CASE-024 - Select listed heritage site: verified site details '
      'are displayed', (WidgetTester tester) async {
    usePhoneSurface(tester);

    final registered = defaultHeritagePlaces
        .singleWhere((s) => s.id == 'cebu_heritage_monument');
    expect(registered.isOfficial, isTrue);

    await signInBeforeLaunch(kTourist);
    await launchAuthGate(tester, until: app.HomeScreen);
    await tapVisible(tester, find.text('Explore Heritage by Location'));
    await pumpUntilFound(tester, find.byType(app.HeritageSiteSearchScreen));

    // STEP 1: List the site and select it.
    await tester.enterText(
        fieldsOf(app.HeritageSiteSearchScreen).first, 'Heritage of Cebu');
    await tester.pump();
    await tapVisible(
      tester,
      find.descendant(
          of: find.byType(ListTile), matching: find.text(registered.name)),
    );
    await pumpUntilFound(tester, find.byType(app.HeritageSiteDetailScreen));
    await pumpFor(tester, const Duration(milliseconds: 500));

    // ---- Observations ---------------------------------------------------
    final detail = tester.widget<app.HeritageSiteDetailScreen>(
        find.byType(app.HeritageSiteDetailScreen));

    final locationCards = infoCardsTitled(tester, 'Location');
    await scrollUntilBuilt(tester, find.text('Historical Information'),
        screen: app.HeritageSiteDetailScreen);
    final historyCards = infoCardsTitled(tester, 'Historical Information');

    final heritageDetailsVisible = find
            .descendant(
                of: find.byType(AppBar), matching: find.text(registered.name))
            .evaluate()
            .isNotEmpty &&
        locationCards.length == 1 &&
        historyCards.length == 1;

    final verifiedSiteShown = detail.site.id == registered.id &&
        find.text('OFFICIAL SITE').evaluate().isNotEmpty &&
        historyCards.single.body == registered.historicalFacts &&
        locationCards.single.body.contains(registered.location) &&
        locationCards.single.body
            .contains('Latitude: ${registered.lat.toStringAsFixed(5)}') &&
        locationCards.single.body
            .contains('Longitude: ${registered.lng.toStringAsFixed(5)}');

    // ---- Expected result -------------------------------------------------
    expect(heritageDetailsVisible, isTrue,
        reason: 'CASE-024: the site detail page must show its information.');
    expect(verifiedSiteShown, isTrue,
        reason: 'CASE-024: details must match the registered official site.');

    // Supporting evidence: further cards and the site-view analytics event.
    await scrollUntilBuilt(tester, find.text('Why Visit This Place'),
        screen: app.HeritageSiteDetailScreen);
    expect(infoCardsTitled(tester, 'What You Can Learn'), hasLength(1));
    expect(find.text('TEST SITE'), findsNothing);
    final views = backend.firestore.documents.entries
        .where((e) => e.key.startsWith('usage_events/'))
        .map((e) => e.value)
        .where((d) => d['eventType'] == 'site_view')
        .toList();
    expect(views, hasLength(1));
    expect(views.single['siteId'], registered.id);
    expect(views.single['userId'], kTourist.uid);

    await unmountApp(tester);
  });
}
