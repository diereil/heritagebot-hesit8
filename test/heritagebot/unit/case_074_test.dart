// HERITAGEBOT - TEST CASE 074
// Proponent: James Stephen O. Ramos
// Module: Administrator Dashboard
// Unit: Generate Report
// Description: Request report with no matching data
// Expected: Show empty report or no-data message
//
// TEST TYPE: Flutter widget test (host VM, no device / live Firebase).
//
// REAL CODE UNDER TEST (lib/, unmodified)
//   AuthGate -> AdminShell -> "Summary" (AdminAnalyticsScreen) ->
//   "Generate PDF Report" -> AdminAnalyticsService.loadSnapshot ->
//   AdminReportService.generateSystemReport / buildSystemReport ->
//   Printing.layoutPdf.
//
// "NO MATCHING DATA": HeritageBot's report has no period or filter input
// (see CASE-073), so the only way to request a report with no matching
// records is a database that holds none: no heritage sites, community
// submissions, AI narratives, usage events or bookmarks. The only account
// is the administrator profile UserService itself writes on login.
//
// WHAT IS OBSERVED
//   * the no-data messages shown by the real Summary screen, and
//   * the PDF HeritageBot generated (read back from the bytes sent to the
//     print dialog): no site rows, no "Recent Community Submissions"
//     section, zero counts on the screen it was requested from,
//   * that the request completes without an error message or exception.
//
// MOCKED: Firebase platform layer and the OS print dialog
// (FakePrintingPlatform).

// ignore_for_file: implementation_imports

import 'package:flutter_test/flutter_test.dart';
import 'package:printing/src/interface.dart';

import 'package:heritagebot/main.dart' as app;

import '../support/admin_flow.dart';
import '../support/fake_media_platforms.dart' show pumpWithRealIoUntil;
import '../support/fake_printing_platform.dart';

const String kNoViews = 'No site-view activity has been recorded yet.';
const String kNoBookmarks = 'No heritage-site bookmarks are available yet.';

late HeritageBotTestBackend backend;
final FakePrintingPlatform printer = FakePrintingPlatform();

void main() {
  setUpAll(() async {
    backend = await HeritageBotTestBackend.install(accounts: [kAdminAccount]);
    PrintingPlatform.instance = printer;
  });

  setUp(() async {
    await backend.reset(); // empty database
    printer.clear();
  });

  testWidgets('CASE-074 - Request report with no matching data', (
    WidgetTester tester,
  ) async {
    usePhoneSurface(tester);
    await openAdminShell(tester);
    final view = await readAdminSummary(tester);

    // STEP: tap "Generate PDF Report".
    final tile = find.descendant(
      of: adminSummaryScreen,
      matching: find.text('Generate PDF Report'),
    );
    await scrollUntilBuilt(tester, tile, screen: app.AdminAnalyticsScreen);
    await tapVisible(tester, tile);
    final finished = await pumpWithRealIoUntil(
      tester,
      () => shownSnackBarTexts(tester).isNotEmpty,
    );
    final messages = shownSnackBarTexts(tester);
    final exception = tester.takeException();
    final job = printer.jobs.length == 1 ? printer.jobs.single : null;
    final words = job?.words ?? const <String>{};

    // ---- Observations -----------------------------------------------------
    final summaryTexts = view.sections.values.expand((t) => t).toList();
    final noDataMessages = summaryTexts
        .where((t) => t == kNoViews || t == kNoBookmarks)
        .toList();
    final emptyOnScreen =
        view.metricValue('Total Heritage Sites') == '0' &&
        view.metricValue('Community Submissions') == '0' &&
        view.metricValue('Generated AI Narratives') == '0';
    // Report body: no heritage-site rows (type column) and no recent
    // submissions section.
    final emptyReport =
        job != null &&
        job.isPdf &&
        words.contains('SYSTEM') &&
        !words.contains('Official') &&
        !words.contains('Testing') &&
        !words.contains('Recent');

    final observed = <String, Object?>{
      'noDataMessageVisible':
          (noDataMessages.length == 2 && emptyOnScreen) || emptyReport,
      'reportErrorFree':
          finished &&
          job != null &&
          job.isPdf &&
          exception == null &&
          messages.contains('HeritageBot PDF report generated successfully.') &&
          !messages.any((m) => m.startsWith('Could not generate report')),
    };
    printOnFailure(
      'CASE-074 observed: $observed\nnoDataMessages=$noDataMessages '
      'emptyOnScreen=$emptyOnScreen emptyReport=$emptyReport\n'
      'finished=$finished messages=$messages exception=$exception\n'
      'job=$job\nreportLines=${job?.lines}\nview=$view',
    );
    // Evidence for the report (printed so the run log shows both parts).
    // ignore: avoid_print
    print(
      'CASE-074 evidence: summary no-data messages=$noDataMessages, '
      'zero counts on screen=$emptyOnScreen, empty PDF report=$emptyReport',
    );

    // ---- Expected result (unchanged from the original CASE-074) ----------
    expect(
      observed['noDataMessageVisible'],
      equals(true),
      reason: 'CASE-074: noDataMessageVisible does not match the real system result',
    );
    expect(
      observed['reportErrorFree'],
      equals(true),
      reason: 'CASE-074: reportErrorFree does not match the real system result',
    );

    await unmountApp(tester);
  });
}
