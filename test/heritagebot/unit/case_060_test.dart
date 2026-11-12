// HERITAGEBOT - TEST CASE 060
// Proponent: James Stephen O. Ramos
// Module: Community Contributor Management
// Unit: Delete Submission
// Description: Cancel deletion.
// Expected: Preserve submission.
//
// TEST TYPE: Flutter widget test (host VM, no device / live Firebase).
//
// REAL CODE UNDER TEST (lib/, unmodified)
//   ContributorDashboardScreen card "Delete" -> _deleteSubmission ->
//   "Delete Submission?" AlertDialog -> "Cancel" (shouldDelete != true ->
//   return; CommunitySubmissionService.deletePendingSubmission must NOT run).
//
// FIXTURE (confirmDelete = false): one PENDING story owned by the
// signed-in contributor; the contributor taps Delete, then Cancel.
//
// MOCKED: Firebase platform layer only (in-memory Firestore).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:heritagebot/models/community_submission.dart';

import '../support/contributor_flow.dart';
import '../support/heritagebot_fixtures.dart';

const FakeAuthAccount kContributor = FakeAuthAccount(
  uid: 'case060-contributor-uid',
  email: 'case060.contributor@heritagebot.test',
  password: 'Case060Pass!',
  displayName: 'James Contributor',
);

final CommunitySubmission kStory = storyFixture(
  id: 'case060-pending',
  title: 'The Old Well Behind the Museum',
  status: CommunitySubmissionStatus.pending,
  site: bundledSite('casa_gorordo'),
  contributorId: kContributor.uid,
  contributorName: 'James Contributor',
);
const String kPath = 'community_submissions/case060-pending';

late HeritageBotTestBackend backend;

void main() {
  setUpAll(() async {
    backend = await HeritageBotTestBackend.install(accounts: [kContributor]);
  });

  setUp(() async {
    await backend.reset();
    seedContributor(backend, kContributor);
    seedStory(backend, kStory);
  });

  testWidgets('CASE-060 - Cancel deletion', (WidgetTester tester) async {
    usePhoneSurface(tester);
    final before = Map<String, dynamic>.of(backend.firestore.documents[kPath]!);

    await signInBeforeLaunch(kContributor);
    await openContributorDashboard(tester);

    // STEP: tap "Delete", then "Cancel" in the confirmation dialog.
    await tapCardAction(tester, title: kStory.title, action: 'Delete');
    await pumpUntilFound(tester, find.byType(AlertDialog));
    final dialogShown = find.text('Delete Submission?').evaluate().isNotEmpty;
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Cancel'),
      ),
    );
    await tester.pump();
    await pumpUntilGone(tester, find.byType(AlertDialog));
    await pumpFor(tester, const Duration(milliseconds: 800));

    // ---- Observations ---------------------------------------------------
    final after = backend.firestore.documents[kPath];
    final cards = await collectDashboardCards(tester);
    final messages = shownSnackBarTexts(tester);

    final observed = <String, Object?>{
      'submissionDeleted':
          after == null ||
          !cards.containsKey(kStory.title) ||
          messages.contains('Submission deleted.'),
      'storyPreserved':
          dialogShown &&
          after != null &&
          after['title'] == before['title'] &&
          after['story'] == before['story'] &&
          after['status'] == CommunitySubmissionStatus.pending &&
          cards[kStory.title]?.hasDelete == true,
    };
    printOnFailure(
      'CASE-060 observed: $observed\ndialogShown=$dialogShown '
      'messages=$messages\nafter=$after\ncards=${cards.values.toList()}',
    );

    // ---- Expected result (unchanged from the original CASE-060) ---------
    expect(
      observed['submissionDeleted'],
      equals(false),
      reason:
          'CASE-060: submissionDeleted does not match the real system result',
    );
    expect(
      observed['storyPreserved'],
      equals(true),
      reason: 'CASE-060: storyPreserved does not match the real system result',
    );

    await unmountApp(tester);
  });
}
