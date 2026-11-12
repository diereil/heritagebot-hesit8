// HERITAGEBOT - TEST CASE 089
// Proponent: James Stephen O. Ramos
// Module: Heritage Site Management
// Unit: Delete Heritage Site
// Description: Cancel site deletion
// Expected: Keep existing site record
//
// TEST TYPE: Flutter widget test (host VM, no device / live Firebase).
//
// REAL CODE UNDER TEST (lib/, unmodified)
//   AuthGate -> AdminShell -> "Sites" (AdminHeritageSitesScreen) ->
//   "Delete" on Magellan's Cross -> "Delete Heritage Site?" dialog ->
//   "Cancel" (confirmDelete = false) -> _deleteSite returns before
//   HeritageSiteService.deleteSite.
//
// MOCKED: Firebase platform layer only.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:heritagebot/models/heritage_place.dart';

import '../support/admin_flow.dart';

const bool kConfirmDelete = false;

late HeritageBotTestBackend backend;

void main() {
  setUpAll(() async {
    backend = await HeritageBotTestBackend.install(accounts: [kAdminAccount]);
  });

  setUp(() async {
    await backend.reset();
    seedRegisteredSites(backend, [kMagellansCross, bundledSite('casa_gorordo')]);
  });

  testWidgets('CASE-089 - Cancel site deletion', (WidgetTester tester) async {
    usePhoneSurface(tester);
    await openAdminShell(tester);
    await openAdminSites(tester);
    final path = 'heritage_sites/${kMagellansCross.id}';
    final before = '${storedSites(backend)}';
    final runtimeBefore = heritagePlaces.map((p) => p.id).toList();

    // STEP: "Delete" -> dialog -> "Cancel".
    await tapSiteAction(tester, siteName: kMagellansCross.name, action: 'Delete');
    await pumpFor(tester, const Duration(milliseconds: 300));
    final dialogShown = textsUnder(tester, find.byType(AlertDialog))
        .contains('Delete Heritage Site?');
    await tapDialogButton(tester, kConfirmDelete ? 'Delete' : 'Cancel');
    await pumpFor(tester, const Duration(milliseconds: 800));
    final dialogClosed = find.byType(AlertDialog).evaluate().isEmpty;
    final messages = shownSnackBarTexts(tester);
    final listed = await listedSites(tester);

    // ---- Observations -----------------------------------------------------
    final after = storedSites(backend);
    final observed = <String, Object?>{
      'heritageSiteDeleted':
          !after.containsKey(path) ||
          messages.contains('${kMagellansCross.name} was deleted.'),
      'siteRecordPreserved':
          dialogShown &&
          dialogClosed &&
          after.containsKey(path) &&
          '$after' == before &&
          listed.any((s) => s.name == kMagellansCross.name) &&
          // the app's runtime site list was not refreshed / changed either
          '${heritagePlaces.map((p) => p.id).toList()}' == '$runtimeBefore',
    };
    printOnFailure(
      'CASE-089 observed: $observed\ndialogShown=$dialogShown '
      'dialogClosed=$dialogClosed messages=$messages\nbefore=$before\n'
      'after=$after\nlisted=$listed',
    );

    // ---- Expected result (unchanged from the original CASE-089) ----------
    expect(
      observed['heritageSiteDeleted'],
      equals(false),
      reason: 'CASE-089: heritageSiteDeleted does not match the real system result',
    );
    expect(
      observed['siteRecordPreserved'],
      equals(true),
      reason: 'CASE-089: siteRecordPreserved does not match the real system result',
    );

    await unmountApp(tester);
  });
}
