// HERITAGEBOT - TEST CASE 101
// Proponent: Shawn Guillmar C. Morales
// Module: Community Contribution Review
// Unit: Approve Contribution
// Description: Approve already reviewed submission
// Expected: Prevent invalid repeated transition
//
// TEST TYPE: Flutter widget test (host VM, no device / live Firebase).
//
// REAL CODE UNDER TEST (lib/, unmodified)
//   AuthGate -> AdminShell -> "Review" -> tap the already APPROVED story ->
//   AdminReviewSubmissionScreen -> "Approve" -> _review(approved) ->
//   CommunitySubmissionService.reviewSubmission.
//
// FIXTURE (storyFixture = already_reviewed): a story that an administrator
// already approved (status "approved", adminFeedback "Approved by
// Administrator.", reviewed on 2026-01-02). The administrator approves it
// again.
//
// WHAT IS OBSERVED: whether HeritageBot performs a second approval
// (success message / new review write) or refuses the repeated transition,
// and whether the stored review record is left exactly as it was.
//
// MOCKED: Firebase platform layer only (in-memory Firestore).

import 'package:flutter_test/flutter_test.dart';

import 'package:heritagebot/models/community_submission.dart';

import '../support/admin_operations_flow.dart';

const String kTitle = 'Sinulog Morning Memories';

late HeritageBotTestBackend backend;

void main() {
  setUpAll(() async {
    backend = await HeritageBotTestBackend.install(accounts: [kAdminAccount]);
  });

  setUp(() async {
    await backend.reset();
    seedRegisteredSites(backend, [kMagellansCross]);
    seedStory(backend, storyFixture(id: 'case101-story', title: kTitle, status: CommunitySubmissionStatus.approved, site: kMagellansCross));
  });

  testWidgets('CASE-101 - Approve already reviewed submission', (WidgetTester tester) async {
    usePhoneSurface(tester);
    const path = 'community_submissions/case101-story';
    final before = Map<String, dynamic>.of(storedSubmissions(backend)[path]!);

    await openAdminShell(tester);
    await openReviewTab(tester);
    await openReviewCard(tester, kTitle);
    final approveOffered = find
        .descendant(of: reviewDetailScreen, matching: find.text('Approve'))
        .evaluate()
        .isNotEmpty;

    // STEP: approve the already approved story again.
    var closed = false;
    if (approveOffered) {
      closed = await tapReviewDecision(tester, 'Approve');
    }
    final messages = shownSnackBarTexts(tester);

    // ---- Observations -----------------------------------------------------
    final after = storedSubmissions(backend)[path];
    final observed = <String, Object?>{
      // A repeat approval = HeritageBot confirmed it OR wrote a new review.
      'repeatApprovalAllowed':
          messages.contains('Community story approved.') ||
          after?['updatedAtMillis'] != before['updatedAtMillis'],
      'reviewStatePreserved': '$after' == '$before',
    };
    printOnFailure(
      'CASE-101 observed: $observed\napproveOffered=$approveOffered closed=$closed '
      'messages=$messages\nbefore=$before\nafter=$after',
    );
    // ignore: avoid_print
    print('CASE-101 evidence: observed=$observed approveOffered=$approveOffered '
        'messages=$messages updatedAt ${before['updatedAtMillis']} -> ${after?['updatedAtMillis']}');

    // ---- Expected result (unchanged from the original CASE-101) ----------
    expect(
      observed['repeatApprovalAllowed'],
      equals(false),
      reason: 'CASE-101: repeatApprovalAllowed does not match the real system result',
    );
    expect(
      observed['reviewStatePreserved'],
      equals(true),
      reason: 'CASE-101: reviewStatePreserved does not match the real system result',
    );

    await unmountApp(tester);
  });
}
