// HERITAGEBOT - TEST CASE 071
// Proponent: James Stephen O. Ramos
// Module: Administrator Dashboard
// Unit: View System Summary
// Description: Open admin dashboard
// Expected: Show system summary
//
// TEST TYPE: Flutter widget test (host VM, no device / live Firebase).
//
// REAL CODE UNDER TEST (lib/, unmodified)
//   AuthGate -> UserService.getUserProfile (authorized administrator e-mail
//   -> role "admin") -> AdminShell -> first tab "Summary" =
//   AdminAnalyticsScreen -> AdminAnalyticsService.loadSnapshot()
//   (UserService.getAllUsers, HeritageSiteService.getAllSites,
//   CommunitySubmissionService.getAllSubmissions, ai_narratives,
//   usage_events, bookmarks) -> "System Summary" metric cards.
//
// CONTROLLED DATA (isolated in-memory Firestore)
//   users: 3 tourists (1 suspended) + 2 community contributors, plus the
//          administrator profile that UserService itself writes on login.
//   heritage_sites: Magellan's Cross, Casa Gorordo Museum (official) and
//          the UCLM testing site.
//   community_submissions: 2 pending, 1 approved, 1 rejected.
//
// MOCKED: Firebase platform layer only (FakeFirebaseAuthPlatform /
// FakeFirebaseFirestorePlatform). No HeritageBot widget is replaced.

import 'package:flutter_test/flutter_test.dart';

import 'package:heritagebot/main.dart' as app;
import 'package:heritagebot/models/community_submission.dart';
import 'package:heritagebot/models/user_profile.dart';

import '../support/admin_flow.dart';

const List<SeedUser> kUsers = [
  SeedUser(
    uid: 'case071-tourist-1',
    fullName: 'Ana Villanueva',
    email: 'ana.villanueva@heritagebot.test',
    role: UserRoles.tourist,
  ),
  SeedUser(
    uid: 'case071-tourist-2',
    fullName: 'Ben Dizon',
    email: 'ben.dizon@heritagebot.test',
    role: UserRoles.tourist,
  ),
  SeedUser(
    uid: 'case071-tourist-3',
    fullName: 'Carla Uy',
    email: 'carla.uy@heritagebot.test',
    role: UserRoles.tourist,
    accountStatus: 'suspended',
  ),
  SeedUser(
    uid: 'case071-contributor-1',
    fullName: 'Dario Lim',
    email: 'dario.lim@heritagebot.test',
    role: UserRoles.communityContributor,
  ),
  SeedUser(
    uid: 'case071-contributor-2',
    fullName: 'Elena Cruz',
    email: 'elena.cruz@heritagebot.test',
    role: UserRoles.communityContributor,
  ),
];

late HeritageBotTestBackend backend;

void main() {
  setUpAll(() async {
    backend = await HeritageBotTestBackend.install(accounts: [kAdminAccount]);
  });

  setUp(() async {
    await backend.reset();
    for (final user in kUsers) {
      seedUser(backend, user);
    }
    seedRegisteredSites(backend, [
      kMagellansCross,
      bundledSite('casa_gorordo'),
      bundledSite('uclm'),
    ]);
    final site = bundledSite('casa_gorordo');
    for (final story in [
      storyFixture(id: 's1', title: 'Pending One', status: CommunitySubmissionStatus.pending, site: site),
      storyFixture(id: 's2', title: 'Pending Two', status: CommunitySubmissionStatus.pending, site: site),
      storyFixture(id: 's3', title: 'Approved One', status: CommunitySubmissionStatus.approved, site: site),
      storyFixture(id: 's4', title: 'Rejected One', status: CommunitySubmissionStatus.rejected, site: site),
    ]) {
      seedStory(backend, story);
    }
  });

  testWidgets('CASE-071 - Open admin dashboard', (WidgetTester tester) async {
    usePhoneSurface(tester);

    // STEP: the authorized administrator opens HeritageBot (real AuthGate).
    await openAdminShell(tester);

    // ---- Observations -----------------------------------------------------
    final shell = find.byType(app.AdminShell).evaluate().isNotEmpty;
    final summaryScreen = adminSummaryScreen.evaluate().isNotEmpty;
    final view = await readAdminSummary(tester);
    final loadError = infoCardsTitled(tester, 'Could Not Load Analytics');

    // Ground truth = the dashboard's data source (the isolated Firestore).
    final users = storedUsers(backend).values.toList();
    final sites = storedSites(backend).values.toList();
    final submissions = storedSubmissions(backend).values.toList();
    int countStatus(String s) =>
        submissions.where((d) => d['status'] == s).length;
    final expected = <String, String>{
      'Total Users': '${users.length}',
      'Total Heritage Sites': '${sites.length}',
      'Community Submissions': '${submissions.length}',
      'Approval Rate':
          '${(countStatus(CommunitySubmissionStatus.approved) / submissions.length * 100).round()}%',
    };
    final shown = <String, String?>{
      for (final label in expected.keys) label: view.metricValue(label),
    };

    final observed = <String, Object?>{
      // The real AdminShell opened on its "System Summary" screen with the
      // summary metric cards rendered.
      'adminSummaryVisible':
          shell &&
          summaryScreen &&
          view.appBarTitle == 'System Summary' &&
          loadError.isEmpty &&
          expected.keys.every(view.metrics.containsKey),
      // Every summary value equals the controlled data in the data source
      // (5 seeded accounts + the admin profile the app writes = 6 users).
      'summaryDataAvailable':
          users.length == kUsers.length + 1 &&
          sites.length == 3 &&
          submissions.length == 4 &&
          expected.entries.every((e) => shown[e.key] == e.value) &&
          view.metricSubtitle('Total Users') == '5 active • 1 suspended' &&
          view.metricSubtitle('Total Heritage Sites') ==
              '2 official • 1 testing' &&
          view.metricSubtitle('Community Submissions') ==
              '2 pending • 1 approved • 1 rejected',
    };
    printOnFailure(
      'CASE-071 observed: $observed\nexpected=$expected shown=$shown\n'
      'loadError=${loadError.map((c) => c.body)}\nview=$view',
    );

    // ---- Expected result (unchanged from the original CASE-071) ----------
    expect(
      observed['adminSummaryVisible'],
      equals(true),
      reason: 'CASE-071: adminSummaryVisible does not match the real system result',
    );
    expect(
      observed['summaryDataAvailable'],
      equals(true),
      reason: 'CASE-071: summaryDataAvailable does not match the real system result',
    );

    await unmountApp(tester);
  });
}
