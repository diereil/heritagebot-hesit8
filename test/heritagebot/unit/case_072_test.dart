// HERITAGEBOT - TEST CASE 072
// Proponent: James Stephen O. Ramos
// Module: Administrator Dashboard
// Unit: View Analytics
// Description: Open analytics panel
// Expected: Display available analytics
//
// TEST TYPE: Flutter widget test (host VM, no device / live Firebase).
//
// REAL CODE UNDER TEST (lib/, unmodified)
//   AuthGate -> AdminShell -> "Summary" tab = AdminAnalyticsScreen (the
//   app's analytics panel; its AppBar reads "System Summary") ->
//   AdminAnalyticsService.loadSnapshot(): usage_events (site_view,
//   dynamic_search, navigation_start), users/*/bookmarks (collection
//   group), ai_narratives, users, heritage_sites, community_submissions.
//
// CONTROLLED DATA (isolated in-memory Firestore, written in the exact shape
// UsageAnalyticsService / BookmarkService / AiNarrativeService write it):
//   4 site_view events (3 x Magellan's Cross, 1 x Fort San Pedro),
//   2 dynamic_search, 1 navigation_start, 3 bookmarks (2 x Casa Gorordo
//   Museum, 1 x Magellan's Cross), 2 generated AI narratives,
//   2 tourists + 1 contributor (+ the administrator), one submission updated
//   2 days ago and one 90 days ago.
//
// The expected figures are computed independently from those records.
//
// MOCKED: Firebase platform layer only.

import 'package:flutter_test/flutter_test.dart';

import 'package:heritagebot/main.dart' as app;
import 'package:heritagebot/models/community_submission.dart';
import 'package:heritagebot/models/user_profile.dart';

import '../support/admin_flow.dart';

late HeritageBotTestBackend backend;

const List<String> kSections = [
  'User Distribution',
  'Heritage Site Status',
  'Submission Status',
  'Most Viewed Heritage Sites',
  'Most Bookmarked Heritage Sites',
];
const List<String> kActivityMetrics = [
  'Generated AI Narratives',
  'Heritage Site Views',
  'Dynamic Heritage Searches',
  'Navigation Starts',
  'Community Activity (30 Days)',
];

void main() {
  setUpAll(() async {
    backend = await HeritageBotTestBackend.install(accounts: [kAdminAccount]);
  });

  setUp(() async {
    await backend.reset();
    final magellan = kMagellansCross;
    final fort = bundledSite('fort_san_pedro');
    final casa = bundledSite('casa_gorordo');
    seedRegisteredSites(backend, [magellan, fort, casa]);

    seedUser(backend, const SeedUser(uid: 'case072-t1', fullName: 'Tina Ramos', email: 'tina.ramos@heritagebot.test', role: UserRoles.tourist));
    seedUser(backend, const SeedUser(uid: 'case072-t2', fullName: 'Uriel Sy', email: 'uriel.sy@heritagebot.test', role: UserRoles.tourist));
    seedUser(backend, const SeedUser(uid: 'case072-c1', fullName: 'Vina Tan', email: 'vina.tan@heritagebot.test', role: UserRoles.communityContributor));

    var n = 0;
    for (final site in [magellan, magellan, magellan, fort]) {
      seedUsageEvent(backend, id: 'ev${n++}', eventType: 'site_view', site: site);
    }
    seedUsageEvent(backend, id: 'ev${n++}', eventType: 'dynamic_search');
    seedUsageEvent(backend, id: 'ev${n++}', eventType: 'dynamic_search');
    seedUsageEvent(backend, id: 'ev${n++}', eventType: 'navigation_start', site: fort);

    seedBookmark(backend, userUid: 'case072-t1', site: casa);
    seedBookmark(backend, userUid: 'case072-t2', site: casa);
    seedBookmark(backend, userUid: 'case072-t2', site: magellan);

    seedNarrative(backend, id: 'nar1', site: magellan);
    seedNarrative(backend, id: 'nar2', site: fort);

    final now = DateTime.now().millisecondsSinceEpoch;
    const day = 86400000;
    seedStory(backend, storyFixture(id: 'recent', title: 'Recent Story', status: CommunitySubmissionStatus.pending, site: casa, createdAtMillis: now - 2 * day, updatedAtMillis: now - 2 * day));
    seedStory(backend, storyFixture(id: 'old', title: 'Old Story', status: CommunitySubmissionStatus.approved, site: casa, createdAtMillis: now - 90 * day, updatedAtMillis: now - 90 * day));
  });

  testWidgets('CASE-072 - Open analytics panel', (WidgetTester tester) async {
    usePhoneSurface(tester);

    // STEP: administrator opens HeritageBot -> Summary / analytics panel.
    await openAdminShell(tester);
    await tapNavDestination(tester, 'Summary');
    await waitForAdminSummary(tester);
    final view = await readAdminSummary(tester);

    // ---- Expected figures, computed from the stored records ---------------
    final docs = backend.firestore.documents;
    final events = docs.entries
        .where((e) => e.key.startsWith('usage_events/'))
        .map((e) => e.value)
        .toList();
    int eventCount(String type) =>
        events.where((e) => e['eventType'] == type).length;
    final views = <String, int>{};
    for (final e in events.where((e) => e['eventType'] == 'site_view')) {
      views[e['siteName'] as String] = (views[e['siteName']] ?? 0) + 1;
    }
    final bookmarks = <String, int>{};
    for (final e in docs.entries.where((e) => e.key.contains('/bookmarks/'))) {
      final name = e.value['siteName'] as String;
      bookmarks[name] = (bookmarks[name] ?? 0) + 1;
    }
    final users = storedUsers(backend).values;
    int role(String r) => users.where((u) => u['role'] == r).length;
    final cutoff = DateTime.now()
        .subtract(const Duration(days: 30))
        .millisecondsSinceEpoch;
    final recentActivity = storedSubmissions(backend).values
        .where((s) => (s['updatedAtMillis'] as int) >= cutoff)
        .length;

    final expectedMetrics = <String, String>{
      'Generated AI Narratives':
          '${docs.keys.where((k) => k.startsWith('ai_narratives/')).length}',
      'Heritage Site Views': '${eventCount('site_view')}',
      'Dynamic Heritage Searches': '${eventCount('dynamic_search')}',
      'Navigation Starts': '${eventCount('navigation_start')}',
      'Community Activity (30 Days)': '$recentActivity',
    };
    final shownMetrics = <String, String?>{
      for (final label in expectedMetrics.keys) label: view.metricValue(label),
    };
    String plural(int n, String one, String many) => '$n ${n == 1 ? one : many}';
    final expectedViewed = (views.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value)))
        .map((e) => [e.key, plural(e.value, 'view', 'views')])
        .toList();
    final expectedBookmarked = (bookmarks.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value)))
        .map((e) => [e.key, plural(e.value, 'bookmark', 'bookmarks')])
        .toList();
    final shownViewed = view
        .ranking('Most Viewed Heritage Sites')
        .map((r) => [r[1], r[2]])
        .toList();
    final shownBookmarked = view
        .ranking('Most Bookmarked Heritage Sites')
        .map((r) => [r[1], r[2]])
        .toList();
    final distribution = view.breakdown('User Distribution');

    final observed = <String, Object?>{
      // The analytics panel shows its analytics sections and activity
      // metrics.
      'analyticsVisible':
          adminSummaryScreen.evaluate().isNotEmpty &&
          kSections.every(view.sections.containsKey) &&
          kActivityMetrics.every(view.metrics.containsKey),
      // ...and every figure equals what the stored records contain.
      'analyticsFromRecords':
          expectedMetrics.entries.every((e) => shownMetrics[e.key] == e.value) &&
          '$shownViewed' == '$expectedViewed' &&
          '$shownBookmarked' == '$expectedBookmarked' &&
          distribution['Tourists'] == role(UserRoles.tourist) &&
          distribution['Community Contributors'] ==
              role(UserRoles.communityContributor) &&
          distribution['Administrators'] == role(UserRoles.admin) &&
          // sanity: the controlled data really is what the test seeded
          eventCount('site_view') == 4 &&
          recentActivity == 1,
    };
    printOnFailure(
      'CASE-072 observed: $observed\nexpectedMetrics=$expectedMetrics '
      'shownMetrics=$shownMetrics\nexpectedViewed=$expectedViewed '
      'shownViewed=$shownViewed\nexpectedBookmarked=$expectedBookmarked '
      'shownBookmarked=$shownBookmarked\ndistribution=$distribution\n'
      'view=$view',
    );
    expect(find.byType(app.AdminShell), findsOneWidget);

    // ---- Expected result (unchanged from the original CASE-072) ----------
    expect(
      observed['analyticsVisible'],
      equals(true),
      reason: 'CASE-072: analyticsVisible does not match the real system result',
    );
    expect(
      observed['analyticsFromRecords'],
      equals(true),
      reason: 'CASE-072: analyticsFromRecords does not match the real system result',
    );

    await unmountApp(tester);
  });
}
