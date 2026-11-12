// HERITAGEBOT - TEST CASE 062
// Proponent: James Stephen O. Ramos
// Module: Community Contributor Management
// Unit: Track Submission Status
// Description: View approved or rejected submission.
// Expected: Display current review status.
//
// TEST TYPE: Flutter widget test (host VM, no device / live Firebase).
//
// REAL CODE UNDER TEST (lib/, unmodified)
//   CommunitySubmissionService.reviewSubmission (the Administrator's review
//   write) -> ContributorDashboardScreen -> getMySubmissions -> status chip
//   (CommunitySubmissionStatus.label) + status icon per card; Edit/Delete
//   are only offered while Pending.
//
// FIXTURE (fixtureId = CASE-062): two PENDING stories by the contributor.
// An Administrator then reviews them through the real service: one is
// APPROVED, the other REJECTED. The contributor opens the dashboard.
//
// MOCKED: Firebase platform layer only (in-memory Firestore).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:heritagebot/main.dart' as app;
import 'package:heritagebot/models/community_submission.dart';
import 'package:heritagebot/services/community_submission_service.dart';

import '../support/contributor_flow.dart';
import '../support/heritagebot_fixtures.dart';

const FakeAuthAccount kContributor = FakeAuthAccount(
  uid: 'case062-contributor-uid',
  email: 'case062.contributor@heritagebot.test',
  password: 'Case062Pass!',
  displayName: 'James Contributor',
);
// Signed-in account used only to perform the review write.
const FakeAuthAccount kAdmin = FakeAuthAccount(
  uid: 'case062-admin-uid',
  email: 'case062.admin@heritagebot.test',
  password: 'Case062Admin!',
  displayName: 'HeritageBot Administrator',
);

final CommunitySubmission kWillApprove = storyFixture(
  id: 'case062-approve',
  title: 'The Bells of the Old Parian Church',
  status: CommunitySubmissionStatus.pending,
  site: bundledSite('cebu_heritage_monument'),
  contributorId: kContributor.uid,
  contributorName: 'James Contributor',
  createdAtMillis: 1767312000000,
);
final CommunitySubmission kWillReject = storyFixture(
  id: 'case062-reject',
  title: 'A Rumour About a Hidden Tunnel',
  status: CommunitySubmissionStatus.pending,
  site: bundledSite('fort_san_pedro'),
  contributorId: kContributor.uid,
  contributorName: 'James Contributor',
);

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
    seedStory(backend, kWillApprove);
    seedStory(backend, kWillReject);
  });

  testWidgets('CASE-062 - View approved or rejected submission', (
    WidgetTester tester,
  ) async {
    usePhoneSurface(tester);

    // Administrator review through the real service.
    await tester.runAsync(() async {
      await signInBeforeLaunch(kAdmin);
      final service = CommunitySubmissionService();
      await service.reviewSubmission(
        submissionId: kWillApprove.id,
        status: CommunitySubmissionStatus.approved,
        adminFeedback: 'Approved by Administrator.',
      );
      await service.reviewSubmission(
        submissionId: kWillReject.id,
        status: CommunitySubmissionStatus.rejected,
        adminFeedback: 'Please cite a source for the tunnel story.',
      );
      await backend.auth.signOut();
    });
    final storedStatus = {
      for (final doc in storedSubmissions(backend).values)
        doc['title'] as String: doc['status'] as String,
    };

    await signInBeforeLaunch(kContributor);
    await openContributorDashboard(tester);

    // ---- Observations ---------------------------------------------------
    final cards = await collectDashboardCards(tester);
    final approved = cards[kWillApprove.title];
    final rejected = cards[kWillReject.title];

    bool cardHasIcon(String title, IconData icon) {
      final card = find
          .ancestor(
            of: find.descendant(
              of: find.byType(app.ContributorDashboardScreen),
              matching: find.text(title),
            ),
            matching: find.byType(Card),
          )
          .first;
      return find
          .descendant(of: card, matching: find.byIcon(icon))
          .evaluate()
          .isNotEmpty;
    }

    final observed = <String, Object?>{
      'reviewStatusVisible':
          approved != null &&
          rejected != null &&
          approved.statusLabel.isNotEmpty &&
          rejected.statusLabel.isNotEmpty,
      'correctReviewStatus':
          approved != null &&
          rejected != null &&
          statusForLabel(approved.statusLabel) ==
              storedStatus[kWillApprove.title] &&
          statusForLabel(rejected.statusLabel) ==
              storedStatus[kWillReject.title] &&
          approved.statusLabel == 'Approved' &&
          rejected.statusLabel == 'Rejected' &&
          cardHasIcon(kWillApprove.title, Icons.check_circle_rounded) &&
          cardHasIcon(kWillReject.title, Icons.cancel_rounded) &&
          // Reviewed submissions are no longer editable/deletable.
          !approved.hasEdit &&
          !approved.hasDelete &&
          !rejected.hasEdit &&
          !rejected.hasDelete,
    };
    printOnFailure(
      'CASE-062 observed: $observed\nstoredStatus=$storedStatus\n'
      'cards=${cards.values.toList()}',
    );

    // ---- Expected result (unchanged from the original CASE-062) ---------
    expect(
      observed['reviewStatusVisible'],
      equals(true),
      reason:
          'CASE-062: reviewStatusVisible does not match the real system result',
    );
    expect(
      observed['correctReviewStatus'],
      equals(true),
      reason:
          'CASE-062: correctReviewStatus does not match the real system result',
    );

    await unmountApp(tester);
  });
}
