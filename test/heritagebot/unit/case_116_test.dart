// HERITAGEBOT - TEST CASE 116
// Proponent: AI Knowledge Base / System Team
// Module: System Settings
// Unit: Save Settings
// Description: Submit valid changes
// Expected: Persist settings successfully
//
// TEST TYPE: Flutter widget test (host VM, no device / live Firebase).
//
// REAL CODE UNDER TEST (lib/, unmodified)
//   AuthGate -> AdminShell -> "Settings" -> several valid changes ->
//   "Save Settings" -> SystemSettingsService.saveSettings ->
//   system_settings/general.set(merge) -> getSettings; then the screen is
//   reloaded ("Refresh") and HeritageBot's runtime settings are read.
//
// FIXTURE (fixtureId = CASE-116): saved settings en+fil+ko, notifications
// ON, plus an earlier backup record that a settings save must not erase.
// Changes: enable Spanish, disable Filipino, turn notifications OFF.
//
// MOCKED: Firebase platform layer only (in-memory Firestore).

import 'package:flutter_test/flutter_test.dart';

import 'package:heritagebot/services/system_settings_service.dart';

import '../support/admin_operations_flow.dart';

const Set<String> kExpectedCodes = {'en', 'ko', 'es'};

late HeritageBotTestBackend backend;

void main() {
  setUpAll(() async {
    backend = await HeritageBotTestBackend.install(accounts: [kAdminAccount]);
  });

  setUp(() async {
    await backend.reset();
    seedSystemSettings(backend, enabledLanguageCodes: const ['en', 'fil', 'ko'], notificationsEnabled: true, lastBackupAtMillis: 1767258000000, lastBackupFileName: 'heritagebot_backup_20260101_090000.json', lastBackupRecordCount: 42);
  });

  testWidgets('CASE-116 - Submit valid changes', (WidgetTester tester) async {
    usePhoneSurface(tester);
    final before = Map<String, dynamic>.of(storedSettings(backend)!);

    await openAdminShell(tester);
    await openSettingsTab(tester);

    // STEP: make the valid changes and save.
    await tapLanguageCheckbox(tester, 'Spanish');
    await tapLanguageCheckbox(tester, 'Filipino / Tagalog');
    await tapNotificationSwitch(tester);
    await tapSettingsButton(tester, 'Save Settings');
    await pumpUntilFound(tester, find.textContaining('System settings saved successfully.').hitTestable());
    final messages = shownSnackBarTexts(tester);

    // STEP: reload from Firestore.
    await refreshSettings(tester);
    final checks = await languageCheckboxStates(tester);
    final notifications = await readNotificationSwitch(tester);

    // ---- Observations -----------------------------------------------------
    final after = storedSettings(backend);
    final stored = ((after?['enabledLanguageCodes'] as List?) ?? const []).cast<String>().toSet();
    final checkedNames = checks.entries.where((e) => e.value.checked).map((e) => e.key).toSet();

    final observed = <String, Object?>{
      'settingsSaved':
          messages.contains('System settings saved successfully.') &&
          stored.length == kExpectedCodes.length &&
          stored.containsAll(kExpectedCodes) &&
          after?['notificationsEnabled'] == false &&
          after?['updatedByEmail'] == kAdminAccount.email,
      'changesPersisted':
          checkedNames.length == 3 &&
          checkedNames.containsAll({'English', 'Korean', 'Spanish'}) &&
          notifications == false &&
          SystemSettingsService.runtimeSettings.enabledLanguageCodes.length == 3 &&
          SystemSettingsService.runtimeSettings.enabledLanguageCodes.containsAll(kExpectedCodes) &&
          SystemSettingsService.notificationsEnabled == false &&
          // merge: the earlier backup record is kept
          after?['lastBackupFileName'] == before['lastBackupFileName'] &&
          after?['lastBackupRecordCount'] == before['lastBackupRecordCount'],
    };
    printOnFailure(
      'CASE-116 observed: $observed\nmessages=$messages\nbefore=$before\nafter=$after\n'
      'checkedAfterReload=$checkedNames notifications=$notifications',
    );
    // ignore: avoid_print
    print('CASE-116 evidence: observed=$observed stored=${after?['enabledLanguageCodes']} '
        'notificationsEnabled=${after?['notificationsEnabled']}');

    // ---- Expected result (unchanged from the original CASE-116) ----------
    expect(
      observed['settingsSaved'],
      equals(true),
      reason: 'CASE-116: settingsSaved does not match the real system result',
    );
    expect(
      observed['changesPersisted'],
      equals(true),
      reason: 'CASE-116: changesPersisted does not match the real system result',
    );

    await unmountApp(tester);
  });
}
