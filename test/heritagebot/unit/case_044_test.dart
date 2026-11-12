// HERITAGEBOT - TEST CASE 044
// Proponent: Reil Esdrelon
// Module: Community Stories
// Unit: Read Community Story
// Description: Open approved story.
// Expected: Show full approved story.
//
// TEST TYPE: Flutter widget test (host VM, no device / live Firebase).
//
// REAL CODE UNDER TEST (lib/, unmodified)
//   CommunityStoriesScreen (list preview is limited to 4 lines) -> tap
//   story card -> CommunityStoryDetailScreen.
//
// FIXTURE (storyFixture = approved_story): one approved story whose body is
// long enough that the list card truncates it, so the test can tell the
// full story from the preview.
//
// MOCKED: Firebase platform layer only (in-memory Firestore).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:heritagebot/main.dart' as app;
import 'package:heritagebot/models/community_submission.dart';

import '../support/heritagebot_fixtures.dart';

const FakeAuthAccount kTourist = FakeAuthAccount(
  uid: 'case044-tourist-uid',
  email: 'case044.tourist@heritagebot.test',
  password: 'Case044Pass!',
  displayName: 'Case 044 Tourist',
);

const String kFullStory =
    'Every December my lola walked us to Casa Gorordo to see the old '
    'belen she remembered from her childhood. She pointed at the narrow '
    'stairs, the capiz windows and the wooden floor and told us how the '
    'Gorordo family lived when Cebu was still a small colonial town.\n\n'
    'She also told us that the house survived the war while many houses '
    'around it burned. Inside, she always stopped at the kitchen and said '
    'that cooking there was a whole-day affair for the household.\n\n'
    'Today I bring my own children there, and I tell them her stories so '
    'that the house stays alive for our family as well.';

late HeritageBotTestBackend backend;
late CommunitySubmission story;

void main() {
  setUpAll(() async {
    backend = await HeritageBotTestBackend.install(accounts: [kTourist]);
  });

  setUp(() async {
    await backend.reset();
    backend.seedTourist(kTourist);
    story = storyFixture(
      id: 'story-approved-044',
      title: "Lola's Christmas at Casa Gorordo",
      status: CommunitySubmissionStatus.approved,
      site: bundledSite('casa_gorordo'),
      contributorName: 'Ana Villamor',
      story: kFullStory,
    );
    seedStory(backend, story);
  });

  testWidgets('CASE-044 - Open approved story: the full approved story is '
      'shown', (WidgetTester tester) async {
    usePhoneSurface(tester);

    await signInBeforeLaunch(kTourist);
    await launchAuthGate(tester, until: app.MainShell);
    await openStoriesTab(tester);

    // Precondition: the list shows only a truncated preview.
    final preview = tester.widget<Text>(find.text(kFullStory));
    expect(preview.maxLines, 4);

    await tapVisible(tester, find.text(story.title));
    await pumpUntilFound(tester, find.byType(app.CommunityStoryDetailScreen));
    await pumpFor(tester, const Duration(milliseconds: 400));

    // ---- Observations ---------------------------------------------------
    final detail = find.byType(app.CommunityStoryDetailScreen);
    final bodyTexts = tester
        .widgetList<Text>(find.descendant(
            of: detail, matching: find.text(kFullStory)))
        .toList();
    final fullStoryVisible = bodyTexts.length == 1 &&
        bodyTexts.single.maxLines == null &&
        bodyTexts.single.overflow != TextOverflow.ellipsis &&
        find
            .descendant(of: detail, matching: find.text(story.title))
            .evaluate()
            .isNotEmpty;
    final badgeShown = find
        .descendant(of: detail, matching: find.text('Approved Community Story'))
        .evaluate()
        .isNotEmpty;
    final stored =
        backend.firestore.documents['community_submissions/${story.id}'];

    final observed = <String, Object?>{
      'fullStoryVisible': fullStoryVisible,
      'storyApproved':
          badgeShown && stored?['status'] == CommunitySubmissionStatus.approved,
    };
    printOnFailure('CASE-044 observed: $observed, badgeShown=$badgeShown, '
        'storedStatus=${stored?['status']}');

    // ---- Expected result (unchanged from the original CASE-044) ---------
    expect(observed['fullStoryVisible'], equals(true),
        reason: 'CASE-044: fullStoryVisible does not match the real system result');
    expect(observed['storyApproved'], equals(true),
        reason: 'CASE-044: storyApproved does not match the real system result');

    await unmountApp(tester);
  });
}
