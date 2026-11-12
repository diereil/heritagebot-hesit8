// HERITAGEBOT - TEST CASE 079
// Proponent: James Stephen O. Ramos
// Module: Admin User Management
// Unit: Search Users
// Description: Search existing account
// Expected: Show matching account
//
// TEST TYPE: Flutter widget test (host VM, no device / live Firebase).
//
// REAL CODE UNDER TEST (lib/, unmodified)
//   AuthGate -> AdminShell -> Settings -> "Manage Users" (AdminUsersScreen)
//   -> "Search Users" field -> _filteredUsers (name / e-mail / role label)
//   -> account cards.
//
// INPUT: the e-mail of an existing account, "mila.bautista@heritagebot.test".
// CONTROLLED DATA: 4 registered accounts + the administrator profile.
//
// MOCKED: Firebase platform layer only.

import 'package:flutter_test/flutter_test.dart';

import 'package:heritagebot/models/user_profile.dart';

import '../support/admin_flow.dart';

const SeedUser kTarget = SeedUser(
  uid: 'case079-c1',
  fullName: 'Mila Bautista',
  email: 'mila.bautista@heritagebot.test',
  role: UserRoles.communityContributor,
);
const List<SeedUser> kUsers = [
  SeedUser(uid: 'case079-t1', fullName: 'Lito Abad', email: 'lito.abad@heritagebot.test', role: UserRoles.tourist),
  SeedUser(uid: 'case079-t2', fullName: 'Olivia Dela Cruz', email: 'olivia.delacruz@heritagebot.test', role: UserRoles.tourist),
  kTarget,
  SeedUser(uid: 'case079-c2', fullName: 'Ramon Garcia', email: 'ramon.garcia@heritagebot.test', role: UserRoles.communityContributor),
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

  testWidgets('CASE-079 - Search existing account', (WidgetTester tester) async {
    usePhoneSurface(tester);
    await openAdminShell(tester);
    await openManageUsers(tester);
    final before = await listedUsers(tester);

    // STEP: type the account's e-mail into "Search Users".
    await searchUsers(tester, kTarget.email);
    final results = await listedUsers(tester);
    final noResults = infoCardsTitled(tester, 'No Users Found');

    final observed = <String, Object?>{
      'searchMatched': results.isNotEmpty && noResults.isEmpty,
      'correctUserReturned':
          before.length == kUsers.length + 1 &&
          results.length == 1 &&
          results.single.email == kTarget.email &&
          results.single.name == kTarget.fullName &&
          results.single.roleLabel == UserRoles.label(kTarget.role),
    };
    printOnFailure(
      'CASE-079 observed: $observed\nbefore=$before\nresults=$results '
      'noResultsCard=${noResults.length}',
    );

    // ---- Expected result (unchanged from the original CASE-079) ----------
    expect(
      observed['searchMatched'],
      equals(true),
      reason: 'CASE-079: searchMatched does not match the real system result',
    );
    expect(
      observed['correctUserReturned'],
      equals(true),
      reason: 'CASE-079: correctUserReturned does not match the real system result',
    );

    await unmountApp(tester);
  });
}
