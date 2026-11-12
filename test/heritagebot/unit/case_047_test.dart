// HERITAGEBOT - TEST CASE 047
// Proponent: Reil Esdrelon
// Module: Community Stories
// Unit: View Community Stories
// Description: Attempt to view pending story publicly.
// Expected: Hide unapproved submission.
//
// TEST TYPE: Flutter widget test (host VM, no device / live Firebase).
//
// REAL CODE UNDER TEST (lib/, unmodified)
//   MainShell "Stories" tab -> CommunityStoriesScreen
//   (getApprovedSubmissions + "Search Stories" field).
//
// FIXTURE (storyFixture = pending_story): a PENDING story plus one approved
// story (so the page is not simply empty). The tourist browses the public
// list and then searches for the pending story by its exact title.
//
// MOCKED: Firebase platform layer only (in-memory Firestore).

import 'package:flutter_test/flutter_test.dart';

import 'package:heritagebot/main.dart' as app;
import 'package:heritagebot/models/community_submission.dart';

import '../support/heritagebot_fixtures.dart';

const FakeAuthAccount kTourist = FakeAuthAccount(
  uid: 'case047-tourist-uid',
  email: 'case047.tourist@heritagebot.test',
  password: 'Case047Pass!',
  displayName: 'Case 047 Tourist',
);

late HeritageBotTestBackend backend;
late CommunitySubmission pending;
late CommunitySubmission approved;

void main() {
  setUpAll(() async {
    backend = await HeritageBotTestBackend.install(accounts: [kTourist]);
  });

  setUp(() async {
    await backend.reset();
    backend.seedTourist(kTourist);
    pending = storyFixture(
        id: 'story-pending-047',
        title: 'Secret Tunnel Under the Fort',
        status: CommunitySubmissionStatus.pending,
        site: bundledSite('fort_san_pedro'));
    approved = storyFixture(
        id: 'story-approved-047',
        title: 'Fiesta Memories at Fort San Pedro',
        status: CommunitySubmissionStatus.approved,
        site: bundledSite('fort_san_pedro'));
    seedStory(backend, pending);
    seedStory(backend, approved);
  });

  testWidgets('CASE-047 - Attempt to view pending story publicly: the '
      'unapproved submission is hidden', (WidgetTester tester) async {
    usePhoneSurface(tester);

    await signInBeforeLaunch(kTourist);
    await launchAuthGate(tester, until: app.MainShell);
    await openStoriesTab(tester);
    final listedBrowse = listedStoryTitles(tester);

    // Attempt: search for the pending story by its exact title.
    await tester.enterText(
        fieldsOf(app.CommunityStoriesScreen).first, pending.title);
    await tester.pump();
    await pumpFor(tester, const Duration(milliseconds: 300));
    final listedSearch = listedStoryTitles(tester);
    final pendingTextAnywhere = anyTextMatches(
        tester,
        find.byType(app.CommunityStoriesScreen),
        RegExp(RegExp.escape(pending.story)));

    // ---- Observations ---------------------------------------------------
    final observed = <String, Object?>{
      'pendingStoryPubliclyVisible': listedBrowse.contains(pending.title) ||
          listedSearch.contains(pending.title) ||
          pendingTextAnywhere,
      'approvedOnly': listedBrowse.isNotEmpty &&
          listedBrowse.every((t) => t == approved.title),
    };
    printOnFailure('CASE-047 observed: $observed\n'
        'browse=$listedBrowse search("${pending.title}")=$listedSearch');

    // ---- Expected result (unchanged from the original CASE-047) ---------
    expect(observed['pendingStoryPubliclyVisible'], equals(false),
        reason: 'CASE-047: pendingStoryPubliclyVisible does not match the real system result');
    expect(observed['approvedOnly'], equals(true),
        reason: 'CASE-047: approvedOnly does not match the real system result');

    await unmountApp(tester);
  });
}
