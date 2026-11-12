// HERITAGEBOT - TEST CASE 057
// Proponent: James Stephen O. Ramos
// Module: Community Contributor Management
// Unit: Edit Submission
// Description: Edit pending submission.
// Expected: Save permitted changes.
//
// TEST TYPE: Flutter widget test (host VM, no device / live Firebase).
//
// REAL CODE UNDER TEST (lib/, unmodified)
//   ContributorDashboardScreen card "Edit" (shown for Pending only) ->
//   EditCommunityStoryScreen._saveChanges -> CommunitySubmissionService
//   .updatePendingSubmission -> Firestore community_submissions/{id}
//   (update) -> dashboard refresh.
//
// FIXTURE (fixtureId = CASE-057): one PENDING story owned by the signed-in
// contributor. The contributor changes the title and the story text (both
// still valid: >= 5 / >= 80 characters).
//
// MOCKED: Firebase platform layer only (in-memory Firestore).

import 'package:flutter_test/flutter_test.dart';

import 'package:heritagebot/main.dart' as app;
import 'package:heritagebot/models/community_submission.dart';

import '../support/contributor_flow.dart';
import '../support/heritagebot_fixtures.dart';

const FakeAuthAccount kContributor = FakeAuthAccount(
  uid: 'case057-contributor-uid',
  email: 'case057.contributor@heritagebot.test',
  password: 'Case057Pass!',
  displayName: 'James Contributor',
);

final CommunitySubmission kPending = storyFixture(
  id: 'case057-pending',
  title: 'Lanterns at the Monument',
  status: CommunitySubmissionStatus.pending,
  site: bundledSite('cebu_heritage_monument'),
  contributorId: kContributor.uid,
  contributorName: 'James Contributor',
);
const String kPath = 'community_submissions/case057-pending';

const String kNewTitle = 'Paper Lanterns at the Heritage of Cebu Monument';
const String kNewStory =
    'Each December our neighbourhood hung paper lanterns around the monument. '
    'My father explained every scene carved on it, from the arrival of '
    'Magellan to the Battle of Mactan, while we waited for the parol contest.';

late HeritageBotTestBackend backend;

void main() {
  setUpAll(() async {
    backend = await HeritageBotTestBackend.install(accounts: [kContributor]);
  });

  setUp(() async {
    await backend.reset();
    seedContributor(backend, kContributor);
    seedStory(backend, kPending);
  });

  testWidgets('CASE-057 - Edit pending submission', (
    WidgetTester tester,
  ) async {
    usePhoneSurface(tester);
    final before = Map<String, dynamic>.of(backend.firestore.documents[kPath]!);

    await signInBeforeLaunch(kContributor);
    await openContributorDashboard(tester);

    // STEP: tap "Edit" on the pending card -> EditCommunityStoryScreen.
    await tapCardAction(tester, title: kPending.title, action: 'Edit');
    await pumpUntilFound(tester, find.byType(app.EditCommunityStoryScreen));

    // STEP: change title + story, tap "Save Changes".
    final fields = fieldsOf(app.EditCommunityStoryScreen);
    expect(fields, findsNWidgets(2), reason: 'Story Title + Heritage Story');
    await tester.enterText(fields.at(0), kNewTitle);
    await tester.enterText(fields.at(1), kNewStory);
    await tester.pump();
    final save = find.text('Save Changes');
    await scrollUntilBuilt(tester, save, screen: app.EditCommunityStoryScreen);
    await tapVisible(tester, save);
    await pumpUntilFound(
      tester,
      snackBarWithText('Pending submission updated.'),
    );
    await pumpUntilGone(tester, find.byType(app.EditCommunityStoryScreen));
    await pumpFor(tester, const Duration(milliseconds: 500));

    // ---- Observations ---------------------------------------------------
    final after = backend.firestore.documents[kPath];
    final cards = await collectDashboardCards(tester);

    final observed = <String, Object?>{
      'editSaved':
          after != null &&
          after['status'] == CommunitySubmissionStatus.pending &&
          (after['updatedAtMillis'] as int) >
              (before['updatedAtMillis'] as int) &&
          storedSubmissions(backend).length == 1,
      'storyChangesPersisted':
          after != null &&
          after['title'] == kNewTitle &&
          after['story'] == kNewStory &&
          // Unchanged fields are preserved.
          after['contributorId'] == kContributor.uid &&
          after['heritagePlaceId'] == kPending.heritagePlaceId &&
          after['createdAtMillis'] == before['createdAtMillis'] &&
          cards.containsKey(kNewTitle) &&
          !cards.containsKey(kPending.title),
    };
    printOnFailure(
      'CASE-057 observed: $observed\nbefore=$before\nafter=$after\n'
      'cards=${cards.values.toList()}',
    );

    // ---- Expected result (unchanged from the original CASE-057) ---------
    expect(
      observed['editSaved'],
      equals(true),
      reason: 'CASE-057: editSaved does not match the real system result',
    );
    expect(
      observed['storyChangesPersisted'],
      equals(true),
      reason:
          'CASE-057: storyChangesPersisted does not match the real system result',
    );

    await unmountApp(tester);
  });
}
