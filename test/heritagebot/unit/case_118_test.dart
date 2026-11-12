// HERITAGEBOT - TEST CASE 118
// Proponent: AI Knowledge Base / System Team
// Module: System Settings
// Unit: Backup Database
// Description: Start authorized database backup
// Expected: Create backup or report backup error
//
// TEST TYPE: Flutter widget test (host VM, no device / live Firebase).
//
// REAL CODE UNDER TEST (lib/, unmodified)
//   AuthGate -> AdminShell (administrator) -> "Settings" -> "Backup
//   Database" -> _backupDatabase -> SystemSettingsService.createDatabaseBackup
//   (reads users + bookmarks + journal_entries, heritage_sites,
//   community_submissions, historical_contents, ai_narratives,
//   usage_events, system_settings -> JSON file in
//   getApplicationDocumentsDirectory()/HeritageBotBackups ->
//   system_settings/general lastBackup* fields) -> SnackBar + "Last Backup".
//
// FIXTURE (fixtureId = CASE-118): a populated in-memory database (users
// with a bookmark and a journal entry, sites, a submission, a knowledge
// record, an AI narrative, a usage event, settings).
//
// MOCKED: Firebase platform layer and the device storage location
// (FakePathProviderPlatform -> a temporary folder). The real JSON file is
// written to disk and read back by the test.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:heritagebot/models/community_submission.dart';

import '../support/admin_operations_flow.dart';
import '../support/fake_media_platforms.dart' show pumpWithRealIoUntil;
import '../support/fake_path_provider.dart';

const List<String> kTopLevel = [
  'heritage_sites', 'community_submissions', 'historical_contents',
  'ai_narratives', 'usage_events', 'system_settings',
];

late HeritageBotTestBackend backend;
late FakePathProviderPlatform storage;

void main() {
  setUpAll(() async {
    backend = await HeritageBotTestBackend.install(accounts: [kAdminAccount]);
    storage = FakePathProviderPlatform.install('case118');
  });

  tearDownAll(() => storage.delete());

  setUp(() async {
    await backend.reset();
    seedRegisteredSites(backend, [kMagellansCross, bundledSite('fort_san_pedro')]);
    seedUser(backend, const SeedUser(uid: 'case118-tourist', fullName: 'Tess Tourist', email: 'tess@heritagebot.test', role: 'tourist'));
    seedBookmark(backend, userUid: 'case118-tourist', site: kMagellansCross);
    backend.firestore.seedDocument('users/case118-tourist/journal_entries/j1', <String, dynamic>{'placeId': kMagellansCross.id, 'letter': 'A quiet morning at the cross.', 'createdAtMillis': 1767225600000});
    seedStory(backend, storyFixture(id: 'case118-story', title: 'Candles at the Cross', status: CommunitySubmissionStatus.approved, site: kMagellansCross));
    seedHistorical(backend, historicalRecord(id: 'case118-kb', site: kMagellansCross, title: 'Planting of the Cross', content: 'The cross was planted by the Magellan expedition in April 1521.', sourceTitle: 'Cebu City Tourism Office'));
    seedNarrative(backend, id: 'case118-narrative', site: kMagellansCross);
    seedUsageEvent(backend, id: 'case118-event', eventType: 'site_view', site: kMagellansCross);
    seedSystemSettings(backend, enabledLanguageCodes: const ['en', 'fil'], notificationsEnabled: true);
  });

  testWidgets('CASE-118 - Start authorized database backup', (WidgetTester tester) async {
    usePhoneSurface(tester);

    await openAdminShell(tester);
    await openSettingsTab(tester);
    final lastBackupBefore = (await settingsTexts(tester)).where((t) => t.startsWith('Last Backup:')).toList();

    // Expected record count, from the database as it is when the backup starts.
    final docs = backend.firestore.documents.keys.toList();
    final userDocs = docs.where((p) => p.startsWith('users/') && p.split('/').length == 2).length;
    final subDocs = docs.where((p) {
      final s = p.split('/');
      return s.length == 4 && s[0] == 'users' && (s[2] == 'bookmarks' || s[2] == 'journal_entries');
    }).length;
    final topDocs = docs.where((p) => p.split('/').length == 2 && kTopLevel.contains(p.split('/').first)).length;
    final expectedRecords = userDocs + subDocs + topDocs;

    // STEP: "Backup Database".
    await tapSettingsButton(tester, 'Backup Database');
    final finished = await pumpWithRealIoUntil(tester, () => shownSnackBarTexts(tester).isNotEmpty);
    await pumpFor(tester, const Duration(milliseconds: 400));
    final messages = shownSnackBarTexts(tester);
    final texts = await settingsTexts(tester);

    // ---- Observations -----------------------------------------------------
    final files = storage.backupFiles();
    Map<String, dynamic>? json;
    if (files.length == 1) {
      json = await tester.runAsync(() async => jsonDecode(await files.single.readAsString()) as Map<String, dynamic>);
    }
    final fileName = files.length == 1 ? files.single.uri.pathSegments.last : null;
    final settings = storedSettings(backend);
    final users = (json?['users'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    final tourist = users.where((u) => u['_documentId'] == 'case118-tourist').firstOrNull;

    final observed = <String, Object?>{
      'backupOutcomeRecorded':
          finished &&
          fileName != null &&
          messages.contains('Database backup created: $fileName ($expectedRecords records).') &&
          json?['backupMetadata']?['createdByEmail'] == kAdminAccount.email &&
          users.length == userDocs &&
          (tourist?['_subcollections']?['bookmarks'] as List?)?.length == 1 &&
          (tourist?['_subcollections']?['journal_entries'] as List?)?.length == 1 &&
          kTopLevel.every((c) => (json?[c] as List?) != null) &&
          (json?['community_submissions'] as List).length == 1 &&
          (json?['historical_contents'] as List).length == 1 &&
          settings?['lastBackupFileName'] == fileName &&
          settings?['lastBackupRecordCount'] == expectedRecords &&
          settings?['lastBackupByEmail'] == kAdminAccount.email &&
          texts.contains(fileName) &&
          texts.contains('$expectedRecords records included') &&
          !texts.contains('Last Backup: No backup created yet'),
      'backupOperationAttempted':
          storage.documentsPathRequests > 0 &&
          (files.isNotEmpty || messages.any((m) => m.startsWith('Database backup failed'))),
    };
    printOnFailure(
      'CASE-118 observed: $observed\nfinished=$finished messages=$messages\n'
      'lastBackupBefore=$lastBackupBefore files=$files expectedRecords=$expectedRecords\n'
      'settings=$settings\njsonKeys=${json?.keys}',
    );
    // ignore: avoid_print
    print('CASE-118 evidence: observed=$observed messages=$messages file=$fileName '
        'lastBackupBefore=$lastBackupBefore');

    // ---- Expected result (unchanged from the original CASE-118) ----------
    expect(
      observed['backupOutcomeRecorded'],
      equals(true),
      reason: 'CASE-118: backupOutcomeRecorded does not match the real system result',
    );
    expect(
      observed['backupOperationAttempted'],
      equals(true),
      reason: 'CASE-118: backupOperationAttempted does not match the real system result',
    );

    await unmountApp(tester);
  });
}
