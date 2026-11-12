// HERITAGEBOT - TEST CASE 070
// Proponent: James Stephen O. Ramos
// Module: User Profile Management
// Unit: Logout
// Description: Log out from profile.
// Expected: Terminate current session.
//
// TEST TYPE: Flutter widget test (host VM, no device / live Firebase).
//
// REAL CODE UNDER TEST (lib/, unmodified)
//   ProfileScreen "Logout" -> ProfileScreen.logout -> AuthService.logout
//   (GoogleSignIn.signOut, FacebookAuth.logOut, FirebaseAuth.signOut) ->
//   AuthGate (authStateChanges -> null) -> LoginSignupScreen.
//   Afterwards the real account-scoped services are called:
//   BookmarkService.getBookmarkedSiteIds and
//   CommunitySubmissionService.getMySubmissions must refuse access.
//
// FIXTURE (fixtureId = CASE-070): a signed-in, verified Tourist with one
// bookmark, on the Profile tab.
//
// MOCKED: Firebase platform layer, Google Sign-In platform and the Facebook
// SDK channel (record calls only).

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:heritagebot/main.dart' as app;
import 'package:heritagebot/services/bookmark_service.dart';
import 'package:heritagebot/services/community_submission_service.dart';

import '../support/contributor_flow.dart';
import '../support/heritagebot_fixtures.dart';

const FakeAuthAccount kTourist = FakeAuthAccount(
  uid: 'case070-tourist-uid',
  email: 'case070.tourist@heritagebot.test',
  password: 'Case070Pass!',
  displayName: 'Andrea Villanueva',
);

late HeritageBotTestBackend backend;

void main() {
  setUpAll(() async {
    backend = await HeritageBotTestBackend.install(accounts: [kTourist]);
  });

  setUp(() async {
    await backend.reset();
    backend.seedTourist(kTourist);
    backend.firestore.seedDocument(
      'users/${kTourist.uid}/bookmarks/fort_san_pedro',
      <String, dynamic>{
        'siteId': 'fort_san_pedro',
        'siteName': 'Fort San Pedro',
        'location': 'A. Pigafetta Street, Cebu City',
        'isTesting': false,
        'createdAtMillis': 1,
      },
    );
  });

  testWidgets('CASE-070 - Log out from profile', (WidgetTester tester) async {
    usePhoneSurface(tester);

    await signInBeforeLaunch(kTourist);
    await launchAuthGate(tester, until: app.MainShell);
    await openProfileTab(tester);

    // Precondition: the session is active and protected data is readable.
    expect(FirebaseAuth.instance.currentUser?.uid, kTourist.uid);
    Set<String>? bookmarksBefore;
    await tester.runAsync(() async {
      bookmarksBefore = await BookmarkService().getBookmarkedSiteIds();
    });
    expect(bookmarksBefore, contains('fort_san_pedro'));

    // STEP: tap "Logout" on the Profile screen.
    final logout = find.descendant(
      of: profileScreen,
      matching: find.text(en('logout')),
    );
    await tapVisible(tester, logout);
    await pumpUntilFound(tester, find.byType(app.LoginSignupScreen));
    await pumpFor(tester, const Duration(milliseconds: 300));

    // ---- Observations ---------------------------------------------------
    final currentUser = FirebaseAuth.instance.currentUser;
    final mainShellGone = find.byType(app.MainShell).evaluate().isEmpty;
    final profileGone = find.byType(app.ProfileScreen).evaluate().isEmpty;

    Object? bookmarkError;
    Object? submissionsError;
    await tester.runAsync(() async {
      try {
        await BookmarkService().getBookmarkedSiteIds();
      } catch (e) {
        bookmarkError = e;
      }
      try {
        await CommunitySubmissionService().getMySubmissions();
      } catch (e) {
        submissionsError = e;
      }
    });
    bool notLoggedIn(Object? e) =>
        e is FirebaseAuthException && e.code == 'not-logged-in';

    final facebookLogOut = backend.channels.facebookCalls.any(
      (c) => c.method == 'logOut',
    );

    final observed = <String, Object?>{
      'sessionActive': currentUser != null || !mainShellGone || !profileGone,
      'protectedAccessDenied':
          find.byType(app.LoginSignupScreen).evaluate().isNotEmpty &&
          notLoggedIn(bookmarkError) &&
          notLoggedIn(submissionsError),
    };
    printOnFailure(
      'CASE-070 observed: $observed\ncurrentUser=${currentUser?.uid} '
      'mainShellGone=$mainShellGone profileGone=$profileGone\n'
      'bookmarkError=$bookmarkError\nsubmissionsError=$submissionsError\n'
      'googleSignOutCalls=${backend.google.signOutCalls} '
      'facebookLogOut=$facebookLogOut',
    );

    // ---- Expected result (unchanged from the original CASE-070) ---------
    expect(
      observed['sessionActive'],
      equals(false),
      reason: 'CASE-070: sessionActive does not match the real system result',
    );
    expect(
      observed['protectedAccessDenied'],
      equals(true),
      reason:
          'CASE-070: protectedAccessDenied does not match the real system result',
    );
    // Supporting evidence: social sign-in sessions are closed too.
    expect(backend.google.signOutCalls, greaterThanOrEqualTo(1));
    expect(facebookLogOut, isTrue);

    await unmountApp(tester);
  });
}
