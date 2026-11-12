// HERITAGEBOT - TEST CASE 097
// Proponent: Shawn Guillmar C. Morales
// Module: Community Contribution Review
// Unit: Approve Contribution
// Description: Approve valid submission
// Expected: Set status approved
//
// TEST TYPE: Flutter widget test (host VM, no device / live Firebase).
//
// REAL CODE UNDER TEST (lib/, unmodified)
//   AuthGate -> AdminShell -> "Review" -> tap the pending story ->
//   AdminReviewSubmissionScreen -> "Approve" -> _review(approved) ->
//   CommunitySubmissionService.reviewSubmission (status, adminFeedback,
//   updatedAtMillis) -> pop(true) -> AdminDashboardScreen._refresh.
//
// FIXTURE (fixtureId = CASE-097): a valid PENDING story (title >= 5 chars,
// story >= 80 chars) plus a second pending story that must stay pending.
//
// MOCKED: Firebase platform layer only (in-memory Firestore).

import 'package:flutter_test/flutter_test.dart';

import 'package:heritagebot/models/community_submission.dart';

import '../support/admin_operations_flow.dart';

const String kTitle = 'Candles at the Cross';
const String kOther = 'My Lola and the Fort Walls';

late HeritageBotTestBackend backend;

void main() {
  setUpAll(() async {
    backend = await HeritageBotTestBackend.install(accounts: [kAdminAccount]);
  });

  setUp(() async {
    await backend.reset();
    seedRegisteredSites(backend, [kMagellansCross, bundledSite('fort_san_pedro')]);
    seedStory(backend, storyFixture(id: 'case097-story', title: kTitle, status: CommunitySubmissionStatus.pending, site: kMagellansCross));
    seedStory(backend, storyFixture(id: 'case097-other', title: kOther, status: CommunitySubmissionStatus.pending, site: bundledSite('fort_san_pedro'), contributorId: 'fixture-contributor-2'));
  });

  testWidgets('CASE-097 - Approve valid submission', (WidgetTester tester) async {
    usePhoneSurface(tester);
    const path = 'community_submissions/case097-story';
    const otherPath = 'community_submissions/case097-other';
    final before = Map<String, dynamic>.of(storedSubmissions(backend)[path]!);
    final otherBefore = '${storedSubmissions(backend)[otherPath]}';

    await openAdminShell(tester);
    await openReviewTab(tester);
    await openReviewCard(tester, kTitle);

    // STEP: "Approve".
    final closed = await tapReviewDecision(tester, 'Approve');
    final messages = shownSnackBarTexts(tester);
    final cards = await reviewQueueCards(tester);

    // ---- Observations -----------------------------------------------------
    final after = storedSubmissions(backend)[path];
    final card = cards.where((c) => c.title == kTitle).firstOrNull;
    final approvedLabel = CommunitySubmissionStatus.label(CommunitySubmissionStatus.approved);

    final observed = <String, Object?>{
      'reviewStatus': after?['status'],
      'reviewPersisted':
          closed &&
          messages.contains('Community story approved.') &&
          after != null &&
          CommunitySubmission.fromMap(after, documentId: 'case097-story').status ==
              CommunitySubmissionStatus.approved &&
          (after['updatedAtMillis'] as num) > (before['updatedAtMillis'] as num) &&
          after['story'] == before['story'] &&
          card?.statusLabel == approvedLabel &&
          reviewSummaryCount('Approved') == 1 &&
          '${storedSubmissions(backend)[otherPath]}' == otherBefore,
    };
    printOnFailure(
      'CASE-097 observed: $observed\nclosed=$closed messages=$messages\n'
      'before=$before\nafter=$after\ncard=$card',
    );
    // ignore: avoid_print
    print('CASE-097 evidence: observed=$observed queueLabel=${card?.statusLabel}');

    // ---- Expected result (unchanged from the original CASE-097) ----------
    expect(
      observed['reviewStatus'],
      equals('approved'),
      reason: 'CASE-097: reviewStatus does not match the real system result',
    );
    expect(
      observed['reviewPersisted'],
      equals(true),
      reason: 'CASE-097: reviewPersisted does not match the real system result',
    );

    await unmountApp(tester);
  });
}
