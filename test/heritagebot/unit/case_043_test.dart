// HERITAGEBOT - TEST CASE 043
// Proponent: Reil Esdrelon
// Module: Community Stories
// Unit: View Community Stories
// Description: Open community stories page.
// Expected: List approved community stories (only approved ones).
//
// TEST TYPE: Flutter widget test (host VM, no device / live Firebase).
//
// REAL CODE UNDER TEST (lib/, unmodified)
//   MainShell "Stories" tab -> CommunityStoriesScreen ->
//   CommunitySubmissionService.getApprovedSubmissions
//   (Firestore where status == 'approved').
//
// FIXTURE (fixtureId = CASE-043): community_submissions contains two
// approved stories, one pending story and one rejected story (documents in
// the exact shape CommunitySubmissionService writes).
//
// MOCKED: Firebase platform layer only (in-memory Firestore).

import 'package:flutter_test/flutter_test.dart';

import 'package:heritagebot/main.dart' as app;
import 'package:heritagebot/models/community_submission.dart';

import '../support/heritagebot_fixtures.dart';

const FakeAuthAccount kTourist = FakeAuthAccount(
  uid: 'case043-tourist-uid',
  email: 'case043.tourist@heritagebot.test',
  password: 'Case043Pass!',
  displayName: 'Case 043 Tourist',
);

late HeritageBotTestBackend backend;
late List<CommunitySubmission> approved;
late List<CommunitySubmission> notApproved;

void main() {
  setUpAll(() async {
    backend = await HeritageBotTestBackend.install(accounts: [kTourist]);
  });

  setUp(() async {
    await backend.reset();
    backend.seedTourist(kTourist);
    approved = [
      storyFixture(
          id: 'story-a1',
          title: 'Sunday Visits to Casa Gorordo',
          status: CommunitySubmissionStatus.approved,
          site: bundledSite('casa_gorordo')),
      storyFixture(
          id: 'story-a2',
          title: 'Fiesta Memories at Fort San Pedro',
          status: CommunitySubmissionStatus.approved,
          site: bundledSite('fort_san_pedro')),
    ];
    notApproved = [
      storyFixture(
          id: 'story-p1',
          title: 'Pending Story Awaiting Review',
          status: CommunitySubmissionStatus.pending,
          site: bundledSite('cebu_heritage_monument')),
      storyFixture(
          id: 'story-r1',
          title: 'Rejected Story Not For Publishing',
          status: CommunitySubmissionStatus.rejected,
          site: bundledSite('fort_san_pedro')),
    ];
    for (final story in [...approved, ...notApproved]) {
      seedStory(backend, story);
    }
  });

  testWidgets('CASE-043 - Open community stories page: approved community '
      'stories are listed', (WidgetTester tester) async {
    usePhoneSurface(tester);

    await signInBeforeLaunch(kTourist);
    await launchAuthGate(tester, until: app.MainShell);
    await openStoriesTab(tester);

    // ---- Observations ---------------------------------------------------
    final listed = listedStoryTitles(tester);
    final approvedTitles = approved.map((s) => s.title).toSet();
    final hiddenTitles = notApproved.map((s) => s.title).toSet();

    final observed = <String, Object?>{
      'storiesLoaded': approvedTitles.every(listed.contains),
      'approvedOnly':
          listed.isNotEmpty && listed.every(approvedTitles.contains) &&
              !listed.any(hiddenTitles.contains),
    };
    printOnFailure('CASE-043 observed: $observed\nlisted=$listed');

    // ---- Expected result (unchanged from the original CASE-043) ---------
    expect(observed['storiesLoaded'], equals(true),
        reason: 'CASE-043: storiesLoaded does not match the real system result');
    expect(observed['approvedOnly'], equals(true),
        reason: 'CASE-043: approvedOnly does not match the real system result');

    await unmountApp(tester);
  });
}
