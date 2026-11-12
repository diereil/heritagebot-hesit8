// HERITAGEBOT - TEST CASE 080
// Proponent: James Stephen O. Ramos
// Module: Admin User Management
// Unit: Search Users
// Description: Search unknown account
// Expected: Show no-results message
//
// TEST TYPE: Flutter widget test (host VM, no device / live Firebase).
//
// REAL CODE UNDER TEST (lib/, unmodified)
//   AuthGate -> AdminShell -> Settings -> "Manage Users" (AdminUsersScreen)
//   -> "Search Users" -> _filteredUsers -> "No Users Found" InfoCard when
//   nothing matches.
//
// INPUT (userQuery): "nonexistent.user@example.test" - no stored account
// has this name, e-mail or role.
// CONTROLLED DATA: 3 registered accounts + the administrator profile.
//
// MOCKED: Firebase platform layer only.

import 'package:flutter_test/flutter_test.dart';

import 'package:heritagebot/models/user_profile.dart';

import '../support/admin_flow.dart';

const String kUserQuery = 'nonexistent.user@example.test';
const List<SeedUser> kUsers = [
  SeedUser(uid: 'case080-t1', fullName: 'Lito Abad', email: 'lito.abad@heritagebot.test', role: UserRoles.tourist),
  SeedUser(uid: 'case080-c1', fullName: 'Mila Bautista', email: 'mila.bautista@heritagebot.test', role: UserRoles.communityContributor),
  SeedUser(uid: 'case080-c2', fullName: 'Ramon Garcia', email: 'ramon.garcia@heritagebot.test', role: UserRoles.communityContributor),
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
  });

  testWidgets('CASE-080 - Search unknown account', (WidgetTester tester) async {
    usePhoneSurface(tester);
    await openAdminShell(tester);
    await openManageUsers(tester);
    final before = await listedUsers(tester);

    // STEP: search for an account that does not exist.
    await searchUsers(tester, kUserQuery);
    final results = await listedUsers(tester);
    final noResults = infoCardsTitled(tester, 'No Users Found');
    final storedMatch = storedUsers(backend).values.any(
      (d) => (d['email'] as String).toLowerCase() == kUserQuery,
    );

    final observed = <String, Object?>{
      'searchMatched': results.isNotEmpty,
      'noResultsVisible':
          before.length == kUsers.length + 1 &&
          !storedMatch &&
          noResults.length == 1 &&
          noResults.single.body ==
              'No registered account matches the current search and filters.',
    };
    printOnFailure(
      'CASE-080 observed: $observed\nbefore=$before\nresults=$results '
      'noResultsCard=${noResults.map((c) => '${c.title}: ${c.body}')}',
    );

    // ---- Expected result (unchanged from the original CASE-080) ----------
    expect(
      observed['searchMatched'],
      equals(false),
      reason: 'CASE-080: searchMatched does not match the real system result',
    );
    expect(
      observed['noResultsVisible'],
      equals(true),
      reason: 'CASE-080: noResultsVisible does not match the real system result',
    );

    await unmountApp(tester);
  });
}
