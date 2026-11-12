// HERITAGEBOT - TEST CASE 120
// Proponent: AI Knowledge Base / System Team
// Module: System Settings
// Unit: System Security
// Description: Access admin settings as tourist
// Expected: Deny unauthorized access
//
// TEST TYPE: Flutter widget test (host VM, no device / live Firebase).
//
// REAL CODE UNDER TEST (lib/, unmodified)
//   AuthGate -> UserService.getUserProfile -> role "tourist" ->
//   MainShell(userRole: tourist) instead of AdminShell. HeritageBot has no
//   named routes / deep links: the ONLY way into the administrator settings
//   is AdminShell -> "Settings" (AdminSystemSettingsScreen), which AuthGate
//   offers only to the administrator role (same access model as CASE-083).
//
// INPUT (actorRole): tourist - a verified, signed-in tourist account whose
// users/{uid} record has role "tourist" (e-mail not in
// UserService.adminEmails). Administrator settings exist in
// system_settings/general.
//
// WHAT IS OBSERVED
//   * which shell the real AuthGate opens for the tourist,
//   * whether AdminShell / AdminSystemSettingsScreen / AdminUsersScreen /
//     AdminNarrativeMonitorScreen are built,
//   * whether any reachable tourist tab (Home, Stories, My Journal, Profile -
//     every entry scrolled into view) offers an administrator-settings entry,
//   * that system_settings/general is unchanged.
//   Firestore security rules are server side and not part of this test.
//
// MOCKED: Firebase platform layer only.

import 'package:flutter_test/flutter_test.dart';

import 'package:heritagebot/main.dart' as app;
import 'package:heritagebot/models/user_profile.dart';
import 'package:heritagebot/services/user_service.dart';

import '../support/admin_operations_flow.dart';

const FakeAuthAccount kTourist = FakeAuthAccount(
  uid: 'case120-tourist-uid',
  email: 'case120.tourist@heritagebot.test',
  password: 'Case120Pass!',
  displayName: 'Tess Tourist',
);

/// Text of any entry that belongs to the administrator settings.
final RegExp kAdminSettingsEntry = RegExp(
  r'backup database|database backup|backup and system settings|system settings|'
  r'manage users|monitor ai narratives|save settings|required fallback language',
  caseSensitive: false,
);

late HeritageBotTestBackend backend;

void main() {
  setUpAll(() async {
    backend = await HeritageBotTestBackend.install(accounts: [kTourist, kAdminAccount]);
  });

  setUp(() async {
    await backend.reset();
    backend.seedTourist(kTourist);
    seedSystemSettings(backend, enabledLanguageCodes: const ['en', 'fil'], notificationsEnabled: true);
  });

  testWidgets('CASE-120 - Access admin settings as tourist', (WidgetTester tester) async {
    usePhoneSurface(tester);
    final settingsBefore = '${storedSettings(backend)}';

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
      final hits = texts.where(kAdminSettingsEntry.hasMatch).toList();
      if (hits.isNotEmpty) entriesFound[tab.key] = hits;
    }

    // ---- Observations -----------------------------------------------------
    bool built(Type t) => find.byType(t, skipOffstage: false).evaluate().isNotEmpty;
    final shell = tester.widget<app.MainShell>(find.byType(app.MainShell));
    final adminScreensBuilt = <String, bool>{
      'AdminShell': built(app.AdminShell),
      'AdminSystemSettingsScreen': built(app.AdminSystemSettingsScreen),
      'AdminUsersScreen': built(app.AdminUsersScreen),
      'AdminNarrativeMonitorScreen': built(app.AdminNarrativeMonitorScreen),
    };
    final storedRole = storedUsers(backend)['users/${kTourist.uid}']?['role'] as String?;
    final settingsAfter = '${storedSettings(backend)}';

    final observed = <String, Object?>{
      'adminSettingsAllowed':
          adminScreensBuilt.values.any((b) => b) ||
          entriesFound.isNotEmpty ||
          settingsAfter != settingsBefore,
      'authorizationDenied':
          storedRole == UserRoles.tourist &&
          !UserService().isAuthorizedAdminEmail(kTourist.email) &&
          shell.userRole == UserRoles.tourist &&
          adminScreensBuilt.values.every((b) => !b) &&
          entriesFound.isEmpty &&
          settingsAfter == settingsBefore &&
          scannedTexts.length == tabs.length &&
          scannedTexts.values.every((n) => n > 0),
    };
    printOnFailure(
      'CASE-120 observed: $observed\nshell.userRole=${shell.userRole} storedRole=$storedRole\n'
      'adminScreensBuilt=$adminScreensBuilt entriesFound=$entriesFound scannedTexts=$scannedTexts',
    );
    // ignore: avoid_print
    print('CASE-120 evidence: observed=$observed tabsScanned=$scannedTexts');

    // ---- Expected result (unchanged from the original CASE-120) ----------
    expect(
      observed['adminSettingsAllowed'],
      equals(false),
      reason: 'CASE-120: adminSettingsAllowed does not match the real system result',
    );
    expect(
      observed['authorizationDenied'],
      equals(true),
      reason: 'CASE-120: authorizationDenied does not match the real system result',
    );

    await unmountApp(tester);
  });
}
