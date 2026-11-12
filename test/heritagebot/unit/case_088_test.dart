// HERITAGEBOT - TEST CASE 088
// Proponent: James Stephen O. Ramos
// Module: Heritage Site Management
// Unit: Delete Heritage Site
// Description: Confirm deletion of eligible site
// Expected: Remove site according to data rules
//
// TEST TYPE: Flutter widget test (host VM, no device / live Firebase).
//
// REAL CODE UNDER TEST (lib/, unmodified)
//   AuthGate -> AdminShell -> "Sites" (AdminHeritageSitesScreen) ->
//   "Delete" on Magellan's Cross -> "Delete Heritage Site?" dialog ->
//   "Delete" -> HeritageSiteService.deleteSite (_ensureAnotherActiveSite,
//   heritage_sites/{id}.delete, refreshRuntimeSites).
//
// HERITAGEBOT'S DATA RULES (from the app itself)
//   * deletion needs the administrator's confirmation (dialog),
//   * at least one OTHER active site must remain (_ensureAnotherActiveSite),
//   * "Existing community submissions will keep their saved site name, but
//     this site will no longer be available for new selections." (dialog).
// ELIGIBLE SITE: Magellan's Cross (active) while Casa Gorordo Museum and
// Fort San Pedro stay active. An approved community story references it.
//
// MOCKED: Firebase platform layer only.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:heritagebot/models/community_submission.dart';
import 'package:heritagebot/models/heritage_place.dart';

import '../support/admin_flow.dart';

late HeritageBotTestBackend backend;

void main() {
  setUpAll(() async {
    backend = await HeritageBotTestBackend.install(accounts: [kAdminAccount]);
  });

  setUp(() async {
    await backend.reset();
    seedRegisteredSites(backend, [
      kMagellansCross,
      bundledSite('casa_gorordo'),
      bundledSite('fort_san_pedro'),
    ]);
    seedStory(
      backend,
      storyFixture(
        id: 'case088-story',
        title: 'Candles at the Cross',
        status: CommunitySubmissionStatus.approved,
        site: kMagellansCross,
      ),
    );
  });

  testWidgets('CASE-088 - Confirm deletion of eligible site', (
    WidgetTester tester,
  ) async {
    usePhoneSurface(tester);
    await openAdminShell(tester);
    await openAdminSites(tester);
    final path = 'heritage_sites/${kMagellansCross.id}';
    final othersBefore = Map<String, Map<String, dynamic>>.of(storedSites(backend))
      ..remove(path);

    // STEP: "Delete" on Magellan's Cross -> confirmation dialog.
    await tapSiteAction(tester, siteName: kMagellansCross.name, action: 'Delete');
    await pumpFor(tester, const Duration(milliseconds: 300));
    final dialogTexts = textsUnder(tester, find.byType(AlertDialog));
    final dialogShown = dialogTexts.contains('Delete Heritage Site?');
    final storedWhileAsking = storedSites(backend).containsKey(path);

    // STEP: confirm.
    await tapDialogButton(tester, 'Delete');
    await pumpFor(tester, const Duration(milliseconds: 800));
    final messages = shownSnackBarTexts(tester);
    await waitForSiteList(tester);
    final listed = await listedSites(tester);

    // ---- Observations -----------------------------------------------------
    final after = storedSites(backend);
    final othersAfter = Map<String, Map<String, dynamic>>.of(after)..remove(path);
    final story = storedSubmissions(backend)['community_submissions/case088-story'];

    final observed = <String, Object?>{
      'heritageSiteDeleted':
          !after.containsKey(path) &&
          messages.contains("${kMagellansCross.name} was deleted.") &&
          !listed.any((s) => s.name == kMagellansCross.name),
      'deleteRulesObserved':
          dialogShown &&
          storedWhileAsking &&
          '$othersAfter' == '$othersBefore' &&
          othersAfter.values.any((s) => s['isActive'] != false) &&
          story != null &&
          story['heritagePlaceName'] == kMagellansCross.name &&
          // refreshRuntimeSites: the app's active site list is now exactly
          // the remaining active Firestore sites.
          heritagePlaces.map((p) => p.id).toSet().length == 2 &&
          heritagePlaces.map((p) => p.id).toSet().containsAll(
            othersAfter.values
                .where((s) => s['isActive'] != false)
                .map((s) => s['id']),
          ),
    };
    printOnFailure(
      'CASE-088 observed: $observed\ndialog=$dialogTexts '
      'storedWhileAsking=$storedWhileAsking\nmessages=$messages\n'
      'sitesAfter=${after.keys}\nlisted=$listed\nstory=$story\n'
      'runtimeSites=${heritagePlaces.map((p) => p.id)}',
    );

    // ---- Expected result (unchanged from the original CASE-088) ----------
    expect(
      observed['heritageSiteDeleted'],
      equals(true),
      reason: 'CASE-088: heritageSiteDeleted does not match the real system result',
    );
    expect(
      observed['deleteRulesObserved'],
      equals(true),
      reason: 'CASE-088: deleteRulesObserved does not match the real system result',
    );

    await unmountApp(tester);
  });
}
