// HERITAGEBOT - TEST CASE 099
// Proponent: Shawn Guillmar C. Morales
// Module: Community Contribution Review
// Unit: Provide Feedback
// Description: Save reviewer feedback
// Expected: Attach feedback to submission
//
// TEST TYPE: Flutter widget test (host VM, no device / live Firebase).
//
// REAL CODE UNDER TEST (lib/, unmodified)
//   AuthGate -> AdminShell -> "Review" -> tap the story ->
//   AdminReviewSubmissionScreen "Administrator Feedback" field -> "Approve"
//   (HeritageBot saves feedback together with the review decision; the
//   screen has no separate "save feedback" button) ->
//   CommunitySubmissionService.reviewSubmission(adminFeedback) -> queue
//   refresh -> the story is opened again and its feedback field is read.
//
// FIXTURE (fixtureId = CASE-099): two PENDING stories; feedback is given on
// "Candles at the Cross" only.
//
// MOCKED: Firebase platform layer only (in-memory Firestore).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:heritagebot/models/community_submission.dart';

import '../support/admin_operations_flow.dart';

const String kTitle = 'Candles at the Cross';
const String kOther = 'My Lola and the Fort Walls';
const String kFeedback =
    'Approved. Thank you - please add the year your grandmother started '
    'lighting candles at the kiosk if you know it.';

late HeritageBotTestBackend backend;

void main() {
  setUpAll(() async {
    backend = await HeritageBotTestBackend.install(accounts: [kAdminAccount]);
  });

  setUp(() async {
    await backend.reset();
    seedRegisteredSites(backend, [kMagellansCross, bundledSite('fort_san_pedro')]);
    seedStory(backend, storyFixture(id: 'case099-story', title: kTitle, status: CommunitySubmissionStatus.pending, site: kMagellansCross));
    seedStory(backend, storyFixture(id: 'case099-other', title: kOther, status: CommunitySubmissionStatus.pending, site: bundledSite('fort_san_pedro'), contributorId: 'fixture-contributor-2'));
  });

  testWidgets('CASE-099 - Save reviewer feedback', (WidgetTester tester) async {
    usePhoneSurface(tester);
    const path = 'community_submissions/case099-story';
    const otherPath = 'community_submissions/case099-other';
    final otherBefore = '${storedSubmissions(backend)[otherPath]}';

    await openAdminShell(tester);
    await openReviewTab(tester);
    await openReviewCard(tester, kTitle);

    // STEP: type feedback and save it with the review decision.
    await enterReviewFeedback(tester, kFeedback);
    final closed = await tapReviewDecision(tester, 'Approve');
    final messages = shownSnackBarTexts(tester);

    // STEP: open the same story again from the refreshed queue.
    String? reopenedFeedback;
    if (closed) {
      await openReviewCard(tester, kTitle);
      final field = find.descendant(
        of: reviewDetailScreen,
        matching: find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.labelText == 'Administrator Feedback',
        ),
      );
      if (field.evaluate().isNotEmpty) {
        reopenedFeedback = tester.widget<TextField>(field).controller?.text;
      }
    }

    // ---- Observations -----------------------------------------------------
    final after = storedSubmissions(backend)[path];
    final otherAfter = storedSubmissions(backend)[otherPath];

    final observed = <String, Object?>{
      'feedbackSaved':
          closed &&
          messages.contains('Community story approved.') &&
          after?['adminFeedback'] == kFeedback &&
          reopenedFeedback == kFeedback,
      'correctSubmissionLinked':
          after != null &&
          CommunitySubmission.fromMap(after, documentId: 'case099-story').adminFeedback ==
              kFeedback &&
          after['title'] == kTitle &&
          '$otherAfter' == otherBefore &&
          otherAfter?['adminFeedback'] != kFeedback,
    };
    printOnFailure(
      'CASE-099 observed: $observed\nclosed=$closed messages=$messages\n'
      'reopenedFeedback=$reopenedFeedback\nafter=$after\notherAfter=$otherAfter',
    );
    // ignore: avoid_print
    print('CASE-099 evidence: observed=$observed storedFeedback="${after?['adminFeedback']}"');

    // ---- Expected result (unchanged from the original CASE-099) ----------
    expect(
      observed['feedbackSaved'],
      equals(true),
      reason: 'CASE-099: feedbackSaved does not match the real system result',
    );
    expect(
      observed['correctSubmissionLinked'],
      equals(true),
      reason: 'CASE-099: correctSubmissionLinked does not match the real system result',
    );

    await unmountApp(tester);
  });
}
