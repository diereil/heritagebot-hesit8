// HERITAGEBOT - TEST CASE 063
// Proponent: James Stephen O. Ramos
// Module: Community Contributor Management
// Unit: View Feedback
// Description: Open reviewed submission.
// Expected: Display administrator feedback.
//
// TEST TYPE: Flutter widget test (host VM, no device / live Firebase).
//
// REAL CODE UNDER TEST (lib/, unmodified)
//   CommunitySubmissionService.reviewSubmission (stores adminFeedback) ->
//   ContributorDashboardScreen -> getMySubmissions -> each card's
//   "Admin Feedback: ..." panel.
//
// FIXTURE (fixtureId = CASE-063): two of the contributor's stories are
// reviewed by an Administrator with DIFFERENT feedback (one rejected with
// guidance, one approved with a thank-you note); a third story is still
// pending and has no feedback. Each card must show its own feedback.
//
// MOCKED: Firebase platform layer only (in-memory Firestore).

import 'package:flutter_test/flutter_test.dart';

import 'package:heritagebot/models/community_submission.dart';
import 'package:heritagebot/services/community_submission_service.dart';

import '../support/contributor_flow.dart';
import '../support/heritagebot_fixtures.dart';

const FakeAuthAccount kContributor = FakeAuthAccount(
  uid: 'case063-contributor-uid',
  email: 'case063.contributor@heritagebot.test',
  password: 'Case063Pass!',
  displayName: 'James Contributor',
);
const FakeAuthAccount kAdmin = FakeAuthAccount(
  uid: 'case063-admin-uid',
  email: 'case063.admin@heritagebot.test',
  password: 'Case063Admin!',
  displayName: 'HeritageBot Administrator',
);

final CommunitySubmission kRejected = storyFixture(
  id: 'case063-rejected',
  title: 'Legend of the Fort Cannon',
  status: CommunitySubmissionStatus.pending,
  site: bundledSite('fort_san_pedro'),
  contributorId: kContributor.uid,
  contributorName: 'James Contributor',
  createdAtMillis: 1767398400000,
);
final CommunitySubmission kApproved = storyFixture(
  id: 'case063-approved',
  title: 'Capiz Windows of Casa Gorordo',
  status: CommunitySubmissionStatus.pending,
  site: bundledSite('casa_gorordo'),
  contributorId: kContributor.uid,
  contributorName: 'James Contributor',
  createdAtMillis: 1767312000000,
);
final CommunitySubmission kStillPending = storyFixture(
  id: 'case063-pending',
  title: 'Not Yet Reviewed Story',
  status: CommunitySubmissionStatus.pending,
  site: bundledSite('cebu_heritage_monument'),
  contributorId: kContributor.uid,
  contributorName: 'James Contributor',
);

const String kRejectFeedback =
    'Please add the year of the event and cite where the legend comes from.';
const String kApproveFeedback =
    'Thank you! Your description of the capiz windows is accurate.';

late HeritageBotTestBackend backend;

void main() {
  setUpAll(() async {
    backend = await HeritageBotTestBackend.install(
      accounts: [kContributor, kAdmin],
    );
  });

  setUp(() async {
    await backend.reset();
    seedContributor(backend, kContributor);
    for (final story in [kRejected, kApproved, kStillPending]) {
      seedStory(backend, story);
    }
  });

  testWidgets('CASE-063 - Open reviewed submission', (
    WidgetTester tester,
  ) async {
    usePhoneSurface(tester);

    // Administrator review through the real service.
    await tester.runAsync(() async {
      await signInBeforeLaunch(kAdmin);
      final service = CommunitySubmissionService();
      await service.reviewSubmission(
        submissionId: kRejected.id,
        status: CommunitySubmissionStatus.rejected,
        adminFeedback: kRejectFeedback,
      );
      await service.reviewSubmission(
        submissionId: kApproved.id,
        status: CommunitySubmissionStatus.approved,
        adminFeedback: kApproveFeedback,
      );
      await backend.auth.signOut();
    });

    await signInBeforeLaunch(kContributor);
    await openContributorDashboard(tester);

    // ---- Observations ---------------------------------------------------
    final cards = await collectDashboardCards(tester);
    final rejected = cards[kRejected.title];
    final approved = cards[kApproved.title];
    final pending = cards[kStillPending.title];

    final observed = <String, Object?>{
      'reviewFeedbackVisible':
          rejected?.feedbackText != null && approved?.feedbackText != null,
      'correctFeedbackShown':
          rejected?.feedbackText == 'Admin Feedback: $kRejectFeedback' &&
          approved?.feedbackText == 'Admin Feedback: $kApproveFeedback' &&
          pending != null &&
          pending.feedbackText == null,
    };
    printOnFailure(
      'CASE-063 observed: $observed\n'
      'cards=${cards.values.toList()}\nstored=${storedSubmissions(backend)}',
    );

    // ---- Expected result (unchanged from the original CASE-063) ---------
    expect(
      observed['reviewFeedbackVisible'],
      equals(true),
      reason:
          'CASE-063: reviewFeedbackVisible does not match the real system result',
    );
    expect(
      observed['correctFeedbackShown'],
      equals(true),
      reason:
          'CASE-063: correctFeedbackShown does not match the real system result',
    );

    await unmountApp(tester);
  });
}
