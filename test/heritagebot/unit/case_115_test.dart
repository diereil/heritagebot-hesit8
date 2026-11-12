// HERITAGEBOT - TEST CASE 115
// Proponent: AI Knowledge Base / System Team
// Module: System Settings
// Unit: Update Notification Settings
// Description: Change notification preference
// Expected: Save notification preference
//
// TEST TYPE: Flutter widget test (host VM, no device / live Firebase).
//
// REAL CODE UNDER TEST (lib/, unmodified)
//   AuthGate -> AdminShell -> "Settings" -> "Notification Settings" switch
//   -> "Save Settings" -> SystemSettingsService.saveSettings
//   (notificationsEnabled) -> system_settings/general -> getSettings ->
//   runtimeSettings (SystemSettingsService.notificationsEnabled).
//
// FIXTURE (fixtureId = CASE-115): saved settings with notifications ON;
// the administrator turns them OFF.
//
// MOCKED: Firebase platform layer only (in-memory Firestore).

import 'package:flutter_test/flutter_test.dart';

import 'package:heritagebot/services/system_settings_service.dart';

import '../support/admin_operations_flow.dart';

late HeritageBotTestBackend backend;

void main() {
  setUpAll(() async {
    backend = await HeritageBotTestBackend.install(accounts: [kAdminAccount]);
  });

  setUp(() async {
    await backend.reset();
    seedSystemSettings(backend, enabledLanguageCodes: const ['en', 'fil', 'ko'], notificationsEnabled: true);
  });

  testWidgets('CASE-115 - Change notification preference', (WidgetTester tester) async {
    usePhoneSurface(tester);
    final before = Map<String, dynamic>.of(storedSettings(backend)!);

    await openAdminShell(tester);
    await openSettingsTab(tester);
    final switchBefore = await readNotificationSwitch(tester);

    // STEP: turn notifications off and save.
    await tapNotificationSwitch(tester);
    final switchAfterTap = await readNotificationSwitch(tester);
    await tapSettingsButton(tester, 'Save Settings');
    await pumpUntilFound(tester, find.textContaining('System settings saved successfully.').hitTestable());
    final messages = shownSnackBarTexts(tester);

    // STEP: reload from Firestore.
    await refreshSettings(tester);
    final switchAfterReload = await readNotificationSwitch(tester);

    // ---- Observations -----------------------------------------------------
    final after = storedSettings(backend);
    final observed = <String, Object?>{
      'notificationSettingsSaved':
          messages.contains('System settings saved successfully.') &&
          after?['notificationsEnabled'] == false &&
          '${after?['enabledLanguageCodes']}' == '${before['enabledLanguageCodes']}' &&
          (after?['updatedAtMillis'] as num) > (before['updatedAtMillis'] as num),
      'preferencePersisted':
          switchBefore == true &&
          switchAfterTap == false &&
          switchAfterReload == false &&
          SystemSettingsService.notificationsEnabled == false,
    };
    printOnFailure(
      'CASE-115 observed: $observed\nmessages=$messages\nbefore=$before\nafter=$after\n'
      'switch $switchBefore -> $switchAfterTap -> reload $switchAfterReload',
    );
    // ignore: avoid_print
    print('CASE-115 evidence: observed=$observed stored notificationsEnabled=${after?['notificationsEnabled']}');

    // ---- Expected result (unchanged from the original CASE-115) ----------
    expect(
      observed['notificationSettingsSaved'],
      equals(true),
      reason: 'CASE-115: notificationSettingsSaved does not match the real system result',
    );
    expect(
      observed['preferencePersisted'],
      equals(true),
      reason: 'CASE-115: preferencePersisted does not match the real system result',
    );

    await unmountApp(tester);
  });
}
