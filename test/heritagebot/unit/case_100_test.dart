// HERITAGEBOT - TEST CASE 100
// Proponent: Shawn Guillmar C. Morales
// Module: Community Contribution Review
// Unit: Review Community Contributions
// Description: Try approval without admin rights
// Expected: Reject unauthorized action
//
// TEST TYPE: Flutter widget test (host VM, no device / live Firebase).
//
// REAL CODE UNDER TEST (lib/, unmodified)
//   AuthGate -> UserService.getUserProfile -> role "tourist" ->
//   MainShell(userRole: tourist) instead of AdminShell. HeritageBot has no
//   named routes / deep links: the ONLY way to approve a contribution is
//   AdminShell -> "Review" (AdminDashboardScreen) -> AdminReviewSubmissionScreen
//   -> "Approve", which AuthGate offers only to the administrator role
//   (same access model as CASE-083).
//
// INPUT (actorRole): tourist - a verified, signed-in tourist account whose
// users/{uid} record has role "tourist" (e-mail not in
// UserService.adminEmails). A PENDING community story exists.
//
// WHAT IS OBSERVED
//   * which shell the real AuthGate opens for the tourist,
//   * whether any review screen (AdminShell, AdminDashboardScreen,
//     AdminReviewSubmissionScreen) is built,
//   * whether any reachable tourist tab (Home, Stories, My Journal, Profile -
//     every entry scrolled into view) offers an approve / review action or
//     shows the pending story, and
//   * that the pending story is unchanged.
//   SCOPE: CommunitySubmissionService.reviewSubmission itself has no role
//   check ("Firestore security rules remain the final authority"). Firestore
//   security rules are server side and are not part of this widget test;
//   the in-memory Firestore fake has no rules.
//
// MOCKED: Firebase platform layer only.

import 'package:flutter_test/flutter_test.dart';

import 'package:heritagebot/main.dart' as app;
import 'package:heritagebot/models/community_submission.dart';
import 'package:heritagebot/models/user_profile.dart';
import 'package:heritagebot/services/user_service.dart';

import '../support/admin_operations_flow.dart';

const FakeAuthAccount kTourist = FakeAuthAccount(
  uid: 'case100-tourist-uid',
  email: 'case100.tourist@heritagebot.test',
  password: 'Case100Pass!',
  displayName: 'Tess Tourist',
);

const String kPendingTitle = 'Candles at the Cross';

/// Text of any entry that would let the user review / approve a story.
final RegExp kApprovalEntry = RegExp(
  r'\bapprove\b|\breject\b|review community contributions|review contribution|'
  r'administrator feedback|pending review',
  caseSensitive: false,
);

late HeritageBotTestBackend backend;

void main() {
  setUpAll(() async {
    backend = await HeritageBotTestBackend.install(accounts: [kTourist, kAdminAccount]);
  });

  setUp(() async {
    await backend.reset();
    backend.seedTourist(kTourist);
    seedRegisteredSites(backend, [kMagellansCross]);
    seedStory(backend, storyFixture(id: 'case100-story', title: kPendingTitle, status: CommunitySubmissionStatus.pending, site: kMagellansCross));
  });

  testWidgets('CASE-100 - Try approval without admin rights', (WidgetTester tester) async {
    usePhoneSurface(tester);
    final storyBefore = '${storedSubmissions(backend)['community_submissions/case100-story']}';

    // STEP: the tourist opens HeritageBot (real AuthGate).
    await signInBeforeLaunch(kTourist);
    await launchAuthGate(tester, until: app.MainShell);
    await pumpFor(tester, const Duration(milliseconds: 400));

    // STEP: look through every tab the tourist can reach.
    final tabs = <String, Type>{
      en('home'): app.HomeScreen,
      'Stories': app.CommunityStoriesScreen,
      en('myJournal'): app.MyJournalScreen,
      en('profile'): app.ProfileScreen,
    };
    final entriesFound = <String, List<String>>{};
    final scannedTexts = <String, int>{};
    var pendingStoryShown = false;
    for (final tab in tabs.entries) {
      await tapNavDestination(tester, tab.key);
      await pumpFor(tester, const Duration(milliseconds: 500));
      final texts = await allTextsOfScreen(tester, find.byType(tab.value));
      scannedTexts[tab.key] = texts.length;
      final hits = texts.where(kApprovalEntry.hasMatch).toList();
      if (hits.isNotEmpty) entriesFound[tab.key] = hits;
      if (texts.contains(kPendingTitle)) pendingStoryShown = true;
    }

    // ---- Observations -----------------------------------------------------
    bool built(Type t) => find.byType(t, skipOffstage: false).evaluate().isNotEmpty;
    final shell = tester.widget<app.MainShell>(find.byType(app.MainShell));
    final reviewScreensBuilt = <String, bool>{
      'AdminShell': built(app.AdminShell),
      'AdminDashboardScreen': built(app.AdminDashboardScreen),
      'AdminReviewSubmissionScreen': built(app.AdminReviewSubmissionScreen),
    };
    final storedRole = storedUsers(backend)['users/${kTourist.uid}']?['role'] as String?;
    final storyAfter = '${storedSubmissions(backend)['community_submissions/case100-story']}';

    final observed = <String, Object?>{
      'approvalAllowed':
          reviewScreensBuilt.values.any((b) => b) ||
          entriesFound.isNotEmpty ||
          pendingStoryShown ||
          storyAfter != storyBefore,
      'authorizationDenied':
          storedRole == UserRoles.tourist &&
          !UserService().isAuthorizedAdminEmail(kTourist.email) &&
          shell.userRole == UserRoles.tourist &&
          reviewScreensBuilt.values.every((b) => !b) &&
          entriesFound.isEmpty &&
          !pendingStoryShown &&
          storyAfter == storyBefore &&
          scannedTexts.length == tabs.length &&
          scannedTexts.values.every((n) => n > 0),
    };
    printOnFailure(
      'CASE-100 observed: $observed\nshell.userRole=${shell.userRole} storedRole=$storedRole\n'
      'reviewScreensBuilt=$reviewScreensBuilt entriesFound=$entriesFound '
      'pendingStoryShown=$pendingStoryShown scannedTexts=$scannedTexts',
    );
    // ignore: avoid_print
    print('CASE-100 evidence: observed=$observed tabsScanned=$scannedTexts');

    // ---- Expected result (unchanged from the original CASE-100) ----------
    expect(
      observed['approvalAllowed'],
      equals(false),
      reason: 'CASE-100: approvalAllowed does not match the real system result',
    );
    expect(
      observed['authorizationDenied'],
      equals(true),
      reason: 'CASE-100: authorizationDenied does not match the real system result',
    );

    await unmountApp(tester);
  });
}
