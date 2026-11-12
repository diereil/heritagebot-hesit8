// HERITAGEBOT - TEST CASE 019
// Proponent: Reil Esdrelon
// Module: Authenticate User
// Unit: Continue with Gmail
// Description: Cancel Google sign-in.
// Expected: Return safely without login.
//
// TEST TYPE: Flutter widget test (host VM, no device / live Firebase).
//
// REAL CODE UNDER TEST (lib/, unmodified)
//   LoginSignupScreen.googleLogin() -> AuthService.signInWithGoogle ->
//   GoogleSignIn.instance.authenticate() throws GoogleSignInException
//   (code: canceled) -> AuthService rethrows as Exception('Google login
//   error: ...') -> googleLogin() shows it and re-enables the form.
//
// MOCKED: Google account picker (the user dismisses it) and Firebase
// platform layer only.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:heritagebot/main.dart' as app;

import '../support/heritagebot_test_harness.dart';

late HeritageBotTestBackend backend;

void main() {
  setUpAll(() async {
    backend = await HeritageBotTestBackend.install();
  });

  setUp(() async {
    await backend.reset();
    backend.google
      ..outcome = FakeGooglePickerOutcome.cancel
      ..authenticateCalls = 0;
  });

  testWidgets('CASE-019 - Cancel Google sign-in: app returns safely to the '
      'login screen without logging in', (WidgetTester tester) async {
    usePhoneSurface(tester);

    expect(FirebaseAuth.instance.currentUser, isNull);
    await launchAuthGate(tester, until: app.LoginSignupScreen);

    // STEP 1: Tap "Continue with Gmail", then cancel the account picker.
    await tapVisible(tester, find.text(en('continueWithGmail')));
    await pumpUntilFound(tester, find.byType(SnackBar));
    await pumpFor(tester, const Duration(seconds: 1));

    // ---- Observations ---------------------------------------------------
    final authenticated = FirebaseAuth.instance.currentUser != null;
    final loginScreenVisible =
        find.byType(app.LoginSignupScreen).evaluate().isNotEmpty;

    // ---- Expected result -------------------------------------------------
    expect(authenticated, isFalse,
        reason: 'CASE-019: cancelling must not sign anybody in.');
    expect(loginScreenVisible, isTrue,
        reason: 'CASE-019: the user must stay on the login screen.');

    // Supporting evidence: the picker was opened, no Firebase credential
    // was sent, the app did not crash and the buttons work again.
    expect(backend.google.authenticateCalls, 1);
    expect(backend.auth.credentialSignInCalls, isEmpty);
    expect(
      find.descendant(
        of: find.byType(SnackBar),
        matching: find.textContaining('Google login error'),
      ),
      findsOneWidget,
      reason: 'The cancellation is reported to the user.',
    );
    expect(find.byType(app.MainShell), findsNothing);
    expect(find.byType(app.RoleSetupScreen), findsNothing);
    final gmailButton = find.ancestor(
      of: find.text(en('continueWithGmail')),
      matching: find.byType(OutlinedButton),
    );
    expect(tester.widget<OutlinedButton>(gmailButton).onPressed, isNotNull,
        reason: 'Continue with Gmail must be enabled again for a retry.');
    final loginButton = find.ancestor(
      of: find.byIcon(Icons.login_rounded),
      matching: find.byType(ElevatedButton),
    );
    expect(tester.widget<ElevatedButton>(loginButton).onPressed, isNotNull);

    await unmountApp(tester);
  });
}
