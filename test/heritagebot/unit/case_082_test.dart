// HERITAGEBOT - TEST CASE 082
// Proponent: James Stephen O. Ramos
// Module: Admin User Management
// Unit: View Account Status
// Description: Inspect selected account
// Expected: Show accurate account status
//
// TEST TYPE: Flutter widget test (host VM, no device / live Firebase).
//
// REAL CODE UNDER TEST (lib/, unmodified)
//   AuthGate -> AdminShell -> Settings -> "Manage Users" (AdminUsersScreen)
//   -> account card (status shown in the list) -> AdminUserDetailScreen
//   "Account Status" row and the status action it offers
//   (Suspend Account / Reactivate Account).
//
// CONTROLLED DATA: one SUSPENDED tourist ("Olivia Dela Cruz") and one
// ACTIVE contributor ("Mila Bautista"). Both are inspected so the status
// shown must follow the stored record, not a default.
//
// MOCKED: Firebase platform layer only.

import 'package:flutter_test/flutter_test.dart';

import 'package:heritagebot/models/user_profile.dart';

import '../support/admin_flow.dart';

const SeedUser kSuspended = SeedUser(
  uid: 'case082-t1',
  fullName: 'Olivia Dela Cruz',
  email: 'olivia.delacruz@heritagebot.test',
  role: UserRoles.tourist,
  accountStatus: 'suspended',
);
const SeedUser kActive = SeedUser(
  uid: 'case082-c1',
  fullName: 'Mila Bautista',
  email: 'mila.bautista@heritagebot.test',
  role: UserRoles.communityContributor,
);

late HeritageBotTestBackend backend;

void main() {
  setUpAll(() async {
    backend = await HeritageBotTestBackend.install(accounts: [kAdminAccount]);
  });

  setUp(() async {
    await backend.reset();
    seedUser(backend, kSuspended);
    seedUser(backend, kActive);
  });

  testWidgets('CASE-082 - Inspect selected account', (WidgetTester tester) async {
    usePhoneSurface(tester);
    await openAdminShell(tester);
    await openManageUsers(tester);
    final listed = {for (final u in await listedUsers(tester)) u.email: u};

    // STEP: inspect the suspended account, go back, inspect the active one.
    final inspected = <String, Map<String, Object?>>{};
    for (final user in [kSuspended, kActive]) {
      await openUserCard(tester, user.email);
      inspected[user.email] = {
        'rows': userDetailRows(tester),
        'buttons': userDetailButtons(tester),
      };
      await backFromUserDetail(tester);
    }

    bool statusMatches(SeedUser user, String action) {
      final stored = storedUsers(backend)['users/${user.uid}']!;
      final expected = (stored['accountStatus'] as String).toUpperCase();
      final rows = inspected[user.email]!['rows'] as Map<String, String>;
      final buttons = inspected[user.email]!['buttons'] as List<String>;
      return rows['Account Status'] == expected &&
          listed[user.email]?.statusLabel == expected &&
          buttons.contains(action);
    }

    final observed = <String, Object?>{
      'accountStatusVisible': inspected.values.every(
        (i) => (i['rows'] as Map<String, String>).containsKey('Account Status'),
      ),
      'accountStatusAccurate':
          statusMatches(kSuspended, 'Reactivate Account') &&
          statusMatches(kActive, 'Suspend Account'),
    };
    printOnFailure(
      'CASE-082 observed: $observed\nlisted=$listed\ninspected=$inspected\n'
      'stored=${storedUsers(backend)}',
    );

    // ---- Expected result (unchanged from the original CASE-082) ----------
    expect(
      observed['accountStatusVisible'],
      equals(true),
      reason: 'CASE-082: accountStatusVisible does not match the real system result',
    );
    expect(
      observed['accountStatusAccurate'],
      equals(true),
      reason: 'CASE-082: accountStatusAccurate does not match the real system result',
    );

    await unmountApp(tester);
  });
}
