// HERITAGEBOT - TEST CASE 046
// Proponent: Reil Esdrelon
// Module: Community Stories
// Unit: View Approved Local Stories
// Description: No approved stories available.
// Expected: Show empty-state message.
//
// TEST TYPE: Flutter widget test (host VM, no device / live Firebase).
//
// REAL CODE UNDER TEST (lib/, unmodified)
//   MainShell "Stories" tab -> CommunityStoriesScreen ->
//   CommunitySubmissionService.getApprovedSubmissions -> empty-state card.
//
// FIXTURE (fixtureId = CASE-046): community_submissions holds only a
// pending and a rejected story - nothing approved.
//
// MOCKED: Firebase platform layer only (in-memory Firestore).

import 'package:flutter_test/flutter_test.dart';

import 'package:heritagebot/main.dart' as app;
import 'package:heritagebot/models/community_submission.dart';

import '../support/heritagebot_fixtures.dart';

const FakeAuthAccount kTourist = FakeAuthAccount(
  uid: 'case046-tourist-uid',
  email: 'case046.tourist@heritagebot.test',
  password: 'Case046Pass!',
  displayName: 'Case 046 Tourist',
);

late HeritageBotTestBackend backend;

void main() {
  setUpAll(() async {
    backend = await HeritageBotTestBackend.install(accounts: [kTourist]);
  });

  setUp(() async {
    await backend.reset();
    backend.seedTourist(kTourist);
    seedStory(
        backend,
        storyFixture(
            id: 'story-p1',
            title: 'Pending Story Awaiting Review',
            status: CommunitySubmissionStatus.pending,
            site: bundledSite('casa_gorordo')));
    seedStory(
        backend,
        storyFixture(
            id: 'story-r1',
            title: 'Rejected Story Not For Publishing',
            status: CommunitySubmissionStatus.rejected,
            site: bundledSite('fort_san_pedro')));
  });

  testWidgets('CASE-046 - No approved stories available: empty-state message '
      'is shown', (WidgetTester tester) async {
    usePhoneSurface(tester);

    await signInBeforeLaunch(kTourist);
    await launchAuthGate(tester, until: app.MainShell);
    await openStoriesTab(tester);

    // ---- Observations ---------------------------------------------------
    final listed = listedStoryTitles(tester);
    final emptyCards = infoCardsTitled(tester, 'No Approved Stories Yet');

    final observed = <String, Object?>{
      'approvedStoryCount': listed.length,
      'emptyStateVisible': emptyCards.length == 1 &&
          emptyCards.single.body.contains('after Administrator review'),
    };
    printOnFailure('CASE-046 observed: $observed\nlisted=$listed');

    // ---- Expected result (unchanged from the original CASE-046) ---------
    expect(observed['approvedStoryCount'], equals(0),
        reason: 'CASE-046: approvedStoryCount does not match the real system result');
    expect(observed['emptyStateVisible'], equals(true),
        reason: 'CASE-046: emptyStateVisible does not match the real system result');

    await unmountApp(tester);
  });
}
