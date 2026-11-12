// HERITAGEBOT - TEST CASE 086
// Proponent: James Stephen O. Ramos
// Module: Heritage Site Management
// Unit: Add Heritage Site
// Description: Omit required site name
// Expected: Show required-field error
//
// TEST TYPE: Flutter widget test (host VM, no device / live Firebase).
//
// REAL CODE UNDER TEST (lib/, unmodified)
//   AuthGate -> AdminShell -> "Sites" -> "Add Site" ->
//   HeritageSiteEditorScreen -> "Save Heritage Site" ->
//   HeritageSiteService.createSite -> _validateSite (name length check) ->
//   error message shown by the editor.
//
// INPUT (siteName): "" - every other field is valid, so only the missing
// site name can stop the save.
//
// MOCKED: Firebase platform layer only.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/admin_flow.dart';

const String kSiteName = '';
const String kLocation = 'Osmena Boulevard, Cebu City';
const String kFacts =
    'The Basilica Minore del Santo Nino was founded in 1565 and is the oldest '
    'Roman Catholic church in the Philippines.';

/// A message telling the administrator that the site name is needed.
final RegExp kNameRequired = RegExp(
  r'(site )?name.*(required|enter|provide|missing|empty)|(required|enter|provide).*(site )?name',
  caseSensitive: false,
);

late HeritageBotTestBackend backend;

void main() {
  setUpAll(() async {
    backend = await HeritageBotTestBackend.install(accounts: [kAdminAccount]);
  });

  setUp(() async {
    await backend.reset();
    seedRegisteredSites(backend, [kMagellansCross, bundledSite('casa_gorordo')]);
  });

  testWidgets('CASE-086 - Omit required site name', (WidgetTester tester) async {
    usePhoneSurface(tester);
    await openAdminShell(tester);
    await openAdminSites(tester);
    final before = Map<String, Map<String, dynamic>>.of(storedSites(backend));

    // STEP: "Add Site", leave Site Name empty, fill everything else.
    await openSiteEditor(tester);
    await enterEditorField(tester, 'Site Name', kSiteName);
    await enterEditorField(tester, 'Location / Address', kLocation);
    await enterEditorField(tester, 'Latitude', '10.29436');
    await enterEditorField(tester, 'Longitude', '123.90207');
    await enterEditorField(tester, 'Detection Radius (meters)', '500');
    await enterEditorField(tester, 'Historical Information', kFacts);

    // STEP: "Save Heritage Site".
    final closed = await saveSiteEditor(tester);
    final messages = shownSnackBarTexts(tester);
    final fieldErrors = tester
        .widgetList<InputDecorator>(
          find.descendant(of: siteEditorScreen, matching: find.byType(InputDecorator)),
        )
        .map((d) => d.decoration.errorText)
        .whereType<String>()
        .toList();

    // ---- Observations -----------------------------------------------------
    final after = storedSites(backend);
    final observed = <String, Object?>{
      'heritageSiteSaved': closed || after.length != before.length,
      'nameRequiredVisible':
          !closed &&
          [...messages, ...fieldErrors].any(kNameRequired.hasMatch),
    };
    printOnFailure(
      'CASE-086 observed: $observed\nclosed=$closed messages=$messages '
      'fieldErrors=$fieldErrors\nsitesBefore=${before.keys} '
      'sitesAfter=${after.keys}',
    );
    // ignore: avoid_print
    print('CASE-086 evidence: message shown = $messages, field errors = $fieldErrors');

    // ---- Expected result (unchanged from the original CASE-086) ----------
    expect(
      observed['heritageSiteSaved'],
      equals(false),
      reason: 'CASE-086: heritageSiteSaved does not match the real system result',
    );
    expect(
      observed['nameRequiredVisible'],
      equals(true),
      reason: 'CASE-086: nameRequiredVisible does not match the real system result',
    );

    await unmountApp(tester);
  });
}
