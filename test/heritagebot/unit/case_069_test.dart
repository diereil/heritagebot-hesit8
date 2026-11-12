// HERITAGEBOT - TEST CASE 069
// Proponent: James Stephen O. Ramos
// Module: User Profile Management
// Unit: View Bookmarked Heritage Sites
// Description: Open saved bookmarks.
// Expected: Show bookmarked sites.
//
// TEST TYPE: Flutter widget test (host VM, no device / live Firebase).
//
// REAL CODE UNDER TEST (lib/, unmodified)
//   BookmarkService.addBookmark (users/{uid}/bookmarks/{siteId}) ->
//   AuthGate -> MainShell -> Profile -> "View Bookmarked Sites" ->
//   BookmarkedSitesScreen (BookmarkService.getBookmarkedSiteIds for the
//   signed-in uid, matched against heritagePlaces).
//
// FIXTURE (fixtureId = CASE-069):
//   * the signed-in Tourist bookmarked Casa Gorordo Museum and
//     Fort San Pedro (saved through the real BookmarkService),
//   * a DIFFERENT user bookmarked Heritage of Cebu Monument
//     (must not appear).
//
// MOCKED: Firebase platform layer only (in-memory Firestore / Auth).

import 'package:flutter_test/flutter_test.dart';

import 'package:heritagebot/main.dart' as app;
import 'package:heritagebot/services/bookmark_service.dart';

import '../support/heritagebot_fixtures.dart';

const FakeAuthAccount kTourist = FakeAuthAccount(
  uid: 'case069-tourist-uid',
  email: 'case069.tourist@heritagebot.test',
  password: 'Case069Pass!',
  displayName: 'Andrea Villanueva',
);
const FakeAuthAccount kOtherUser = FakeAuthAccount(
  uid: 'case069-other-uid',
  email: 'case069.other@heritagebot.test',
  password: 'Case069Other!',
  displayName: 'Other Tourist',
);

late HeritageBotTestBackend backend;

void main() {
  setUpAll(() async {
    backend = await HeritageBotTestBackend.install(
      accounts: [kTourist, kOtherUser],
    );
  });

  setUp(() async {
    await backend.reset();
    backend.seedTourist(kTourist);
    backend.seedTourist(kOtherUser);
  });

  testWidgets('CASE-069 - Open saved bookmarks', (WidgetTester tester) async {
    usePhoneSurface(tester);
    final ownSites = [
      bundledSite('casa_gorordo'),
      bundledSite('fort_san_pedro'),
    ];
    final otherSite = bundledSite('cebu_heritage_monument');

    // Bookmarks saved earlier by each user through the real service.
    await tester.runAsync(() async {
      await signInBeforeLaunch(kOtherUser);
      await BookmarkService().addBookmark(otherSite);
      await backend.auth.signOut();
      await signInBeforeLaunch(kTourist);
      for (final site in ownSites) {
        await BookmarkService().addBookmark(site);
      }
    });

    await launchAuthGate(tester, until: app.MainShell);

    // STEP: Profile -> "View Bookmarked Sites".
    await openBookmarkedSitesFromProfile(tester);
    await pumpFor(tester, const Duration(milliseconds: 300));

    // ---- Observations ---------------------------------------------------
    final listed = bookmarkedSiteNames(tester);
    final ownNames = ownSites.map((s) => s.name).toSet();
    final emptyState = find.text('No Bookmarked Sites').evaluate().isNotEmpty;

    final observed = <String, Object?>{
      'bookmarksVisible': !emptyState && listed.toSet().containsAll(ownNames),
      'onlyOwnBookmarks':
          listed.isNotEmpty &&
          listed.toSet().length == ownNames.length &&
          listed.toSet().difference(ownNames).isEmpty &&
          !listed.contains(otherSite.name),
    };
    printOnFailure(
      'CASE-069 observed: $observed\nlisted=$listed\n'
      'bookmarkDocs=${backend.firestore.documents.keys.where((k) => k.contains('/bookmarks/')).toList()}',
    );

    // ---- Expected result (unchanged from the original CASE-069) ---------
    expect(
      observed['bookmarksVisible'],
      equals(true),
      reason:
          'CASE-069: bookmarksVisible does not match the real system result',
    );
    expect(
      observed['onlyOwnBookmarks'],
      equals(true),
      reason:
          'CASE-069: onlyOwnBookmarks does not match the real system result',
    );

    await unmountApp(tester);
  });
}
