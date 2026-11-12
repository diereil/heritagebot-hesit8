// HERITAGEBOT - TEST CASE 020
// Proponent: Reil Esdrelon
// Module: Authenticate User
// Unit: Logout
// Description: Select logout.
// Expected: End session and return to login.
//
// TEST TYPE: Flutter widget test (host VM, no device / live Firebase).
//
// REAL CODE UNDER TEST (lib/, unmodified)
//   AuthGate -> MainShell -> Profile tab -> "Logout" ->
//   ProfileScreen.logout -> AuthService.logout (GoogleSignIn.signOut,
//   FacebookAuth.logOut, FirebaseAuth.signOut) -> AuthGate stream ->
//   LoginSignupScreen.
//
// MOCKED: Firebase platform layer, Google Sign-In platform and the Facebook
// SDK method channel (all record the sign-out calls).

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:heritagebot/main.dart' as app;

import '../support/heritagebot_test_harness.dart';

const FakeAuthAccount kTourist = FakeAuthAccount(
  uid: 'case020-tourist-uid',
  email: 'case020.tourist@heritagebot.test',
  password: 'Case020Pass!',
  displayName: 'Case 020 Tourist',
);

late HeritageBotTestBackend backend;

void main() {
  setUpAll(() async {
    backend = await HeritageBotTestBackend.install(accounts: [kTourist]);
  });

  setUp(() async {
    await backend.reset();
    backend.seedTourist(kTourist);
    backend.google.signOutCalls = 0;
  });

  testWidgets('CASE-020 - Select logout: session ends and the login screen '
      'returns', (WidgetTester tester) async {
    usePhoneSurface(tester);

    // STEP 1: Precondition - tourist signed in on the Tourist Home Page.
    await signInBeforeLaunch(kTourist);
    await launchAuthGate(tester, until: app.MainShell);
    expect(FirebaseAuth.instance.currentUser?.uid, kTourist.uid);

    // STEP 2: Profile tab -> real "Logout" button.
    await tapNavDestination(tester, en('profile'));
    final logoutButton = find.ancestor(
      of: find.text(en('logout')),
      matching: find.byType(ElevatedButton),
    );
    await pumpUntilFound(tester, logoutButton);
    await tapVisible(tester, logoutButton);

    // STEP 3: AuthGate must return to the login screen.
    await pumpUntilFound(tester, find.byType(app.LoginSignupScreen));
    await pumpFor(tester, const Duration(milliseconds: 500));

    // ---- Observations ---------------------------------------------------
    final sessionActive = FirebaseAuth.instance.currentUser != null;
    final loginScreenVisible =
        find.byType(app.LoginSignupScreen).evaluate().isNotEmpty;

    // ---- Expected result -------------------------------------------------
    expect(sessionActive, isFalse,
        reason: 'CASE-020: the Firebase session must end.');
    expect(loginScreenVisible, isTrue,
        reason: 'CASE-020: the login screen must be shown.');

    // Supporting evidence: every provider session was closed and no part of
    // the signed-in interface remains.
    expect(backend.google.signOutCalls, greaterThanOrEqualTo(1),
        reason: 'Google session must be signed out.');
    expect(backend.channels.facebookCalls.map((c) => c.method),
        contains('logOut'),
        reason: 'Facebook session must be logged out.');
    expect(find.byType(app.MainShell), findsNothing);
    expect(find.byType(app.ProfileScreen), findsNothing);
    expect(find.byType(app.HomeScreen), findsNothing);

    await unmountApp(tester);
  });
}
