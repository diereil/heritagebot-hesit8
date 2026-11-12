// HERITAGEBOT - TEST CASE 095
// Proponent: Shawn Guillmar C. Morales
// Module: Community Contribution Review
// Unit: View Submitted Story
// Description: Open pending story
// Expected: Show story content
//
// TEST TYPE: Flutter widget test (host VM, no device / live Firebase).
//
// REAL CODE UNDER TEST (lib/, unmodified)
//   AuthGate -> AdminShell -> "Review" (AdminDashboardScreen) -> tap the
//   pending story card (_openSubmission) -> AdminReviewSubmissionScreen
//   (SectionTitle title/place, "Contributor", "Submission Timestamp", full
//   story text, "Current Status").
//
// FIXTURE (fixtureId = CASE-095): two PENDING stories from different
// contributors; the administrator opens "Candles at the Cross".
//
// MOCKED: Firebase platform layer only (in-memory Firestore).

import 'package:flutter_test/flutter_test.dart';

import 'package:heritagebot/main.dart' as app;
import 'package:heritagebot/models/community_submission.dart';

import '../support/admin_operations_flow.dart';

const String kOpened = 'Candles at the Cross';
const String kOther = 'My Lola and the Fort Walls';
const String kStory =
    'Every Friday my grandmother lit candles at the kiosk of the cross and '
    'told us how her own mother had done the same before the war. The '
    'candle vendors outside still know our family by name.';

late HeritageBotTestBackend backend;

void main() {
  setUpAll(() async {
    backend = await HeritageBotTestBackend.install(accounts: [kAdminAccount]);
  });

  setUp(() async {
    await backend.reset();
    seedRegisteredSites(backend, [kMagellansCross, bundledSite('fort_san_pedro')]);
    seedStory(backend, storyFixture(id: 'case095-open', title: kOpened, status: CommunitySubmissionStatus.pending, site: kMagellansCross, contributorName: 'Maria Santos', story: kStory));
    seedStory(backend, storyFixture(id: 'case095-other', title: kOther, status: CommunitySubmissionStatus.pending, site: bundledSite('fort_san_pedro'), contributorId: 'fixture-contributor-2', contributorName: 'Jose Ramos'));
  });

  testWidgets('CASE-095 - Open pending story', (WidgetTester tester) async {
    usePhoneSurface(tester);

    await openAdminShell(tester);
    await openReviewTab(tester);
    await openReviewCard(tester, kOpened);

    // ---- Observations -----------------------------------------------------
    final detail = tester.widget<app.AdminReviewSubmissionScreen>(reviewDetailScreen);
    final texts = textsUnder(tester, reviewDetailScreen);
    final heading = tester
        .widgetList<app.SectionTitle>(
          find.descendant(of: reviewDetailScreen, matching: find.byType(app.SectionTitle)),
        )
        .first;
    final contributorCard = infoCardsTitled(tester, 'Contributor').firstOrNull;
    final statusCard = infoCardsTitled(tester, 'Current Status').firstOrNull;
    final stored = storedSubmissions(backend)['community_submissions/case095-open']!;
    final other = storedSubmissions(backend)['community_submissions/case095-other']!;

    final observed = <String, Object?>{
      'submittedStoryVisible':
          heading.title == kOpened &&
          heading.subtitle == kMagellansCross.name &&
          texts.contains(kStory) &&
          (contributorCard?.body.contains('Maria Santos') ?? false) &&
          statusCard?.body ==
              CommunitySubmissionStatus.label(CommunitySubmissionStatus.pending) &&
          infoCardsTitled(tester, 'Submission Timestamp').isNotEmpty,
      'correctStoryLoaded':
          detail.submission.id == 'case095-open' &&
          detail.submission.story == stored['story'] &&
          !texts.contains(other['story']) &&
          !texts.contains(kOther),
    };
    printOnFailure(
      'CASE-095 observed: $observed\nheading=${heading.title}/${heading.subtitle}\n'
      'contributor=${contributorCard?.body} status=${statusCard?.body}\ntexts=$texts',
    );
    // ignore: avoid_print
    print('CASE-095 evidence: observed=$observed openedId=${detail.submission.id}');

    // ---- Expected result (unchanged from the original CASE-095) ----------
    expect(
      observed['submittedStoryVisible'],
      equals(true),
      reason: 'CASE-095: submittedStoryVisible does not match the real system result',
    );
    expect(
      observed['correctStoryLoaded'],
      equals(true),
      reason: 'CASE-095: correctStoryLoaded does not match the real system result',
    );

    await unmountApp(tester);
  });
}
