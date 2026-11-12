// HERITAGEBOT - TEST CASE 040
// Proponent: Reil Esdrelon
// Module: Tourist Heritage Access
// Unit: Bookmark Heritage Site
// Description: Bookmark a site.
// Expected: Save site to tourist bookmarks.
//
// TEST TYPE: Flutter widget test (host VM, no device / live Firebase).
//
// REAL CODE UNDER TEST (lib/, unmodified)
//   HeritageSiteService.initializeRuntimeSites -> Home -> Explore Heritage
//   (HeritageSiteSearchScreen) -> HeritageSiteDetailScreen
//   ("Bookmark Heritage Site") -> BookmarkService.toggleBookmark ->
//   Firestore users/{uid}/bookmarks/{siteId} -> Profile ->
//   "View Bookmarked Sites" -> BookmarkedSitesScreen.
//
// FIXTURE (siteFixture = magellans_cross): CASE-022's administrator-
// registered Magellan's Cross record; the tourist has no bookmarks yet.
//
// MOCKED: Firebase platform layer only (in-memory Firestore).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:heritagebot/main.dart' as app;
import 'package:heritagebot/models/heritage_place.dart';
import 'package:heritagebot/services/heritage_site_service.dart';

import '../support/heritagebot_fixtures.dart';

const FakeAuthAccount kTourist = FakeAuthAccount(
  uid: 'case040-tourist-uid',
  email: 'case040.tourist@heritagebot.test',
  password: 'Case040Pass!',
  displayName: 'Case 040 Tourist',
);

const HeritagePlace kSite = kMagellansCross;
final String kBookmarkPath = 'users/${kTourist.uid}/bookmarks/${kSite.id}';

late HeritageBotTestBackend backend;

void main() {
  setUpAll(() async {
    backend = await HeritageBotTestBackend.install(accounts: [kTourist]);
  });

  setUp(() async {
    await backend.reset();
    backend.seedTourist(kTourist);
    seedRegisteredSites(backend, [...defaultHeritagePlaces, kSite]);
  });

  testWidgets('CASE-040 - Bookmark a site: the site is saved to the '
      "tourist's bookmarks", (WidgetTester tester) async {
    usePhoneSurface(tester);

    await HeritageSiteService().initializeRuntimeSites();
    expect(backend.firestore.documents.containsKey(kBookmarkPath), isFalse,
        reason: 'Precondition: site is not bookmarked yet.');

    await signInBeforeLaunch(kTourist);
    await launchAuthGate(tester, until: app.HomeScreen);
    await openSiteDetailFromSearch(tester,
        query: 'Magellan', siteName: kSite.name);

    // STEP: tap "Bookmark Heritage Site".
    final bookmarkButton = find.text('Bookmark Heritage Site');
    await scrollUntilBuilt(tester, bookmarkButton,
        screen: app.HeritageSiteDetailScreen);
    await tapVisible(tester, bookmarkButton);
    await pumpUntilFound(
        tester, snackBarWithText('${kSite.name} added to bookmarks.'));
    final buttonNowRemove = find.text('Remove Bookmark').evaluate().isNotEmpty;

    // Back to the main shell, then Profile -> View Bookmarked Sites.
    await goBackFrom(tester, app.HeritageSiteDetailScreen); // -> search
    await goBackFrom(tester, app.HeritageSiteSearchScreen); // -> home
    await pumpUntilFound(tester, find.byType(NavigationBar));
    await openBookmarkedSitesFromProfile(tester);

    // ---- Observations ---------------------------------------------------
    final stored = backend.firestore.documents[kBookmarkPath];
    final listed = bookmarkedSiteNames(tester);

    final observed = <String, Object?>{
      'bookmarkSaved': stored != null &&
          stored['siteId'] == kSite.id &&
          stored['siteName'] == kSite.name,
      'siteInBookmarks': listed.contains(kSite.name),
    };
    printOnFailure('CASE-040 observed: $observed\n'
        'firestore[$kBookmarkPath]=$stored\n'
        'bookmarkedSitesScreen=$listed buttonNowRemove=$buttonNowRemove');

    // ---- Expected result (unchanged from the original CASE-040) ---------
    expect(observed['bookmarkSaved'], equals(true),
        reason: 'CASE-040: bookmarkSaved does not match the real system result');
    expect(observed['siteInBookmarks'], equals(true),
        reason: 'CASE-040: siteInBookmarks does not match the real system result');
    expect(buttonNowRemove, isTrue,
        reason: 'The detail screen should switch to "Remove Bookmark".');

    await unmountApp(tester);
  });
}
