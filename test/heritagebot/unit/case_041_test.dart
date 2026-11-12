// HERITAGEBOT - TEST CASE 041
// Proponent: Reil Esdrelon
// Module: Tourist Heritage Access
// Unit: Bookmark Heritage Site
// Description: Remove bookmarked site.
// Expected: Remove site from saved bookmarks.
//
// TEST TYPE: Flutter widget test (host VM, no device / live Firebase).
//
// REAL CODE UNDER TEST (lib/, unmodified)
//   Profile -> "View Bookmarked Sites" (BookmarkedSitesScreen,
//   BookmarkService.getBookmarkedSiteIds) -> tap site ->
//   HeritageSiteDetailScreen ("Remove Bookmark") ->
//   BookmarkService.toggleBookmark/removeBookmark -> back to
//   BookmarkedSitesScreen (refreshes from Firestore).
//
// FIXTURE (siteFixture = magellans_cross): CASE-022's administrator-
// registered Magellan's Cross record, already bookmarked by the tourist
// (users/{uid}/bookmarks/magellans_cross written in the exact shape of
// BookmarkService.addBookmark).
//
// MOCKED: Firebase platform layer only (in-memory Firestore).

import 'package:flutter_test/flutter_test.dart';

import 'package:heritagebot/main.dart' as app;
import 'package:heritagebot/models/heritage_place.dart';
import 'package:heritagebot/services/heritage_site_service.dart';

import '../support/heritagebot_fixtures.dart';

const FakeAuthAccount kTourist = FakeAuthAccount(
  uid: 'case041-tourist-uid',
  email: 'case041.tourist@heritagebot.test',
  password: 'Case041Pass!',
  displayName: 'Case 041 Tourist',
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
    backend.firestore.seedDocument(kBookmarkPath, <String, dynamic>{
      'siteId': kSite.id,
      'siteName': kSite.name,
      'location': kSite.location,
      'isTesting': kSite.isTesting,
      'createdAtMillis': 1767225600000,
    });
  });

  testWidgets('CASE-041 - Remove bookmarked site: the site is removed from '
      'saved bookmarks', (WidgetTester tester) async {
    usePhoneSurface(tester);

    await HeritageSiteService().initializeRuntimeSites();

    await signInBeforeLaunch(kTourist);
    await launchAuthGate(tester, until: app.MainShell);
    await openBookmarkedSitesFromProfile(tester);
    final listedBefore = bookmarkedSiteNames(tester);
    expect(listedBefore, contains(kSite.name),
        reason: 'Precondition: the site is listed in bookmarks.');

    // STEP: open the bookmarked site and tap "Remove Bookmark".
    await tapVisible(tester, find.text(kSite.name));
    await pumpUntilFound(tester, find.byType(app.HeritageSiteDetailScreen));
    final removeButton = find.text('Remove Bookmark');
    await pumpUntilFound(tester, removeButton);
    await scrollUntilBuilt(tester, removeButton,
        screen: app.HeritageSiteDetailScreen);
    await tapVisible(tester, removeButton);
    await pumpUntilFound(
        tester, snackBarWithText('${kSite.name} removed from bookmarks.'));

    // Back to the bookmark list (it reloads from Firestore).
    await goBackFrom(tester, app.HeritageSiteDetailScreen);
    await pumpUntilFound(tester, find.text('Saved Heritage Sites'));
    await pumpFor(tester, const Duration(milliseconds: 500));

    // ---- Observations ---------------------------------------------------
    final listedAfter = bookmarkedSiteNames(tester);
    final emptyStateShown = find.text('No Bookmarked Sites').evaluate().isNotEmpty;

    final observed = <String, Object?>{
      'bookmarkRemoved': !backend.firestore.documents.containsKey(kBookmarkPath),
      'siteInBookmarks': listedAfter.contains(kSite.name),
    };
    printOnFailure('CASE-041 observed: $observed\n'
        'listedBefore=$listedBefore listedAfter=$listedAfter '
        'emptyStateShown=$emptyStateShown');

    // ---- Expected result (unchanged from the original CASE-041) ---------
    expect(observed['bookmarkRemoved'], equals(true),
        reason: 'CASE-041: bookmarkRemoved does not match the real system result');
    expect(observed['siteInBookmarks'], equals(false),
        reason: 'CASE-041: siteInBookmarks does not match the real system result');
    expect(emptyStateShown, isTrue,
        reason: 'The bookmark list should show its empty state.');

    await unmountApp(tester);
  });
}
