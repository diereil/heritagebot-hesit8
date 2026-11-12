// HERITAGEBOT - TEST CASE 077
// Proponent: James Stephen O. Ramos
// Module: Administrator Dashboard
// Unit: View Submission Status Summary
// Description: Open submission status summary
// Expected: Display pending approved rejected counts
//
// TEST TYPE: Flutter widget test (host VM, no device / live Firebase).
//
// REAL CODE UNDER TEST (lib/, unmodified)
//   AuthGate -> AdminShell -> "Summary" (AdminAnalyticsScreen) ->
//   AdminAnalyticsService.loadSnapshot ->
//   CommunitySubmissionService.getAllSubmissions -> "Submission Status"
//   section and the "Community Submissions" metric card.
//   Cross-check: the "Review" tab (AdminDashboardScreen) status chips.
//
// CONTROLLED DATA (isolated in-memory Firestore)
//   community_submissions: 3 pending, 2 approved, 4 rejected (9 total),
//   in the exact shape CommunitySubmissionService writes.
//
// MOCKED: Firebase platform layer only.

import 'package:flutter_test/flutter_test.dart';

import 'package:heritagebot/main.dart' as app;
import 'package:heritagebot/models/community_submission.dart';

import '../support/admin_flow.dart';

late HeritageBotTestBackend backend;

void main() {
  setUpAll(() async {
    backend = await HeritageBotTestBackend.install(accounts: [kAdminAccount]);
  });

  setUp(() async {
    await backend.reset();
    final site = bundledSite('fort_san_pedro');
    seedRegisteredSites(backend, [site]);
    var n = 0;
    for (final status in [
      CommunitySubmissionStatus.pending,
      CommunitySubmissionStatus.pending,
      CommunitySubmissionStatus.pending,
      CommunitySubmissionStatus.approved,
      CommunitySubmissionStatus.approved,
      CommunitySubmissionStatus.rejected,
      CommunitySubmissionStatus.rejected,
      CommunitySubmissionStatus.rejected,
      CommunitySubmissionStatus.rejected,
    ]) {
      seedStory(
        backend,
        storyFixture(id: 'case077-$n', title: 'Story $n', status: status, site: site),
      );
      n++;
    }
  });

  testWidgets('CASE-077 - Open submission status summary', (
    WidgetTester tester,
  ) async {
    usePhoneSurface(tester);

    // STEP: administrator opens the dashboard summary.
    await openAdminShell(tester);
    final view = await readAdminSummary(tester);
    final status = view.breakdown('Submission Status');

    // Cross-check on the Review tab (AdminDashboardScreen chips).
    await tapNavDestination(tester, 'Review');
    await pumpUntilFound(
      tester,
      find.descendant(
        of: find.byType(app.AdminDashboardScreen),
        matching: find.textContaining('Pending: '),
      ),
    );
    final reviewChips = textsUnder(tester, find.byType(app.AdminDashboardScreen))
        .where((t) => RegExp(r'^(Total|Pending|Approved|Rejected): \d+$').hasMatch(t))
        .toList();

    // ---- Ground truth: community_submissions records ----------------------
    final stored = storedSubmissions(backend).values.toList();
    int count(String s) => stored.where((d) => d['status'] == s).length;
    final pending = count(CommunitySubmissionStatus.pending);
    final approved = count(CommunitySubmissionStatus.approved);
    final rejected = count(CommunitySubmissionStatus.rejected);

    final observed = <String, Object?>{
      'statusCountsAccurate':
          pending == 3 &&
          approved == 2 &&
          rejected == 4 &&
          status['Pending'] == pending &&
          status['Approved'] == approved &&
          status['Rejected'] == rejected &&
          view.metricValue('Community Submissions') == '${stored.length}' &&
          view.metricSubtitle('Community Submissions') ==
              '$pending pending • $approved approved • $rejected rejected' &&
          reviewChips.contains('Pending: $pending') &&
          reviewChips.contains('Approved: $approved') &&
          reviewChips.contains('Rejected: $rejected'),
      'threeStatusesShown':
          view.sections.containsKey('Submission Status') &&
          status.keys.toSet().containsAll({'Pending', 'Approved', 'Rejected'}),
    };
    printOnFailure(
      'CASE-077 observed: $observed\nstored pending=$pending '
      'approved=$approved rejected=$rejected\nsection=$status '
      'metric=${view.metrics['Community Submissions']}\n'
      'reviewChips=$reviewChips',
    );

    // ---- Expected result (unchanged from the original CASE-077) ----------
    expect(
      observed['statusCountsAccurate'],
      equals(true),
      reason: 'CASE-077: statusCountsAccurate does not match the real system result',
    );
    expect(
      observed['threeStatusesShown'],
      equals(true),
      reason: 'CASE-077: threeStatusesShown does not match the real system result',
    );

    await unmountApp(tester);
  });
}
