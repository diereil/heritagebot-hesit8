// HERITAGEBOT - TEST CASE 045
// Proponent: Reil Esdrelon
// Module: Community Stories
// Unit: View Approved Local Stories
// Description: Filter by heritage site.
// Expected: Show approved stories for selected site.
//
// TEST TYPE: Flutter widget test (host VM, no device / live Firebase).
//
// REAL CODE UNDER TEST (lib/, unmodified)
//   CommunityStoriesScreen: getApprovedSubmissions + the "Search Stories"
//   field (_filtered), which matches the heritage place name (as well as
//   title, contributor and story text). CommunityStoriesScreen has no
//   separate site dropdown; the search field is how a tourist narrows the
//   list to one heritage site.
//
// FIXTURE (siteFixture = magellans_cross)
//   * 2 approved stories for Magellan's Cross (CASE-022 site record),
//   * 1 approved story for Fort San Pedro,
//   * 1 PENDING story for Magellan's Cross.
// The tourist types the site name "Magellan's Cross" into the field.
//
// MOCKED: Firebase platform layer only (in-memory Firestore).

import 'package:flutter_test/flutter_test.dart';

import 'package:heritagebot/main.dart' as app;
import 'package:heritagebot/models/community_submission.dart';
import 'package:heritagebot/services/heritage_site_service.dart';
import 'package:heritagebot/models/heritage_place.dart';

import '../support/heritagebot_fixtures.dart';

const FakeAuthAccount kTourist = FakeAuthAccount(
  uid: 'case045-tourist-uid',
  email: 'case045.tourist@heritagebot.test',
  password: 'Case045Pass!',
  displayName: 'Case 045 Tourist',
);

late HeritageBotTestBackend backend;
late List<CommunitySubmission> stories;

void main() {
  setUpAll(() async {
    backend = await HeritageBotTestBackend.install(accounts: [kTourist]);
  });

  setUp(() async {
    await backend.reset();
    backend.seedTourist(kTourist);
    seedRegisteredSites(backend, [...defaultHeritagePlaces, kMagellansCross]);
    stories = [
      storyFixture(
          id: 'story-m1',
          title: 'Candle Vendors by the Cross',
          status: CommunitySubmissionStatus.approved,
          site: kMagellansCross),
      storyFixture(
          id: 'story-m2',
          title: 'My First Sinulog Morning',
          status: CommunitySubmissionStatus.approved,
          site: kMagellansCross),
      storyFixture(
          id: 'story-f1',
          title: 'Fiesta Memories at Fort San Pedro',
          status: CommunitySubmissionStatus.approved,
          site: bundledSite('fort_san_pedro')),
      storyFixture(
          id: 'story-mp',
          title: 'Unreviewed Chapel Memory',
          status: CommunitySubmissionStatus.pending,
          site: kMagellansCross),
    ];
    for (final story in stories) {
      seedStory(backend, story);
    }
  });

  testWidgets('CASE-045 - Filter by heritage site: approved stories for the '
      'selected site are shown', (WidgetTester tester) async {
    usePhoneSurface(tester);

    await HeritageSiteService().initializeRuntimeSites();
    await signInBeforeLaunch(kTourist);
    await launchAuthGate(tester, until: app.MainShell);
    await openStoriesTab(tester);
    final listedBefore = listedStoryTitles(tester);

    // STEP: narrow the list to the heritage site.
    await tester.enterText(
        fieldsOf(app.CommunityStoriesScreen).first, kMagellansCross.name);
    await tester.pump();
    await pumpFor(tester, const Duration(milliseconds: 300));

    // ---- Observations ---------------------------------------------------
    final listedAfter = listedStoryTitles(tester);
    final expectedTitles = stories
        .where((s) =>
            s.heritagePlaceId == kMagellansCross.id &&
            s.status == CommunitySubmissionStatus.approved)
        .map((s) => s.title)
        .toSet();
    final otherTitles =
        stories.map((s) => s.title).toSet().difference(expectedTitles);

    final observed = <String, Object?>{
      'siteFilterApplied': listedBefore.length > listedAfter.length &&
          listedAfter.isNotEmpty,
      'onlyMatchingApprovedStories':
          listedAfter.toSet().containsAll(expectedTitles) &&
              !listedAfter.any(otherTitles.contains),
    };
    printOnFailure('CASE-045 observed: $observed\n'
        'before=$listedBefore\nafter=$listedAfter\nexpected=$expectedTitles');

    // ---- Expected result (unchanged from the original CASE-045) ---------
    expect(observed['siteFilterApplied'], equals(true),
        reason: 'CASE-045: siteFilterApplied does not match the real system result');
    expect(observed['onlyMatchingApprovedStories'], equals(true),
        reason: 'CASE-045: onlyMatchingApprovedStories does not match the real system result');

    await unmountApp(tester);
  });
}
