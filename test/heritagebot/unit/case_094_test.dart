// HERITAGEBOT - TEST CASE 094
// Proponent: Shawn Guillmar C. Morales
// Module: Community Contribution Review
// Unit: Review Community Contributions
// Description: Open pending review queue
// Expected: Show pending submissions
//
// TEST TYPE: Flutter widget test (host VM, no device / live Firebase).
//
// REAL CODE UNDER TEST (lib/, unmodified)
//   AuthGate -> AdminShell -> "Review" (AdminDashboardScreen) ->
//   CommunitySubmissionService.getAllSubmissions -> summary chips
//   ("Pending: N") -> "Pending" filter chip (_filtered).
//
// FIXTURE (fixtureId = CASE-094): community_submissions holds two PENDING
// stories (different sites and contributors), one APPROVED and one
// REJECTED story.
//
// MOCKED: Firebase platform layer only (in-memory Firestore).

import 'package:flutter_test/flutter_test.dart';

import 'package:heritagebot/models/community_submission.dart';

import '../support/admin_operations_flow.dart';

const String kPendingA = 'Candles at the Cross';
const String kPendingB = 'My Lola and the Fort Walls';
const String kApproved = 'Sinulog Morning Memories';
const String kRejected = 'Unverified Tunnel Rumour';

late HeritageBotTestBackend backend;

void main() {
  setUpAll(() async {
    backend = await HeritageBotTestBackend.install(accounts: [kAdminAccount]);
  });

  setUp(() async {
    await backend.reset();
    seedRegisteredSites(backend, [kMagellansCross, bundledSite('fort_san_pedro')]);
    seedStory(backend, storyFixture(id: 'case094-a', title: kPendingA, status: CommunitySubmissionStatus.pending, site: kMagellansCross, contributorName: 'Maria Santos'));
    seedStory(backend, storyFixture(id: 'case094-b', title: kPendingB, status: CommunitySubmissionStatus.pending, site: bundledSite('fort_san_pedro'), contributorId: 'fixture-contributor-2', contributorName: 'Jose Ramos', createdAtMillis: 1767312000000));
    seedStory(backend, storyFixture(id: 'case094-c', title: kApproved, status: CommunitySubmissionStatus.approved, site: kMagellansCross));
    seedStory(backend, storyFixture(id: 'case094-d', title: kRejected, status: CommunitySubmissionStatus.rejected, site: bundledSite('fort_san_pedro')));
  });

  testWidgets('CASE-094 - Open pending review queue', (WidgetTester tester) async {
    usePhoneSurface(tester);

    await openAdminShell(tester);
    await openReviewTab(tester);
    final allCards = await reviewQueueCards(tester);
    final pendingChip = reviewSummaryCount('Pending');
    final errorShown = infoCardsTitled(tester, 'Could Not Load Contributions').isNotEmpty;

    // STEP: tap the "Pending" filter.
    await tapReviewFilter(tester, 'Pending');
    final pendingCards = await reviewQueueCards(tester);

    // ---- Observations -----------------------------------------------------
    final storedPending = storedSubmissions(backend)
        .values
        .where((d) => d['status'] == CommunitySubmissionStatus.pending)
        .map((d) => d['title'])
        .toSet();
    final pendingLabel = CommunitySubmissionStatus.label(CommunitySubmissionStatus.pending);

    final observed = <String, Object?>{
      'reviewQueueVisible':
          reviewQueueScreen.evaluate().isNotEmpty &&
          !errorShown &&
          screenShowsText(reviewQueueScreen, 'Review Community Contributions') &&
          allCards.length == 4,
      'pendingStoriesLoaded':
          pendingChip == storedPending.length &&
          pendingCards.length == storedPending.length &&
          pendingCards.map((c) => c.title).toSet().containsAll(storedPending) &&
          pendingCards.every((c) => c.statusLabel == pendingLabel) &&
          pendingCards.any((c) => c.contributorLine == 'Contributor: Jose Ramos'),
    };
    printOnFailure(
      'CASE-094 observed: $observed\nallCards=$allCards\npendingChip=$pendingChip '
      'errorShown=$errorShown\npendingCards=$pendingCards\nstoredPending=$storedPending',
    );
    // ignore: avoid_print
    print('CASE-094 evidence: observed=$observed pendingCards=${pendingCards.map((c) => c.title).toList()}');

    // ---- Expected result (unchanged from the original CASE-094) ----------
    expect(
      observed['reviewQueueVisible'],
      equals(true),
      reason: 'CASE-094: reviewQueueVisible does not match the real system result',
    );
    expect(
      observed['pendingStoriesLoaded'],
      equals(true),
      reason: 'CASE-094: pendingStoriesLoaded does not match the real system result',
    );

    await unmountApp(tester);
  });
}
