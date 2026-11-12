// HERITAGEBOT - TEST CASE 050
// Proponent: James Stephen O. Ramos
// Module: Community Contributor Management
// Unit: Submit Heritage Story
// Description: Submit empty story body.
// Expected: Show required-field error (and do not save the story).
//
// TEST TYPE: Flutter widget test (host VM, no device / live Firebase).
//
// REAL CODE UNDER TEST (lib/, unmodified)
//   ContributorDashboardScreen -> "Submit Story" ->
//   SubmitCommunityStoryScreen._submit (story-body validation) ->
//   CommunitySubmissionService (must NOT be reached).
//
// FIXTURE (storyBody = ''): valid title, empty story body.
//
// MOCKED: Firebase platform layer only (in-memory Firestore).

import 'package:flutter_test/flutter_test.dart';

import 'package:heritagebot/main.dart' as app;

import '../support/heritagebot_fixtures.dart';
import '../support/story_submission_flow.dart';

const FakeAuthAccount kContributor = FakeAuthAccount(
  uid: 'case050-contributor-uid',
  email: 'case050.contributor@heritagebot.test',
  password: 'Case050Pass!',
  displayName: 'James Contributor',
);

const String kTitle = 'The Bell Ringers of Casa Gorordo';
const String kStory = '';

/// The story-body field is labelled "Heritage Story"; an error about it may
/// refer to the story, its content or its length.
final RegExp kBodyMessage =
    RegExp(r'story|content|body|characters', caseSensitive: false);

late HeritageBotTestBackend backend;

void main() {
  setUpAll(() async {
    backend = await HeritageBotTestBackend.install(accounts: [kContributor]);
  });

  setUp(() async {
    await backend.reset();
    seedContributor(backend, kContributor);
  });

  testWidgets('CASE-050 - Submit empty story body: required-field error is '
      'shown', (WidgetTester tester) async {
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
      'bodyRequiredVisible': stillOnForm &&
          messages.any((m) =>
              kBodyMessage.hasMatch(m) &&
              !RegExp('title', caseSensitive: false).hasMatch(m)),
    };
    printOnFailure('CASE-050 observed: $observed\nmessages=$messages');

    // ---- Expected result (unchanged from the original CASE-050) ---------
    expect(observed['submissionCreated'], equals(false),
        reason: 'CASE-050: submissionCreated does not match the real system result');
    expect(observed['bodyRequiredVisible'], equals(true),
        reason: 'CASE-050: bodyRequiredVisible does not match the real system result');

    await unmountApp(tester);
  });
}
