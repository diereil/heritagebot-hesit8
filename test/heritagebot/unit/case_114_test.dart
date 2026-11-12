// HERITAGEBOT - TEST CASE 114
// Proponent: AI Knowledge Base / System Team
// Module: System Settings
// Unit: Update Language Settings
// Description: Enable supported language
// Expected: Save language configuration
//
// TEST TYPE: Flutter widget test (host VM, no device / live Firebase).
//
// REAL CODE UNDER TEST (lib/, unmodified)
//   AuthGate -> AdminShell -> "Settings" -> "Korean" checkbox ->
//   "Save Settings" -> _saveSettings -> SystemSettingsService.saveSettings
//   (known codes only, English always kept) -> system_settings/general.set
//   (merge) -> getSettings -> runtimeSettings -> enabledLanguagesForUi.
//
// FIXTURE (fixtureId = CASE-114): saved settings with only English and
// Filipino enabled; the administrator enables Korean (code "ko", one of
// HeritageBot's supportedLanguages).
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
    seedSystemSettings(backend, enabledLanguageCodes: const ['en', 'fil'], notificationsEnabled: true);
  });

  testWidgets('CASE-114 - Enable supported language', (WidgetTester tester) async {
    usePhoneSurface(tester);
    final before = Map<String, dynamic>.of(storedSettings(backend)!);

    await openAdminShell(tester);
    await openSettingsTab(tester);
    final koreanBefore = (await languageCheckboxStates(tester))['Korean'];

    // STEP: enable Korean and save.
    await tapLanguageCheckbox(tester, 'Korean');
    await tapSettingsButton(tester, 'Save Settings');
    await pumpUntilFound(tester, find.textContaining('System settings saved successfully.').hitTestable());
    final messages = shownSnackBarTexts(tester);

    // STEP: reload the screen from Firestore.
    await refreshSettings(tester);
    final koreanAfterReload = (await languageCheckboxStates(tester))['Korean'];

    // ---- Observations -----------------------------------------------------
    final after = storedSettings(backend);
    final stored = ((after?['enabledLanguageCodes'] as List?) ?? const []).cast<String>();
    final observed = <String, Object?>{
      'languageSettingsSaved':
          messages.contains('System settings saved successfully.') &&
          stored.toSet().containsAll({'en', 'fil', 'ko'}) &&
          stored.length == 3 &&
          after?['notificationsEnabled'] == true &&
          after?['updatedByEmail'] == kAdminAccount.email &&
          (after?['updatedAtMillis'] as num) > (before['updatedAtMillis'] as num),
      'languageEnabled':
          koreanBefore?.checked == false &&
          koreanAfterReload?.checked == true &&
          SystemSettingsService.runtimeSettings.enabledLanguageCodes.contains('ko') &&
          SystemSettingsService.enabledLanguagesForUi().any((l) => l.code == 'ko'),
    };
    printOnFailure(
      'CASE-114 observed: $observed\nmessages=$messages\nbefore=$before\nafter=$after\n'
      'koreanBefore=$koreanBefore koreanAfterReload=$koreanAfterReload',
    );
    // ignore: avoid_print
    print('CASE-114 evidence: observed=$observed storedLanguages=$stored');

    // ---- Expected result (unchanged from the original CASE-114) ----------
    expect(
      observed['languageSettingsSaved'],
      equals(true),
      reason: 'CASE-114: languageSettingsSaved does not match the real system result',
    );
    expect(
      observed['languageEnabled'],
      equals(true),
      reason: 'CASE-114: languageEnabled does not match the real system result',
    );

    await unmountApp(tester);
  });
}
