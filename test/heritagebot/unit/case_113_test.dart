// HERITAGEBOT - TEST CASE 113
// Proponent: AI Knowledge Base / System Team
// Module: System Settings
// Unit: View System Settings
// Description: Open settings as administrator
// Expected: Display saved settings
//
// TEST TYPE: Flutter widget test (host VM, no device / live Firebase).
//
// REAL CODE UNDER TEST (lib/, unmodified)
//   AuthGate -> AdminShell -> "Settings" (AdminSystemSettingsScreen) ->
//   SystemSettingsService.getSettings (system_settings/general) ->
//   HeritageBotSystemSettings.fromMap -> _initializeForm -> "Language
//   Settings" checkboxes, "Notification Settings" switch, "Database Backup"
//   (Last Backup / file name / record count).
//
// FIXTURE (fixtureId = CASE-113): saved settings that differ from the
// defaults - only English, Filipino and Japanese enabled, notifications
// OFF, and a previous backup (file name + 42 records).
//
// MOCKED: Firebase platform layer only (in-memory Firestore).

import 'package:flutter_test/flutter_test.dart';

import 'package:heritagebot/services/language_service.dart';

import '../support/admin_operations_flow.dart';

const List<String> kEnabled = ['en', 'fil', 'ja'];
const int kLastBackupAt = 1767258000000; // 2026-01-01
const String kBackupFile = 'heritagebot_backup_20260101_090000.json';

String formatLikeScreen(int millis) {
  final date = DateTime.fromMillisecondsSinceEpoch(millis).toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(date.month)}/${two(date.day)}/${date.year} ${two(date.hour)}:${two(date.minute)}';
}

late HeritageBotTestBackend backend;

void main() {
  setUpAll(() async {
    backend = await HeritageBotTestBackend.install(accounts: [kAdminAccount]);
  });

  setUp(() async {
    await backend.reset();
    seedSystemSettings(backend, enabledLanguageCodes: kEnabled, notificationsEnabled: false, lastBackupAtMillis: kLastBackupAt, lastBackupFileName: kBackupFile, lastBackupRecordCount: 42);
  });

  testWidgets('CASE-113 - Open settings as administrator', (WidgetTester tester) async {
    usePhoneSurface(tester);

    await openAdminShell(tester);
    await openSettingsTab(tester);
    final texts = await settingsTexts(tester);
    final checkboxes = await languageCheckboxStates(tester);
    final notifications = await readNotificationSwitch(tester);

    // ---- Observations -----------------------------------------------------
    final expectedChecks = {
      for (final language in supportedLanguages) language.name: kEnabled.contains(language.code),
    };
    final observed = <String, Object?>{
      'settingsVisible':
          infoCardsTitled(tester, 'System Settings Unavailable').isEmpty &&
          texts.containsAll(['Backup and System Settings', 'Language Settings', 'Notification Settings', 'Database Backup', 'Save Settings']) &&
          checkboxes.length == supportedLanguages.length,
      'storedValuesLoaded':
          expectedChecks.entries.every((e) => checkboxes[e.key]?.checked == e.value) &&
          checkboxes['English']?.enabled == false &&
          notifications == false &&
          texts.contains('Last Backup: ${formatLikeScreen(kLastBackupAt)}') &&
          texts.contains(kBackupFile) &&
          texts.contains('42 records included'),
    };
    printOnFailure(
      'CASE-113 observed: $observed\ncheckboxes=$checkboxes\nexpected=$expectedChecks\n'
      'notifications=$notifications\ntexts=$texts',
    );
    // ignore: avoid_print
    print('CASE-113 evidence: observed=$observed checked=${checkboxes.entries.where((e) => e.value.checked).map((e) => e.key).toList()} '
        'notifications=$notifications');

    // ---- Expected result (unchanged from the original CASE-113) ----------
    expect(
      observed['settingsVisible'],
      equals(true),
      reason: 'CASE-113: settingsVisible does not match the real system result',
    );
    expect(
      observed['storedValuesLoaded'],
      equals(true),
      reason: 'CASE-113: storedValuesLoaded does not match the real system result',
    );

    await unmountApp(tester);
  });
}
