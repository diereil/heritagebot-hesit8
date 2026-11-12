// HERITAGEBOT - TEST CASE 059
// Proponent: James Stephen O. Ramos
// Module: Community Contributor Management
// Unit: Delete Submission
// Description: Delete own eligible submission.
// Expected: Remove submission after confirmation.
//
// TEST TYPE: Flutter widget test (host VM, no device / live Firebase).
//
// REAL CODE UNDER TEST (lib/, unmodified)
//   ContributorDashboardScreen card "Delete" (Pending only) ->
//   _deleteSubmission -> "Delete Submission?" AlertDialog -> "Delete" ->
//   CommunityMediaService.deleteMediaUrls + CommunitySubmissionService
//   .deletePendingSubmission -> Firestore delete -> dashboard refresh.
//
// FIXTURE (fixtureId = CASE-059): two PENDING stories owned by the
// signed-in contributor; only one is deleted (the other must remain).
//
// MOCKED: Firebase platform layer only (in-memory Firestore).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:heritagebot/models/community_submission.dart';

import '../support/contributor_flow.dart';
import '../support/heritagebot_fixtures.dart';

const FakeAuthAccount kContributor = FakeAuthAccount(
  uid: 'case059-contributor-uid',
  email: 'case059.contributor@heritagebot.test',
  password: 'Case059Pass!',
  displayName: 'James Contributor',
);

final CommunitySubmission kToDelete = storyFixture(
  id: 'case059-delete-me',
  title: 'Duplicate Draft About Casa Gorordo',
  status: CommunitySubmissionStatus.pending,
  site: bundledSite('casa_gorordo'),
  contributorId: kContributor.uid,
  contributorName: 'James Contributor',
  createdAtMillis: 1767312000000,
);
final CommunitySubmission kToKeep = storyFixture(
  id: 'case059-keep-me',
  title: 'Market Day Beside Fort San Pedro',
  status: CommunitySubmissionStatus.pending,
  site: bundledSite('fort_san_pedro'),
  contributorId: kContributor.uid,
  contributorName: 'James Contributor',
);
const String kDeletePath = 'community_submissions/case059-delete-me';
const String kKeepPath = 'community_submissions/case059-keep-me';

late HeritageBotTestBackend backend;

void main() {
  setUpAll(() async {
    backend = await HeritageBotTestBackend.install(accounts: [kContributor]);
  });

  setUp(() async {
    await backend.reset();
    seedContributor(backend, kContributor);
    seedStory(backend, kToDelete);
    seedStory(backend, kToKeep);
  });

  testWidgets('CASE-059 - Delete own eligible submission', (
    WidgetTester tester,
  ) async {
    usePhoneSurface(tester);

    await signInBeforeLaunch(kContributor);
    await openContributorDashboard(tester);

    // STEP: tap "Delete" on the card.
    await tapCardAction(tester, title: kToDelete.title, action: 'Delete');
    await pumpUntilFound(tester, find.byType(AlertDialog));
    final dialog = find.byType(AlertDialog);
    final dialogShown = find
        .descendant(of: dialog, matching: find.text('Delete Submission?'))
        .evaluate()
        .isNotEmpty;
    // Nothing is deleted while the confirmation is still open.
    final keptWhileAsking = backend.firestore.documents.containsKey(
      kDeletePath,
    );

    // STEP: confirm with the dialog's "Delete" button.
    await tester.tap(
      find.descendant(of: dialog, matching: find.text('Delete')),
    );
    await tester.pump();
    await pumpUntilFound(tester, snackBarWithText('Submission deleted.'));
    await pumpFor(tester, const Duration(milliseconds: 500));

    // ---- Observations ---------------------------------------------------
    final dialogClosed = find.byType(AlertDialog).evaluate().isEmpty;
    final cards = await collectDashboardCards(tester);

    final observed = <String, Object?>{
      'submissionDeleted':
          !backend.firestore.documents.containsKey(kDeletePath) &&
          backend.firestore.documents.containsKey(kKeepPath) &&
          !cards.containsKey(kToDelete.title) &&
          cards.containsKey(kToKeep.title),
      'confirmationAccepted': dialogShown && keptWhileAsking && dialogClosed,
    };
    printOnFailure(
      'CASE-059 observed: $observed\n'
      'dialogShown=$dialogShown keptWhileAsking=$keptWhileAsking '
      'dialogClosed=$dialogClosed\nstored=${storedSubmissions(backend).keys}\n'
      'cards=${cards.values.toList()}',
    );

    // ---- Expected result (unchanged from the original CASE-059) ---------
    expect(
      observed['submissionDeleted'],
      equals(true),
      reason:
          'CASE-059: submissionDeleted does not match the real system result',
    );
    expect(
      observed['confirmationAccepted'],
      equals(true),
      reason:
          'CASE-059: confirmationAccepted does not match the real system result',
    );

    await unmountApp(tester);
  });
}
