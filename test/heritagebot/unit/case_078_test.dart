// HERITAGEBOT - TEST CASE 078
// Proponent: James Stephen O. Ramos
// Module: Admin User Management
// Unit: Manage Users
// Description: Open user management
// Expected: Display account list
//
// TEST TYPE: Flutter widget test (host VM, no device / live Firebase).
//
// REAL CODE UNDER TEST (lib/, unmodified)
//   AuthGate -> AdminShell -> "Settings" tab (AdminSystemSettingsScreen) ->
//   "Manage Users" -> AdminUsersScreen -> UserService.getAllUsers ->
//   one account card per users/{uid} record (name, e-mail, role label,
//   account status).
//
// CONTROLLED DATA (isolated in-memory Firestore)
//   4 registered accounts (2 tourists - one suspended - and 2 community
//   contributors) plus the administrator profile UserService writes.
//
// MOCKED: Firebase platform layer only.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:heritagebot/main.dart' as app;
import 'package:heritagebot/models/user_profile.dart';

import '../support/admin_flow.dart';

const List<SeedUser> kUsers = [
  SeedUser(uid: 'case078-t1', fullName: 'Lito Abad', email: 'lito.abad@heritagebot.test', role: UserRoles.tourist),
  SeedUser(uid: 'case078-t2', fullName: 'Olivia Dela Cruz', email: 'olivia.delacruz@heritagebot.test', role: UserRoles.tourist, accountStatus: 'suspended'),
  SeedUser(uid: 'case078-c1', fullName: 'Mila Bautista', email: 'mila.bautista@heritagebot.test', role: UserRoles.communityContributor),
  SeedUser(uid: 'case078-c2', fullName: 'Ramon Garcia', email: 'ramon.garcia@heritagebot.test', role: UserRoles.communityContributor),
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

  testWidgets('CASE-078 - Open user management', (WidgetTester tester) async {
    usePhoneSurface(tester);

    // STEP: administrator -> Settings -> Manage Users.
    await openAdminShell(tester);
    await openManageUsers(tester);

    final listed = await listedUsers(tester);
    final screenTexts = textsUnder(tester, adminUsersScreen);
    final appBar = textsUnder(
      tester,
      find.descendant(of: adminUsersScreen, matching: find.byType(AppBar)),
    );

    // ---- Ground truth: users records --------------------------------------
    final stored = storedUsers(backend).values.toList();
    final listedByEmail = {for (final u in listed) u.email: u};
    final everyRecordListedCorrectly = stored.every((doc) {
      final card = listedByEmail[doc['email']];
      return card != null &&
          card.name == doc['fullName'] &&
          card.roleLabel == UserRoles.label(doc['role'] as String) &&
          card.statusLabel == (doc['accountStatus'] as String).toUpperCase();
    });

    final observed = <String, Object?>{
      'userListVisible':
          stored.length == kUsers.length + 1 &&
          listed.length == stored.length &&
          everyRecordListedCorrectly &&
          screenTexts.contains('Total Users: ${stored.length}'),
      'managementScreenVisible':
          find.byType(app.AdminUsersScreen).evaluate().isNotEmpty &&
          appBar.contains('Manage Users') &&
          screenTexts.contains('Admin User Management') &&
          screenTexts.contains('Search Users'),
    };
    printOnFailure(
      'CASE-078 observed: $observed\nlisted=$listed\n'
      'stored=${stored.map((d) => '${d['email']}/${d['role']}/${d['accountStatus']}')}\n'
      'appBar=$appBar screenTexts=$screenTexts',
    );

    // ---- Expected result (unchanged from the original CASE-078) ----------
    expect(
      observed['userListVisible'],
      equals(true),
      reason: 'CASE-078: userListVisible does not match the real system result',
    );
    expect(
      observed['managementScreenVisible'],
      equals(true),
      reason: 'CASE-078: managementScreenVisible does not match the real system result',
    );

    await unmountApp(tester);
  });
}
