// HERITAGEBOT - TEST CASE 056
// Proponent: James Stephen O. Ramos
// Module: Community Contributor Management
// Unit: Manage Submissions
// Description: Open own submissions.
// Expected: List contributor submissions.
//
// TEST TYPE: Flutter widget test (host VM, no device / live Firebase).
//
// REAL CODE UNDER TEST (lib/, unmodified)
//   AuthGate (role = community_contributor) -> MainShell "Contribute" ->
//   ContributorDashboardScreen ("My Submissions") ->
//   CommunitySubmissionService.getMySubmissions
//   (where contributorId == current uid).
//
// FIXTURE (fixtureId = CASE-056): Firestore community_submissions holds
//   * 2 stories by the signed-in contributor (1 pending, 1 approved),
//   * 1 story by a DIFFERENT contributor (must not be listed).
//
// MOCKED: Firebase platform layer only (in-memory Firestore).

import 'package:flutter_test/flutter_test.dart';

import 'package:heritagebot/main.dart' as app;
import 'package:heritagebot/models/community_submission.dart';

import '../support/contributor_flow.dart';
import '../support/heritagebot_fixtures.dart';

const FakeAuthAccount kContributor = FakeAuthAccount(
  uid: 'case056-contributor-uid',
  email: 'case056.contributor@heritagebot.test',
  password: 'Case056Pass!',
  displayName: 'James Contributor',
);
const String kOtherContributorUid = 'case056-other-contributor-uid';

final List<CommunitySubmission> kOwnStories = [
  storyFixture(
    id: 'case056-own-pending',
    title: 'Evening Bells of Casa Gorordo',
    status: CommunitySubmissionStatus.pending,
    site: bundledSite('casa_gorordo'),
    contributorId: kContributor.uid,
    contributorName: 'James Contributor',
    createdAtMillis: 1767312000000,
  ),
  storyFixture(
    id: 'case056-own-approved',
    title: 'Fort San Pedro at Low Tide',
    status: CommunitySubmissionStatus.approved,
    site: bundledSite('fort_san_pedro'),
    contributorId: kContributor.uid,
    contributorName: 'James Contributor',
    createdAtMillis: 1767225600000,
  ),
];

final CommunitySubmission kOtherStory = storyFixture(
  id: 'case056-other-pending',
  title: 'A Stranger at the Monument',
  status: CommunitySubmissionStatus.pending,
  site: bundledSite('cebu_heritage_monument'),
  contributorId: kOtherContributorUid,
  contributorName: 'Maria Santos',
);

late HeritageBotTestBackend backend;

void main() {
  setUpAll(() async {
    backend = await HeritageBotTestBackend.install(accounts: [kContributor]);
  });

  setUp(() async {
    await backend.reset();
    seedContributor(backend, kContributor);
    for (final story in [...kOwnStories, kOtherStory]) {
      seedStory(backend, story);
    }
  });

  testWidgets('CASE-056 - Open own submissions', (WidgetTester tester) async {
    usePhoneSurface(tester);

    await signInBeforeLaunch(kContributor);
    await openContributorDashboard(tester);

    // ---- Observations ---------------------------------------------------
    final cards = await collectDashboardCards(tester);
    final listedTitles = cards.keys.toSet();
    final ownTitles = kOwnStories.map((s) => s.title).toSet();
    final emptyStateShown = find
        .descendant(
          of: find.byType(app.ContributorDashboardScreen),
          matching: find.text('No Submissions Yet'),
        )
        .evaluate()
        .isNotEmpty;

    final observed = <String, Object?>{
      'submissionListVisible':
          find.text('My Submissions').evaluate().isNotEmpty &&
          !emptyStateShown &&
          listedTitles.containsAll(ownTitles),
      'onlyOwnSubmissions':
          listedTitles.isNotEmpty &&
          listedTitles.length == ownTitles.length &&
          listedTitles.difference(ownTitles).isEmpty &&
          !listedTitles.contains(kOtherStory.title),
    };
    printOnFailure(
      'CASE-056 observed: $observed\ncards=${cards.values.toList()}',
    );

    // ---- Expected result (unchanged from the original CASE-056) ---------
    expect(
      observed['submissionListVisible'],
      equals(true),
      reason:
          'CASE-056: submissionListVisible does not match the real system result',
    );
    expect(
      observed['onlyOwnSubmissions'],
      equals(true),
      reason:
          'CASE-056: onlyOwnSubmissions does not match the real system result',
    );

    await unmountApp(tester);
  });
}
