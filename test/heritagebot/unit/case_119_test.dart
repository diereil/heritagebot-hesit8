// HERITAGEBOT - TEST CASE 119
// Proponent: AI Knowledge Base / System Team
// Module: System Settings
// Unit: Backup Database
// Description: Backup service fails
// Expected: Show failure without false success
//
// TEST TYPE: Flutter widget test (host VM, no device / live Firebase).
//
// REAL CODE UNDER TEST (lib/, unmodified)
//   AuthGate -> AdminShell -> "Settings" -> "Backup Database" ->
//   _backupDatabase -> SystemSettingsService.createDatabaseBackup ->
//   _backupDirectory -> getApplicationDocumentsDirectory() FAILS ->
//   catch -> "Database backup failed: ..." SnackBar.
//
// INPUT (backupService = unavailable): the device storage service that
// the backup writes to is unavailable (FakePathProviderPlatform reports a
// PlatformException "unavailable"), after HeritageBot has read the data.
//
// WHAT IS OBSERVED: no success message, no backup file, no "last backup"
// metadata written to system_settings/general, the screen still says no
// backup was created, and a failure message is shown.
//
// MOCKED: Firebase platform layer and the device storage location
// (FakePathProviderPlatform).

import 'package:flutter_test/flutter_test.dart';

import '../support/admin_operations_flow.dart';
import '../support/fake_media_platforms.dart' show pumpWithRealIoUntil;
import '../support/fake_path_provider.dart';

late HeritageBotTestBackend backend;
late FakePathProviderPlatform storage;

void main() {
  setUpAll(() async {
    backend = await HeritageBotTestBackend.install(accounts: [kAdminAccount]);
    storage = FakePathProviderPlatform.install('case119');
  });

  tearDownAll(() => storage.delete());

  setUp(() async {
    await backend.reset();
    storage.storageAvailable = false;
    seedRegisteredSites(backend, [kMagellansCross]);
    seedSystemSettings(backend, enabledLanguageCodes: const ['en', 'fil'], notificationsEnabled: true);
  });

  testWidgets('CASE-119 - Backup service fails', (WidgetTester tester) async {
    usePhoneSurface(tester);
    final settingsBefore = '${storedSettings(backend)}';

    await openAdminShell(tester);
    await openSettingsTab(tester);

    // STEP: "Backup Database" while the storage service is unavailable.
    await tapSettingsButton(tester, 'Backup Database');
    final finished = await pumpWithRealIoUntil(tester, () => shownSnackBarTexts(tester).isNotEmpty);
    await pumpFor(tester, const Duration(milliseconds: 400));
    final messages = shownSnackBarTexts(tester);
    final texts = await settingsTexts(tester);

    // ---- Observations -----------------------------------------------------
    final settings = storedSettings(backend);
    final observed = <String, Object?>{
      'backupSucceeded':
          messages.any((m) => m.startsWith('Database backup created')) ||
          storage.backupFiles().isNotEmpty ||
          (settings?['lastBackupFileName']?.toString().isNotEmpty ?? false) ||
          settings?['lastBackupAtMillis'] != null ||
          !texts.contains('Last Backup: No backup created yet'),
      'backupErrorVisible':
          finished &&
          messages.any((m) => m.startsWith('Database backup failed:')) &&
          storage.documentsPathRequests > 0 &&
          '$settings' == settingsBefore,
    };
    printOnFailure(
      'CASE-119 observed: $observed\nfinished=$finished messages=$messages\n'
      'settingsBefore=$settingsBefore\nsettingsAfter=$settings\nfiles=${storage.backupFiles()}',
    );
    // ignore: avoid_print
    print('CASE-119 evidence: observed=$observed messages=$messages');

    // ---- Expected result (unchanged from the original CASE-119) ----------
    expect(
      observed['backupSucceeded'],
      equals(false),
      reason: 'CASE-119: backupSucceeded does not match the real system result',
    );
    expect(
      observed['backupErrorVisible'],
      equals(true),
      reason: 'CASE-119: backupErrorVisible does not match the real system result',
    );

    await unmountApp(tester);
  });
}
