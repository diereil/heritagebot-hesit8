// HERITAGEBOT - TEST CASE 083
// Proponent: James Stephen O. Ramos
// Module: Admin User Management
// Unit: Manage Users
// Description: Try user management without admin role
// Expected: Deny unauthorized access
//
// TEST TYPE: Flutter widget test (host VM, no device / live Firebase).
//
// REAL CODE UNDER TEST (lib/, unmodified)
//   AuthGate -> UserService.getUserProfile -> role "tourist" ->
//   MainShell(userRole: tourist) instead of AdminShell. HeritageBot has no
//   named routes / deep links: the ONLY way into user management is
//   AdminShell -> Settings -> "Manage Users", which AuthGate shows only for
//   the administrator role.
//
// INPUT (actorRole): tourist - a verified, signed-in tourist account whose
// users/{uid} record has role "tourist" (e-mail not in
// UserService.adminEmails).
//
// WHAT IS OBSERVED
//   * which shell the real AuthGate opens for the tourist,
//   * whether any admin screen (AdminShell, AdminUsersScreen,
//     AdminUserDetailScreen) is built, and
//   * whether any reachable tourist tab (Home, Stories, My Journal,
//     Profile - every entry scrolled into view) offers a user-management
//     entry.
//   Firestore security rules are server side and are not part of this
//   widget test.
//
// MOCKED: Firebase platform layer only.

import 'package:flutter_test/flutter_test.dart';

import 'package:heritagebot/main.dart' as app;
import 'package:heritagebot/models/user_profile.dart';
import 'package:heritagebot/services/user_service.dart';

import '../support/admin_flow.dart';

const FakeAuthAccount kTourist = FakeAuthAccount(
  uid: 'case083-tourist-uid',
  email: 'case083.tourist@heritagebot.test',
  password: 'Case083Pass!',
  displayName: 'Tess Tourist',
);

/// Text of any entry that would lead into user management.
final RegExp kUserManagementEntry = RegExp(
  r'manage users|user management|admin user|search users|suspend account',
  caseSensitive: false,
);

late HeritageBotTestBackend backend;

void main() {
  setUpAll(() async {
    backend = await HeritageBotTestBackend.install(
      accounts: [kTourist, kAdminAccount],
    );
  });

  setUp(() async {
    await backend.reset();
    backend.seedTourist(kTourist);
    // Other accounts exist that an administrator could manage.
    seedUser(backend, const SeedUser(uid: 'case083-other', fullName: 'Mila Bautista', email: 'mila.bautista@heritagebot.test', role: UserRoles.communityContributor));
  });

  testWidgets('CASE-083 - Try user management without admin role', (
    WidgetTester tester,
  ) async {
    usePhoneSurface(tester);

    // STEP: the tourist opens HeritageBot (real AuthGate).
    await signInBeforeLaunch(kTourist);
    await launchAuthGate(tester, until: app.MainShell);
    await pumpFor(tester, const Duration(milliseconds: 400));

    // STEP: look through every tab the tourist can reach.
    final tabs = <String, Type>{
      en('home'): app.HomeScreen,
      'Stories': app.CommunityStoriesScreen,
      en('myJournal'): app.MyJournalScreen,
      en('profile'): app.ProfileScreen,
    };
    final entriesFound = <String, List<String>>{};
    final scannedTexts = <String, int>{};
    for (final tab in tabs.entries) {
      await tapNavDestination(tester, tab.key);
      await pumpFor(tester, const Duration(milliseconds: 500));
      final texts = await allTextsOfScreen(tester, find.byType(tab.value));
      scannedTexts[tab.key] = texts.length;
      final hits = texts.where(kUserManagementEntry.hasMatch).toList();
      if (hits.isNotEmpty) entriesFound[tab.key] = hits;
    }

    // ---- Observations -----------------------------------------------------
    bool built(Type t) =>
        find.byType(t, skipOffstage: false).evaluate().isNotEmpty;
    final shell = tester.widget<app.MainShell>(find.byType(app.MainShell));
    final adminScreensBuilt = <String, bool>{
      'AdminShell': built(app.AdminShell),
      'AdminUsersScreen': built(app.AdminUsersScreen),
      'AdminUserDetailScreen': built(app.AdminUserDetailScreen),
    };
    final storedRole =
        storedUsers(backend)['users/${kTourist.uid}']?['role'] as String?;

    final observed = <String, Object?>{
      'userManagementAllowed':
          adminScreensBuilt.values.any((b) => b) || entriesFound.isNotEmpty,
      'authorizationDenied':
          storedRole == UserRoles.tourist &&
          !UserService().isAuthorizedAdminEmail(kTourist.email) &&
          shell.userRole == UserRoles.tourist &&
          adminScreensBuilt.values.every((b) => !b) &&
          entriesFound.isEmpty &&
          // every tab really was rendered and scanned
          scannedTexts.length == tabs.length &&
          scannedTexts.values.every((n) => n > 0),
    };
    printOnFailure(
      'CASE-083 observed: $observed\nshell.userRole=${shell.userRole} '
      'storedRole=$storedRole adminScreensBuilt=$adminScreensBuilt\n'
      'userManagementEntriesFound=$entriesFound scannedTexts=$scannedTexts',
    );
    // ignore: avoid_print
    print('CASE-083 evidence: tourist tabs scanned (texts per tab) = $scannedTexts');

    // ---- Expected result (unchanged from the original CASE-083) ----------
    expect(
      observed['userManagementAllowed'],
      equals(false),
      reason: 'CASE-083: userManagementAllowed does not match the real system result',
    );
    expect(
      observed['authorizationDenied'],
      equals(true),
      reason: 'CASE-083: authorizationDenied does not match the real system result',
    );

    await unmountApp(tester);
  });
}
