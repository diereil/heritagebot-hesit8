// HERITAGEBOT - TEST CASE 023
// Proponent: Reil Esdrelon
// Module: Tourist Heritage Access
// Unit: Search Heritage Site
// Description: Search nonexistent site ('nonexistent-test-site-xyz').
// Expected: Show no-results message.
//
// TEST TYPE: Flutter widget test (host VM, no device / live Firebase).
//
// REAL CODE UNDER TEST (lib/, unmodified)
//   HeritageSiteSearchScreen: instant registered-site matching, then
//   "Search Any Location with AI" -> HeritageDiscoveryService.searchByLocation
//   -> Nominatim geocoding (OpenStreetMap) -> error card shown by the screen.
//
// MOCKED: Firebase platform layer, and the external OpenStreetMap Nominatim
// HTTP API (package:http MockClient via http.runWithClient). Nominatim
// answers an unknown place with an empty JSON list "[]" - exactly what the
// mock returns.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:heritagebot/main.dart' as app;

import '../support/heritagebot_test_harness.dart';

const FakeAuthAccount kTourist = FakeAuthAccount(
  uid: 'case023-tourist-uid',
  email: 'case023.tourist@heritagebot.test',
  password: 'Case023Pass!',
  displayName: 'Case 023 Tourist',
);

const String kQuery = 'nonexistent-test-site-xyz';

late HeritageBotTestBackend backend;

void main() {
  setUpAll(() async {
    backend = await HeritageBotTestBackend.install(accounts: [kTourist]);
  });

  setUp(() async {
    await backend.reset();
    backend.seedTourist(kTourist);
  });

  testWidgets('CASE-023 - Search nonexistent site: no-results message is '
      'shown', (WidgetTester tester) async {
    usePhoneSurface(tester);

    final requests = <Uri>[];
    final osm = MockClient((request) async {
      requests.add(request.url);
      if (request.url.host == 'nominatim.openstreetmap.org') {
        return http.Response('[]', 200,
            headers: {'content-type': 'application/json'});
      }
      return http.Response('Not found', 404);
    });

    await http.runWithClient(() async {
      await signInBeforeLaunch(kTourist);
      await launchAuthGate(tester, until: app.HomeScreen);
      await tapVisible(tester, find.text('Explore Heritage by Location'));
      await pumpUntilFound(tester, find.byType(app.HeritageSiteSearchScreen));

      // STEP 1: Type the nonexistent site name.
      await tester.enterText(
          fieldsOf(app.HeritageSiteSearchScreen).first, kQuery);
      await tester.pump();

      // Instant matching against registered sites finds nothing.
      expect(find.text('Matching Heritage Sites'), findsNothing);

      // STEP 2: Run the full search with the real button.
      await tapVisible(tester, find.text('Search Any Location with AI'));
      await pumpUntilFound(
          tester, find.text('Search Could Not Be Completed'));
    }, () => osm);

    // ---- Observations ---------------------------------------------------
    final searchHasMatch =
        find.text('Matching Heritage Sites').evaluate().isNotEmpty ||
            find.text('Discovered Heritage Places').evaluate().isNotEmpty ||
            find.byType(app.HeritageSiteDetailScreen).evaluate().isNotEmpty;
    final messageCards =
        infoCardsTitled(tester, 'Search Could Not Be Completed');
    final noResultsVisible = messageCards.length == 1 &&
        messageCards.single.body.startsWith('Location not found.');

    printOnFailure('Message cards: ${messageCards.map((c) => c.body)}');

    // ---- Expected result -------------------------------------------------
    expect(searchHasMatch, isFalse,
        reason: 'CASE-023: no heritage site may be returned.');
    expect(noResultsVisible, isTrue,
        reason: 'CASE-023: a not-found / no-results message must be shown.');

    // Supporting evidence: the app really queried the location service with
    // the typed text, and the search button is usable again.
    expect(requests, hasLength(1));
    expect(requests.single.queryParameters['q'], kQuery);
    expect(find.text('Search Any Location with AI'), findsOneWidget);

    await unmountApp(tester);
  });
}
