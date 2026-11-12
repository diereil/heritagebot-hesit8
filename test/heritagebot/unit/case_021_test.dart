// HERITAGEBOT - TEST CASE 021
// Proponent: Reil Esdrelon
// Module: Tourist Heritage Access
// Unit: Home Page
// Description: Open tourist home page.
// Expected: Display available heritage features.
//
// TEST TYPE: Flutter widget test (host VM, no device / live Firebase).
//
// REAL CODE UNDER TEST (lib/, unmodified)
//   AuthGate -> MainShell(userRole: tourist) -> HomeScreen, including the
//   "Explore Heritage by Location" entry (opens HeritageSiteSearchScreen),
//   the feature cards and the tourist bottom navigation.
//
// MOCKED: Firebase platform layer only (signed-in dummy tourist).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:heritagebot/main.dart' as app;
import 'package:heritagebot/models/user_profile.dart';

import '../support/heritagebot_test_harness.dart';

const FakeAuthAccount kTourist = FakeAuthAccount(
  uid: 'case021-tourist-uid',
  email: 'case021.tourist@heritagebot.test',
  password: 'Case021Pass!',
  displayName: 'Case 021 Tourist',
);

late HeritageBotTestBackend backend;

void main() {
  setUpAll(() async {
    backend = await HeritageBotTestBackend.install(accounts: [kTourist]);
  });

  setUp(() async {
    await backend.reset();
    backend.seedTourist(kTourist);
  });

  testWidgets('CASE-021 - Open tourist home page: available heritage '
      'features are displayed', (WidgetTester tester) async {
    usePhoneSurface(tester);

    // STEP 1: Signed-in tourist opens the app.
    await signInBeforeLaunch(kTourist);
    await launchAuthGate(tester, until: app.MainShell);
    await pumpUntilFound(tester, find.byType(app.HomeScreen));

    // ---- Observations ---------------------------------------------------
    final shell = tester.widget<app.MainShell>(find.byType(app.MainShell));
    final navBar = find.byType(NavigationBar);
    final homeLoaded = shell.userRole == UserRoles.tourist &&
        tester.widget<NavigationBar>(navBar).selectedIndex == 0 &&
        find.byType(app.HomeScreen).evaluate().isNotEmpty;

    final featureTexts = <String>[
      'Explore Heritage by Location',
      en('welcomeHome'),
      en('aiStoryTitle'),
      en('liveMapTitle'),
      en('memoryJournalTitle'),
    ];
    final missingFeatures = <String>[];
    for (final text in featureTexts) {
      final finder = find.descendant(
          of: find.byType(app.HomeScreen), matching: find.text(text));
      if (finder.evaluate().isEmpty) {
        try {
          await scrollUntilBuilt(tester, finder, screen: app.HomeScreen);
        } catch (_) {
          missingFeatures.add(text);
        }
      }
    }
    final navLabels = [
      en('home'),
      en('geolocation'),
      'Stories',
      en('myJournal'),
      en('profile'),
    ];
    final missingNav = navLabels
        .where((label) => find
            .descendant(of: navBar, matching: find.text(label))
            .evaluate()
            .isEmpty)
        .toList();
    final heritageFeaturesVisible =
        missingFeatures.isEmpty && missingNav.isEmpty;

    printOnFailure('missing features: $missingFeatures, missing nav: '
        '$missingNav');

    // ---- Expected result -------------------------------------------------
    expect(homeLoaded, isTrue,
        reason: 'CASE-021: the tourist home page must be open.');
    expect(heritageFeaturesVisible, isTrue,
        reason: 'CASE-021: all heritage features must be displayed.');

    // Supporting evidence: the search feature on the home page really works.
    await scrollUntilBuilt(
        tester, find.text('Explore Heritage by Location'),
        screen: app.HomeScreen, delta: -250);
    await tapVisible(tester, find.text('Explore Heritage by Location'));
    await pumpUntilFound(tester, find.byType(app.HeritageSiteSearchScreen));
    expect(find.text('Search Heritage or Location'), findsOneWidget);

    await unmountApp(tester);
  });
}
