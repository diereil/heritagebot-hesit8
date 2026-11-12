// HERITAGEBOT - TEST CASE 073
// Proponent: James Stephen O. Ramos
// Module: Administrator Dashboard
// Unit: Generate Report
// Description: Generate report for selected period
// Expected: Create report using selected records
//
// TEST TYPE: Flutter widget test (host VM, no device / live Firebase).
//
// REAL CODE UNDER TEST (lib/, unmodified)
//   AuthGate -> AdminShell -> "Summary" (AdminAnalyticsScreen) ->
//   "Generate PDF Report" tile -> _generateReport ->
//   AdminAnalyticsService.loadSnapshot -> AdminReportService
//   .generateSystemReport -> buildSystemReport (package:pdf) ->
//   Printing.layoutPdf (the phone's print / save-as-PDF dialog).
//
// SELECTED PERIOD: October 2026 (2026-10-01 .. 2026-10-31).
// CONTROLLED DATA (isolated in-memory Firestore)
//   IN the period : submission "Sinulog-Night-Procession" (created
//                   2026-10-12) and tourist "Rosa Octavio" (registered
//                   2026-10-05).
//   OUTSIDE it    : submission "Old-Parian-Fiesta" (created 2025-03-02) and
//                   tourist "Pedro Antiguo" (registered 2025-02-14).
//
// WHAT IS OBSERVED
//   * whether the real Summary screen / report flow lets the administrator
//     choose a reporting period at all (any period / date-range text or
//     control on the screen, or a date picker / dialog opened by the
//     "Generate PDF Report" tile), and
//   * which records the generated PDF really contains (text read back from
//     the PDF bytes HeritageBot sent to the print dialog).
//   A period counts as applied only if it could be selected AND the report
//   holds the in-period records but not the out-of-period ones.
//
// MOCKED: Firebase platform layer and the OS print dialog
// (FakePrintingPlatform). The PDF itself is built by the real
// AdminReportService.

// printing is a direct HeritageBot dependency (pubspec.yaml unchanged).
// ignore_for_file: implementation_imports

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:printing/src/interface.dart';

import 'package:heritagebot/main.dart' as app;
import 'package:heritagebot/models/community_submission.dart';
import 'package:heritagebot/models/user_profile.dart';

import '../support/admin_flow.dart';
import '../support/fake_media_platforms.dart' show pumpWithRealIoUntil;
import '../support/fake_printing_platform.dart';

const String kInPeriodStory = 'Sinulog-Night-Procession';
const String kOutOfPeriodStory = 'Old-Parian-Fiesta';
const String kInPeriodUser = 'Octavio';
const String kOutOfPeriodUser = 'Antiguo';

final int kOct12 = DateTime(2026, 10, 12).millisecondsSinceEpoch;
final int kOct05 = DateTime(2026, 10, 5).millisecondsSinceEpoch;
final int kMar2025 = DateTime(2025, 3, 2).millisecondsSinceEpoch;
final int kFeb2025 = DateTime(2025, 2, 14).millisecondsSinceEpoch;

/// Text that would identify a reporting-period / date-range control.
final RegExp kPeriodControl = RegExp(
  r'period|date range|start date|end date|from date|to date|select (a )?(month|year|date)|reporting (window|range)',
  caseSensitive: false,
);

late HeritageBotTestBackend backend;
final FakePrintingPlatform printer = FakePrintingPlatform();

void main() {
  setUpAll(() async {
    backend = await HeritageBotTestBackend.install(accounts: [kAdminAccount]);
    PrintingPlatform.instance = printer;
  });

  setUp(() async {
    await backend.reset();
    printer.clear();
    final site = bundledSite('casa_gorordo');
    seedRegisteredSites(backend, [site]);
    seedStory(backend, storyFixture(id: 'in', title: kInPeriodStory, status: CommunitySubmissionStatus.approved, site: site, createdAtMillis: kOct12, updatedAtMillis: kOct12));
    seedStory(backend, storyFixture(id: 'out', title: kOutOfPeriodStory, status: CommunitySubmissionStatus.approved, site: site, createdAtMillis: kMar2025, updatedAtMillis: kMar2025));
    seedUser(backend, SeedUser(uid: 'case073-in', fullName: 'Rosa $kInPeriodUser', email: 'rosa@heritagebot.test', role: UserRoles.tourist, createdAtMillis: kOct05));
    seedUser(backend, SeedUser(uid: 'case073-out', fullName: 'Pedro $kOutOfPeriodUser', email: 'pedro@heritagebot.test', role: UserRoles.tourist, createdAtMillis: kFeb2025));
  });

  testWidgets('CASE-073 - Generate report for selected period', (
    WidgetTester tester,
  ) async {
    usePhoneSurface(tester);
    await openAdminShell(tester);

    // STEP 1: look for a way to select October 2026 on the real screen.
    final screenTexts = await allTextsOfScreen(tester, adminSummaryScreen);
    final tooltips = tester
        .widgetList<IconButton>(
          find.descendant(of: adminSummaryScreen, matching: find.byType(IconButton)),
        )
        .map((b) => b.tooltip ?? '')
        .toList();
    final periodTexts = [...screenTexts, ...tooltips]
        .where(kPeriodControl.hasMatch)
        .toList();

    // STEP 2: tap "Generate PDF Report".
    final tile = find.descendant(
      of: adminSummaryScreen,
      matching: find.text('Generate PDF Report'),
    );
    await scrollUntilBuilt(tester, tile, screen: app.AdminAnalyticsScreen);
    await tapVisible(tester, tile);
    await tester.pump(const Duration(milliseconds: 100));
    final periodPrompt =
        find.byType(DatePickerDialog).evaluate().isNotEmpty ||
        find.byType(DateRangePickerDialog).evaluate().isNotEmpty ||
        find.byType(Dialog).evaluate().isNotEmpty ||
        find.byType(BottomSheet).evaluate().isNotEmpty;
    final finished = await pumpWithRealIoUntil(
      tester,
      () => shownSnackBarTexts(tester).isNotEmpty,
    );
    final messages = shownSnackBarTexts(tester);
    final job = printer.jobs.length == 1 ? printer.jobs.single : null;
    final words = job?.words ?? const <String>{};

    // ---- Observations -----------------------------------------------------
    final periodSelectable = periodTexts.isNotEmpty || periodPrompt;
    final observed = <String, Object?>{
      // A real PDF report was produced from the stored records.
      'reportGenerated':
          job != null &&
          job.isPdf &&
          messages.contains('HeritageBot PDF report generated successfully.') &&
          words.contains('SYSTEM') &&
          words.contains('REPORT') &&
          words.contains(kInPeriodStory),
      // The administrator's October 2026 selection was applied.
      'selectedPeriodApplied':
          periodSelectable &&
          words.contains(kInPeriodStory) &&
          words.contains(kInPeriodUser) &&
          !words.contains(kOutOfPeriodStory) &&
          !words.contains(kOutOfPeriodUser),
    };
    printOnFailure(
      'CASE-073 observed: $observed\n'
      'periodControlTexts=$periodTexts periodPromptShown=$periodPrompt '
      'finished=$finished messages=$messages\njob=$job\n'
      'reportContains: $kInPeriodStory=${words.contains(kInPeriodStory)} '
      '$kOutOfPeriodStory=${words.contains(kOutOfPeriodStory)} '
      '$kInPeriodUser=${words.contains(kInPeriodUser)} '
      '$kOutOfPeriodUser=${words.contains(kOutOfPeriodUser)}\n'
      'appBarTooltips=$tooltips\nreportLines=${job?.lines}',
    );

    // ---- Expected result (unchanged from the original CASE-073) ----------
    expect(
      observed['reportGenerated'],
      equals(true),
      reason: 'CASE-073: reportGenerated does not match the real system result',
    );
    expect(
      observed['selectedPeriodApplied'],
      equals(true),
      reason: 'CASE-073: selectedPeriodApplied does not match the real system result',
    );

    await unmountApp(tester);
  });
}
