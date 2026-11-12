// HERITAGEBOT - TEST CASE 117
// Proponent: AI Knowledge Base / System Team
// Module: System Settings
// Unit: Save Settings
// Description: Submit invalid settings
// Expected: Reject invalid configuration
//
// TEST TYPE: Flutter widget test (host VM, no device / live Firebase).
//
// REAL CODE UNDER TEST (lib/, unmodified)
//   1. AdminSystemSettingsScreen: the only invalid configuration the screen
//      lets an administrator attempt is disabling English, HeritageBot's
//      required fallback language (every other control is a supported
//      language or an on/off switch). The test taps the English checkbox
//      and then "Save Settings".
//   2. SystemSettingsService.saveSettings called directly with an invalid
//      configuration (an unsupported language code "xx" and no English), as
//      any other caller of the save operation could.
//
// INPUT (settingFixture = invalid_value): see above.
//
// WHAT IS OBSERVED
//   settingsSaved             - whether the INVALID value ended up stored
//                               (English missing or "xx" present) through
//                               either path.
//   settingsValidationVisible - whether the screen visibly refuses the
//                               invalid change: the English control stays
//                               checked, is locked (disabled) and is labelled
//                               "Required fallback language".
//   The direct service call has no UI; its result is recorded as evidence.
//
// MOCKED: Firebase platform layer only (in-memory Firestore).

import 'package:flutter/material.dart';
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

  testWidgets('CASE-117 - Submit invalid settings', (WidgetTester tester) async {
    usePhoneSurface(tester);

    await openAdminShell(tester);
    await openSettingsTab(tester);

    // PATH 1 - UI: try to disable English, then save.
    await tapLanguageCheckbox(tester, 'English');
    await pumpFor(tester, const Duration(milliseconds: 200));
    final englishTile = tester.widget<CheckboxListTile>(languageCheckbox('English'));
    final englishSubtitle = englishTile.subtitle is Text ? (englishTile.subtitle as Text).data : null;
    await tapSettingsButton(tester, 'Save Settings');
    await pumpFor(tester, const Duration(milliseconds: 800));
    final uiMessages = shownSnackBarTexts(tester);
    final storedAfterUi = Map<String, dynamic>.of(storedSettings(backend) ?? const {});

    // PATH 2 - service: an unsupported code and no English.
    Object? serviceOutcome;
    try {
      final saved = await SystemSettingsService().saveSettings(
        enabledLanguageCodes: {'xx'},
        notificationsEnabled: true,
      );
      serviceOutcome = 'returned enabledLanguageCodes=${saved.enabledLanguageCodes}';
    } catch (e) {
      serviceOutcome = e;
    }
    final storedAfterService = Map<String, dynamic>.of(storedSettings(backend) ?? const {});

    // ---- Observations -----------------------------------------------------
    bool invalidStored(Map<String, dynamic> doc) {
      final codes = ((doc['enabledLanguageCodes'] as List?) ?? const []).cast<String>();
      return !codes.contains('en') || codes.contains('xx');
    }

    final observed = <String, Object?>{
      'settingsSaved': invalidStored(storedAfterUi) || invalidStored(storedAfterService),
      'settingsValidationVisible':
          englishTile.value == true &&
          englishTile.onChanged == null &&
          englishSubtitle == 'Required fallback language',
    };
    printOnFailure(
      'CASE-117 observed: $observed\nenglish checked=${englishTile.value} '
      'locked=${englishTile.onChanged == null} subtitle=$englishSubtitle\n'
      'uiMessages=$uiMessages\nstoredAfterUi=$storedAfterUi\n'
      'serviceOutcome=$serviceOutcome\nstoredAfterService=$storedAfterService',
    );
    // ignore: avoid_print
    print('CASE-117 evidence: observed=$observed\n  UI: English checked=${englishTile.value} '
        'locked=${englishTile.onChanged == null} subtitle="$englishSubtitle" messages=$uiMessages\n'
        '  service saveSettings({xx}) -> $serviceOutcome; stored=${storedAfterService['enabledLanguageCodes']}');

    // ---- Expected result (unchanged from the original CASE-117) ----------
    expect(
      observed['settingsSaved'],
      equals(false),
      reason: 'CASE-117: settingsSaved does not match the real system result',
    );
    expect(
      observed['settingsValidationVisible'],
      equals(true),
      reason: 'CASE-117: settingsValidationVisible does not match the real system result',
    );

    await unmountApp(tester);
  });
}
