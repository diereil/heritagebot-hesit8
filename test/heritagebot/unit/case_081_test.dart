// HERITAGEBOT - TEST CASE 081
// Proponent: James Stephen O. Ramos
// Module: Admin User Management
// Unit: View User Details
// Description: Open selected account
// Expected: Display account details
//
// TEST TYPE: Flutter widget test (host VM, no device / live Firebase).
//
// REAL CODE UNDER TEST (lib/, unmodified)
//   AuthGate -> AdminShell -> Settings -> "Manage Users" (AdminUsersScreen)
//   -> tap an account card -> AdminUserDetailScreen (Email Address, User
//   Role, Preferred Language, Account Created, Account Status).
//
// CONTROLLED DATA: the selected account "Mila Bautista" (community
// contributor, preferred language "tl", registered 2026-03-15, active) and
// two other accounts. Every displayed detail is compared with the selected
// users/{uid} record.
//
// MOCKED: Firebase platform layer only.

import 'package:flutter_test/flutter_test.dart';

import 'package:heritagebot/main.dart' as app;
import 'package:heritagebot/models/user_profile.dart';

import '../support/admin_flow.dart';

final SeedUser kSelected = SeedUser(
  uid: 'case081-c1',
  fullName: 'Mila Bautista',
  email: 'mila.bautista@heritagebot.test',
  role: UserRoles.communityContributor,
  preferredLanguage: 'tl',
  createdAtMillis: DateTime(2026, 3, 15, 10, 30).millisecondsSinceEpoch,
);
const List<SeedUser> kOthers = [
  SeedUser(uid: 'case081-t1', fullName: 'Lito Abad', email: 'lito.abad@heritagebot.test', role: UserRoles.tourist),
  SeedUser(uid: 'case081-t2', fullName: 'Olivia Dela Cruz', email: 'olivia.delacruz@heritagebot.test', role: UserRoles.tourist, accountStatus: 'suspended'),
];

late HeritageBotTestBackend backend;

void main() {
  setUpAll(() async {
    backend = await HeritageBotTestBackend.install(accounts: [kAdminAccount]);
  });

  setUp(() async {
    await backend.reset();
    seedUser(backend, kSelected);
    for (final user in kOthers) {
      seedUser(backend, user);
    }
  });

  testWidgets('CASE-081 - Open selected account', (WidgetTester tester) async {
    usePhoneSurface(tester);
    await openAdminShell(tester);
    await openManageUsers(tester);

    // STEP: tap the selected account in the list.
    await openUserCard(tester, kSelected.email);
    final rows = userDetailRows(tester);

    // Ground truth: the selected users/{uid} record.
    final doc = storedUsers(backend)['users/${kSelected.uid}']!;
    final created = DateTime.fromMillisecondsSinceEpoch(
      doc['createdAtMillis'] as int,
    );
    final createdText =
        '${created.year}-${created.month.toString().padLeft(2, '0')}-'
        '${created.day.toString().padLeft(2, '0')}';

    final observed = <String, Object?>{
      'userDetailsVisible':
          find.byType(app.AdminUserDetailScreen).evaluate().isNotEmpty &&
          textsUnder(tester, find.byType(app.AdminUserDetailScreen))
              .contains('User Details') &&
          const [
            'Email Address',
            'User Role',
            'Preferred Language',
            'Account Created',
            'Account Status',
          ].every(rows.containsKey),
      'correctUserLoaded':
          rows['title'] == doc['fullName'] &&
          rows['Email Address'] == doc['email'] &&
          rows['User Role'] == UserRoles.label(doc['role'] as String) &&
          rows['Preferred Language'] == doc['preferredLanguage'] &&
          rows['Account Created'] == createdText &&
          createdText == '2026-03-15' &&
          rows['Account Status'] ==
              (doc['accountStatus'] as String).toUpperCase(),
    };
    printOnFailure(
      'CASE-081 observed: $observed\nrows=$rows\nstored=$doc',
    );

    // ---- Expected result (unchanged from the original CASE-081) ----------
    expect(
      observed['userDetailsVisible'],
      equals(true),
      reason: 'CASE-081: userDetailsVisible does not match the real system result',
    );
    expect(
      observed['correctUserLoaded'],
      equals(true),
      reason: 'CASE-081: correctUserLoaded does not match the real system result',
    );

    await unmountApp(tester);
  });
}
