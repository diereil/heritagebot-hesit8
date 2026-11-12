// HERITAGEBOT - TEST CASE 098
// Proponent: Shawn Guillmar C. Morales
// Module: Community Contribution Review
// Unit: Reject Contribution
// Description: Reject unsuitable submission
// Expected: Set status rejected
//
// TEST TYPE: Flutter widget test (host VM, no device / live Firebase).
//
// REAL CODE UNDER TEST (lib/, unmodified)
//   AuthGate -> AdminShell -> "Review" -> tap the pending story ->
//   AdminReviewSubmissionScreen -> "Administrator Feedback" (required when
//   rejecting) -> "Reject" -> _review(rejected) ->
//   CommunitySubmissionService.reviewSubmission -> pop(true) -> queue refresh.
//
// FIXTURE (fixtureId = CASE-098): an unsuitable PENDING story (an
// unverified rumour presented as history) plus a second pending story that
// must stay pending.
//
// MOCKED: Firebase platform layer only (in-memory Firestore).

import 'package:flutter_test/flutter_test.dart';

import 'package:heritagebot/models/community_submission.dart';

import '../support/admin_operations_flow.dart';

const String kTitle = 'Secret Tunnel Under the Fort';
const String kStory =
    'People say there is a secret tunnel from the fort all the way to the '
    'cathedral that was used to hide gold, but nobody I know has seen it and '
    'I could not find any record of it anywhere.';
const String kFeedback =
    'Rejected: the story presents an unverified rumour as history. Please '
    'share a personal memory or cite a reliable source.';

late HeritageBotTestBackend backend;

void main() {
  setUpAll(() async {
    backend = await HeritageBotTestBackend.install(accounts: [kAdminAccount]);
  });

  setUp(() async {
    await backend.reset();
    seedRegisteredSites(backend, [kMagellansCross, bundledSite('fort_san_pedro')]);
    seedStory(backend, storyFixture(id: 'case098-story', title: kTitle, status: CommunitySubmissionStatus.pending, site: bundledSite('fort_san_pedro'), story: kStory));
    seedStory(backend, storyFixture(id: 'case098-other', title: 'Candles at the Cross', status: CommunitySubmissionStatus.pending, site: kMagellansCross, contributorId: 'fixture-contributor-2'));
  });

  testWidgets('CASE-098 - Reject unsuitable submission', (WidgetTester tester) async {
    usePhoneSurface(tester);
    const path = 'community_submissions/case098-story';
    const otherPath = 'community_submissions/case098-other';
    final before = Map<String, dynamic>.of(storedSubmissions(backend)[path]!);
    final otherBefore = '${storedSubmissions(backend)[otherPath]}';

    await openAdminShell(tester);
    await openReviewTab(tester);
    await openReviewCard(tester, kTitle);

    // STEP: explain the rejection, then "Reject".
    await enterReviewFeedback(tester, kFeedback);
    final closed = await tapReviewDecision(tester, 'Reject');
    final messages = shownSnackBarTexts(tester);
    final cards = await reviewQueueCards(tester);

    // ---- Observations -----------------------------------------------------
    final after = storedSubmissions(backend)[path];
    final card = cards.where((c) => c.title == kTitle).firstOrNull;
    final rejectedLabel = CommunitySubmissionStatus.label(CommunitySubmissionStatus.rejected);

    final observed = <String, Object?>{
      'reviewStatus': after?['status'],
      'reviewPersisted':
          closed &&
          messages.contains('Community story rejected.') &&
          after != null &&
          CommunitySubmission.fromMap(after, documentId: 'case098-story').status ==
              CommunitySubmissionStatus.rejected &&
          after['adminFeedback'] == kFeedback &&
          (after['updatedAtMillis'] as num) > (before['updatedAtMillis'] as num) &&
          card?.statusLabel == rejectedLabel &&
          reviewSummaryCount('Rejected') == 1 &&
          '${storedSubmissions(backend)[otherPath]}' == otherBefore,
    };
    printOnFailure(
      'CASE-098 observed: $observed\nclosed=$closed messages=$messages\n'
      'before=$before\nafter=$after\ncard=$card',
    );
    // ignore: avoid_print
    print('CASE-098 evidence: observed=$observed queueLabel=${card?.statusLabel}');

    // ---- Expected result (unchanged from the original CASE-098) ----------
    expect(
      observed['reviewStatus'],
      equals('rejected'),
      reason: 'CASE-098: reviewStatus does not match the real system result',
    );
    expect(
      observed['reviewPersisted'],
      equals(true),
      reason: 'CASE-098: reviewPersisted does not match the real system result',
    );

    await unmountApp(tester);
  });
}
