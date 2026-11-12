// HERITAGEBOT - TEST CASE 075
// Proponent: James Stephen O. Ramos
// Module: Administrator Dashboard
// Unit: View Total Users
// Description: Open user count metric
// Expected: Display count from user records
//
// TEST TYPE: Flutter widget test (host VM, no device / live Firebase).
//
// REAL CODE UNDER TEST (lib/, unmodified)
//   AuthGate -> AdminShell -> "Summary" (AdminAnalyticsScreen) ->
//   AdminAnalyticsService.loadSnapshot -> UserService.getAllUsers
//   (Firestore users collection) -> "Total Users" metric card
//   (AdminAnalyticsSnapshot.totalUsers / activeUsers / suspendedUsers) and
//   the "User Distribution" section.
//
// CONTROLLED DATA (isolated in-memory Firestore)
//   users: 4 tourists (1 suspended) + 3 community contributors, plus the
//   administrator profile UserService writes on login = 8 user records.
//   A bookmark sub-document (users/{uid}/bookmarks/{site}) is also stored to
//   show that only user records - not their sub-collections - are counted.
//
// MOCKED: Firebase platform layer only.

import 'package:flutter_test/flutter_test.dart';

import 'package:heritagebot/models/user_profile.dart';

import '../support/admin_flow.dart';

const List<SeedUser> kUsers = [
  SeedUser(uid: 'case075-t1', fullName: 'Lito Abad', email: 'lito.abad@heritagebot.test', role: UserRoles.tourist),
  SeedUser(uid: 'case075-t2', fullName: 'Mila Bautista', email: 'mila.bautista@heritagebot.test', role: UserRoles.tourist),
  SeedUser(uid: 'case075-t3', fullName: 'Nestor Cabrera', email: 'nestor.cabrera@heritagebot.test', role: UserRoles.tourist),
  SeedUser(uid: 'case075-t4', fullName: 'Olivia Dela Cruz', email: 'olivia.delacruz@heritagebot.test', role: UserRoles.tourist, accountStatus: 'suspended'),
  SeedUser(uid: 'case075-c1', fullName: 'Paolo Enriquez', email: 'paolo.enriquez@heritagebot.test', role: UserRoles.communityContributor),
  SeedUser(uid: 'case075-c2', fullName: 'Queenie Flores', email: 'queenie.flores@heritagebot.test', role: UserRoles.communityContributor),
  SeedUser(uid: 'case075-c3', fullName: 'Ramon Garcia', email: 'ramon.garcia@heritagebot.test', role: UserRoles.communityContributor),
];

late HeritageBotTestBackend backend;

void main() {
  setUpAll(() async {
    backend = await HeritageBotTestBackend.install(accounts: [kAdminAccount]);
  });

  setUp(() async {
    await backend.reset();
    for (final user in kUsers) {
      seedUser(backend, user);
    }
    seedBookmark(backend, userUid: 'case075-t1', site: kMagellansCross);
  });

  testWidgets('CASE-075 - Open user count metric', (WidgetTester tester) async {
    usePhoneSurface(tester);

    // STEP: administrator opens the dashboard summary.
    await openAdminShell(tester);
    final view = await readAdminSummary(tester);

    // ---- Ground truth: the user records in Firestore ----------------------
    final users = storedUsers(backend).values.toList();
    final active = users.where((u) => u['accountStatus'] == 'active').length;
    final suspended =
        users.where((u) => u['accountStatus'] == 'suspended').length;
    int role(String r) => users.where((u) => u['role'] == r).length;
    final distribution = view.breakdown('User Distribution');

    final observed = <String, Object?>{
      'userCountAccurate':
          users.length == kUsers.length + 1 &&
          view.metricValue('Total Users') == '${users.length}' &&
          view.metricSubtitle('Total Users') ==
              '$active active • $suspended suspended' &&
          distribution['Tourists'] == role(UserRoles.tourist) &&
          distribution['Community Contributors'] ==
              role(UserRoles.communityContributor) &&
          distribution['Administrators'] == role(UserRoles.admin),
      'userMetricVisible':
          adminSummaryScreen.evaluate().isNotEmpty &&
          view.metrics.containsKey('Total Users'),
    };
    printOnFailure(
      'CASE-075 observed: $observed\nstoredUsers=${users.length} '
      'active=$active suspended=$suspended\n'
      'metric=${view.metrics['Total Users']} distribution=$distribution',
    );

    // ---- Expected result (unchanged from the original CASE-075) ----------
    expect(
      observed['userCountAccurate'],
      equals(true),
      reason: 'CASE-075: userCountAccurate does not match the real system result',
    );
    expect(
      observed['userMetricVisible'],
      equals(true),
      reason: 'CASE-075: userMetricVisible does not match the real system result',
    );

    await unmountApp(tester);
  });
}
