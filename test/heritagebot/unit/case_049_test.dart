// HERITAGEBOT - TEST CASE 049
// Proponent: James Stephen O. Ramos
// Module: Community Contributor Management
// Unit: Submit Heritage Story
// Description: Submit empty title.
// Expected: Show required-field error (and do not save the story).
//
// TEST TYPE: Flutter widget test (host VM, no device / live Firebase).
//
// REAL CODE UNDER TEST (lib/, unmodified)
//   ContributorDashboardScreen -> "Submit Story" ->
//   SubmitCommunityStoryScreen._submit (title validation) ->
//   CommunitySubmissionService (must NOT be reached).
//
// FIXTURE (storyTitle = ''): empty title, otherwise valid story text.
//
// MOCKED: Firebase platform layer only (in-memory Firestore).

import 'package:flutter_test/flutter_test.dart';

import 'package:heritagebot/main.dart' as app;

import '../support/heritagebot_fixtures.dart';
import '../support/story_submission_flow.dart';

const FakeAuthAccount kContributor = FakeAuthAccount(
  uid: 'case049-contributor-uid',
  email: 'case049.contributor@heritagebot.test',
  password: 'Case049Pass!',
  displayName: 'James Contributor',
);

const String kTitle = '';
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

  testWidgets('CASE-049 - Submit empty title: required-field error is shown',
      (WidgetTester tester) async {
    usePhoneSurface(tester);

    await signInBeforeLaunch(kContributor);
    await openSubmitStoryScreen(tester);
    await fillAndSubmitStory(tester, title: kTitle, story: kStory);

    // ---- Observations ---------------------------------------------------
    final messages = snackBarTexts(tester);
    final stillOnForm =
        find.byType(app.SubmitCommunityStoryScreen).evaluate().isNotEmpty;

    final observed = <String, Object?>{
      'submissionCreated': storedSubmissions(backend).isNotEmpty,
      'titleRequiredVisible': stillOnForm &&
          messages.any((m) => RegExp('title', caseSensitive: false).hasMatch(m)),
    };
    printOnFailure('CASE-049 observed: $observed\nmessages=$messages');

    // ---- Expected result (unchanged from the original CASE-049) ---------
    expect(observed['submissionCreated'], equals(false),
        reason: 'CASE-049: submissionCreated does not match the real system result');
    expect(observed['titleRequiredVisible'], equals(true),
        reason: 'CASE-049: titleRequiredVisible does not match the real system result');

    await unmountApp(tester);
  });
}
