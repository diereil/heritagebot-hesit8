// HERITAGEBOT - TEST CASE 048
// Proponent: James Stephen O. Ramos
// Module: Community Contributor Management
// Unit: Submit Heritage Story
// Description: Submit complete valid story.
// Expected: Save story as pending review.
//
// TEST TYPE: Flutter widget test (host VM, no device / live Firebase).
//
// REAL CODE UNDER TEST (lib/, unmodified)
//   AuthGate (role = community_contributor) -> MainShell "Contribute" ->
//   ContributorDashboardScreen -> "Submit Story" ->
//   SubmitCommunityStoryScreen._submit -> CommunitySubmissionService
//   .submitStory -> Firestore community_submissions/{id} -> dashboard
//   (getMySubmissions).
//
// FIXTURE (storyFixture = valid_story): heritage place = default selection
// (first official site), title and story that meet the form's rules
// (title >= 5 characters, story >= 80 characters); no media attached.
//
// MOCKED: Firebase platform layer only (in-memory Firestore).

import 'package:flutter_test/flutter_test.dart';

import 'package:heritagebot/main.dart' as app;
import 'package:heritagebot/models/community_submission.dart';
import 'package:heritagebot/models/heritage_place.dart';

import '../support/heritagebot_fixtures.dart';
import '../support/story_submission_flow.dart';

const FakeAuthAccount kContributor = FakeAuthAccount(
  uid: 'case048-contributor-uid',
  email: 'case048.contributor@heritagebot.test',
  password: 'Case048Pass!',
  displayName: 'James Contributor',
);

const String kTitle = 'The Bell Ringers of Casa Gorordo';
const String kStory =
    'When I was a child, my grandfather worked near Casa Gorordo and told '
    'us how families in Parian gathered in the house during fiestas. He '
    'described the capiz windows, the long dining table and the stories '
    'shared by the elders, which taught us why the house matters to Cebu.';

late HeritageBotTestBackend backend;

void main() {
  setUpAll(() async {
    backend = await HeritageBotTestBackend.install(accounts: [kContributor]);
  });

  setUp(() async {
    await backend.reset();
    seedContributor(backend, kContributor);
  });

  testWidgets('CASE-048 - Submit complete valid story: story is saved as '
      'pending review', (WidgetTester tester) async {
    usePhoneSurface(tester);
    expect(kTitle.length, greaterThanOrEqualTo(5));
    expect(kStory.length, greaterThanOrEqualTo(80));
    final expectedPlace = officialHeritagePlaces.first;

    await signInBeforeLaunch(kContributor);
    await openSubmitStoryScreen(tester);
    expect(storedSubmissions(backend), isEmpty);

    await fillAndSubmitStory(tester, title: kTitle, story: kStory);
    await pumpUntilFound(tester,
        snackBarWithText('Heritage story submitted for administrator review.'));
    await pumpUntilGone(tester, find.byType(app.SubmitCommunityStoryScreen));
    await pumpFor(tester, const Duration(milliseconds: 500));

    // ---- Observations ---------------------------------------------------
    final stored = storedSubmissions(backend);
    final doc = stored.length == 1 ? stored.values.single : null;
    final dashboardShowsStory = find
        .descendant(
            of: find.byType(app.ContributorDashboardScreen),
            matching: find.text(kTitle))
        .evaluate()
        .isNotEmpty;

    final observed = <String, Object?>{
      'submissionCreated': doc != null &&
          doc['title'] == kTitle &&
          doc['story'] == kStory &&
          doc['contributorId'] == kContributor.uid &&
          doc['heritagePlaceId'] == expectedPlace.id,
      'reviewStatus': doc?['status'],
    };
    printOnFailure('CASE-048 observed: $observed\n'
        'storedSubmissions=$stored\ndashboardShowsStory=$dashboardShowsStory');

    // ---- Expected result (unchanged from the original CASE-048) ---------
    expect(observed['submissionCreated'], equals(true),
        reason: 'CASE-048: submissionCreated does not match the real system result');
    expect(observed['reviewStatus'], equals(CommunitySubmissionStatus.pending),
        reason: 'CASE-048: reviewStatus does not match the real system result');
    // Supporting evidence: the contributor's dashboard lists the new story.
    expect(dashboardShowsStory, isTrue);

    await unmountApp(tester);
  });
}
