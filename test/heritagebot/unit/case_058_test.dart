// HERITAGEBOT - TEST CASE 058
// Proponent: James Stephen O. Ramos
// Module: Community Contributor Management
// Unit: Edit Submission
// Description: Edit another contributor submission.
// Expected: Block unauthorized edit.
//
// TEST TYPE: Flutter widget test (host VM, no device / live Firebase).
//
// REAL CODE UNDER TEST (lib/, unmodified)
//   1. ContributorDashboardScreen (getMySubmissions) - does the other
//      contributor's story appear with an "Edit" button at all?
//   2. EditCommunityStoryScreen opened with the OTHER contributor's
//      submission (as a crafted navigation would) -> _saveChanges ->
//      CommunitySubmissionService.updatePendingSubmission
//      (contributorId != current uid -> permission-denied).
//   3. CommunitySubmissionService.updatePendingSubmission called directly.
//
// FIXTURE (actorFixture = different_contributor): a PENDING story owned by
// contributor A; contributor B (different uid) is signed in and tries to
// change its title and story.
//
// NOTE: in production Firestore security rules would be a second line of
// defence; the in-memory Firestore fake has no rules, so this test measures
// HeritageBot's own app-level authorization check.
//
// MOCKED: Firebase platform layer only (in-memory Firestore).

import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:heritagebot/main.dart' as app;
import 'package:heritagebot/models/community_submission.dart';
import 'package:heritagebot/services/community_submission_service.dart';

import '../support/contributor_flow.dart';
import '../support/heritagebot_fixtures.dart';

const FakeAuthAccount kOwner = FakeAuthAccount(
  uid: 'case058-owner-uid',
  email: 'case058.owner@heritagebot.test',
  password: 'Case058Owner!',
  displayName: 'Maria Santos',
);
const FakeAuthAccount kDifferentContributor = FakeAuthAccount(
  uid: 'case058-different-uid',
  email: 'case058.different@heritagebot.test',
  password: 'Case058Other!',
  displayName: 'James Contributor',
);

final CommunitySubmission kOwnersStory = storyFixture(
  id: 'case058-owners-pending',
  title: "Maria's Story of the Fort Gate",
  status: CommunitySubmissionStatus.pending,
  site: bundledSite('fort_san_pedro'),
  contributorId: kOwner.uid,
  contributorName: 'Maria Santos',
);
const String kPath = 'community_submissions/case058-owners-pending';

const String kTamperedTitle = 'Overwritten by Another Contributor';
const String kTamperedStory =
    'This text was typed by a different contributor who is trying to replace '
    "Maria's pending story with their own words before the administrator "
    'reviews it, which HeritageBot should not allow.';

late HeritageBotTestBackend backend;

void main() {
  setUpAll(() async {
    backend = await HeritageBotTestBackend.install(
      accounts: [kOwner, kDifferentContributor],
    );
  });

  setUp(() async {
    await backend.reset();
    seedContributor(backend, kOwner);
    seedContributor(backend, kDifferentContributor);
    seedStory(backend, kOwnersStory);
  });

  testWidgets('CASE-058 - Edit another contributor submission', (
    WidgetTester tester,
  ) async {
    usePhoneSurface(tester);
    final before = Map<String, dynamic>.of(backend.firestore.documents[kPath]!);

    await signInBeforeLaunch(kDifferentContributor);
    await openContributorDashboard(tester);

    // 1. The other contributor's story is not offered for editing.
    final cards = await collectDashboardCards(tester);
    final offeredForEdit = cards[kOwnersStory.title]?.hasEdit == true;

    // 2. Open the real edit screen with Maria's submission anyway.
    Navigator.of(
      tester.element(find.byType(app.ContributorDashboardScreen)),
    ).push(
      MaterialPageRoute<bool>(
        builder: (_) => app.EditCommunityStoryScreen(submission: kOwnersStory),
      ),
    );
    await pumpUntilFound(tester, find.byType(app.EditCommunityStoryScreen));
    final fields = fieldsOf(app.EditCommunityStoryScreen);
    await tester.enterText(fields.at(0), kTamperedTitle);
    await tester.enterText(fields.at(1), kTamperedStory);
    await tester.pump();
    final save = find.text('Save Changes');
    await scrollUntilBuilt(tester, save, screen: app.EditCommunityStoryScreen);
    await tapVisible(tester, save);
    await pumpFor(tester, const Duration(milliseconds: 800));
    final uiMessages = shownSnackBarTexts(tester);
    final stillOnEditScreen = find
        .byType(app.EditCommunityStoryScreen)
        .evaluate()
        .isNotEmpty;
    final afterUi = Map<String, dynamic>.of(
      backend.firestore.documents[kPath]!,
    );

    // 3. Direct service call as the different contributor.
    Object? serviceError;
    await tester.runAsync(() async {
      try {
        await CommunitySubmissionService().updatePendingSubmission(
          submission: kOwnersStory,
          heritagePlaceId: kOwnersStory.heritagePlaceId,
          heritagePlaceName: kOwnersStory.heritagePlaceName,
          title: kTamperedTitle,
          story: kTamperedStory,
          imageUrls: const [],
          videoUrls: const [],
        );
      } catch (e) {
        serviceError = e;
      }
    });
    final afterService = backend.firestore.documents[kPath];

    // ---- Observations ---------------------------------------------------
    bool unchanged(Map<String, dynamic>? doc) =>
        doc != null &&
        doc['title'] == before['title'] &&
        doc['story'] == before['story'] &&
        doc['updatedAtMillis'] == before['updatedAtMillis'];

    final observed = <String, Object?>{
      'editSaved': !unchanged(afterUi) || !unchanged(afterService),
      'authorizationDenied':
          !offeredForEdit &&
          uiMessages.any(
            (m) => m.contains('You can only edit your own submission.'),
          ) &&
          stillOnEditScreen &&
          serviceError is FirebaseException &&
          (serviceError as FirebaseException).code == 'permission-denied',
    };
    printOnFailure(
      'CASE-058 observed: $observed\n'
      'dashboardCards=${cards.values.toList()} offeredForEdit=$offeredForEdit\n'
      'uiMessages=$uiMessages stillOnEditScreen=$stillOnEditScreen\n'
      'serviceError=$serviceError\nbefore=$before\nafterUi=$afterUi\n'
      'afterService=$afterService',
    );

    // ---- Expected result (unchanged from the original CASE-058) ---------
    expect(
      observed['editSaved'],
      equals(false),
      reason: 'CASE-058: editSaved does not match the real system result',
    );
    expect(
      observed['authorizationDenied'],
      equals(true),
      reason:
          'CASE-058: authorizationDenied does not match the real system result',
    );

    await unmountApp(tester);
  });
}
