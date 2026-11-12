// HERITAGEBOT - TEST CASE 064
// Proponent: James Stephen O. Ramos
// Module: User Profile Management
// Unit: Manage Profile
// Description: Open profile page.
// Expected: Display account profile.
//
// TEST TYPE: Flutter widget test (host VM, no device / live Firebase).
//
// REAL CODE UNDER TEST (lib/, unmodified)
//   AuthGate -> MainShell -> "Profile" destination -> ProfileScreen
//   (FirebaseAuth.currentUser display name / email,
//   UserService.getUserProfile role badge, Change Password, Logout,
//   View Bookmarked Sites, Language Settings).
//
// FIXTURE (fixtureId = CASE-064): a signed-in, verified Tourist account.
// A second registered account exists so the test can tell whether the
// profile shown is the signed-in one.
//
// MOCKED: Firebase platform layer only (in-memory Firestore / Auth).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:heritagebot/main.dart' as app;

import '../support/contributor_flow.dart';
import '../support/heritagebot_fixtures.dart';

const FakeAuthAccount kTourist = FakeAuthAccount(
  uid: 'case064-tourist-uid',
  email: 'case064.tourist@heritagebot.test',
  password: 'Case064Pass!',
  displayName: 'Andrea Villanueva',
);
const FakeAuthAccount kOtherUser = FakeAuthAccount(
  uid: 'case064-other-uid',
  email: 'case064.other@heritagebot.test',
  password: 'Case064Other!',
  displayName: 'Other HeritageBot User',
);

late HeritageBotTestBackend backend;

void main() {
  setUpAll(() async {
    backend = await HeritageBotTestBackend.install(
      accounts: [kTourist, kOtherUser],
    );
  });

  setUp(() async {
    await backend.reset();
    backend.seedTourist(kTourist);
    backend.seedTourist(kOtherUser);
  });

  testWidgets('CASE-064 - Open profile page', (WidgetTester tester) async {
    usePhoneSurface(tester);

    await signInBeforeLaunch(kTourist);
    await launchAuthGate(tester, until: app.MainShell);

    // STEP: tap the "Profile" destination.
    await openProfileTab(tester);
    await pumpUntilFound(
      tester,
      find.descendant(of: profileScreen, matching: find.text('Role: Tourist')),
    );

    // ---- Observations ---------------------------------------------------
    final texts = profileTexts(tester);
    final appBarTitle = find.descendant(
      of: find.descendant(of: profileScreen, matching: find.byType(AppBar)),
      matching: find.text(en('profile')),
    );
    final profileOnScreen = tester
        .getRect(
          find.descendant(
            of: profileScreen,
            matching: find.text(kTourist.email),
          ),
        )
        .overlaps(tester.getRect(profileScreen));

    final observed = <String, Object?>{
      'profileVisible':
          appBarTitle.evaluate().isNotEmpty &&
          profileOnScreen &&
          texts.contains(en('logout')) &&
          texts.contains('View Bookmarked Sites') &&
          texts.contains(en('languageSettings')),
      'correctAccountLoaded':
          texts.contains(kTourist.displayName) &&
          texts.contains(kTourist.email) &&
          texts.contains('Role: Tourist') &&
          !texts.contains(kOtherUser.displayName) &&
          !texts.contains(kOtherUser.email),
    };
    printOnFailure('CASE-064 observed: $observed\nprofileTexts=$texts');

    // ---- Expected result (unchanged from the original CASE-064) ---------
    expect(
      observed['profileVisible'],
      equals(true),
      reason: 'CASE-064: profileVisible does not match the real system result',
    );
    expect(
      observed['correctAccountLoaded'],
      equals(true),
      reason:
          'CASE-064: correctAccountLoaded does not match the real system result',
    );

    await unmountApp(tester);
  });
}
