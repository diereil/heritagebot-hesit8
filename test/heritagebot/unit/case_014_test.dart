// HERITAGEBOT - TEST CASE 014
// Proponent: Reil Esdrelon
// Module: Authenticate User
// Unit: Forgot Password
// Description: Request reset for registered email.
// Expected: Send password reset instructions.
//
// TEST TYPE: Flutter widget test (host VM, no device / live Firebase).
//
// REAL CODE UNDER TEST (lib/, unmodified)
//   LoginSignupScreen "Forgot Password?" -> forgotPassword() validation ->
//   AuthService.sendPasswordResetEmail -> FirebaseAuth ->
//   success SnackBar t('resetSent').
//
// MOCKED: Firebase platform layer only (records the reset request instead
// of sending a real e-mail).

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:heritagebot/main.dart' as app;

import '../support/heritagebot_test_harness.dart';

const FakeAuthAccount kRegistered = FakeAuthAccount(
  uid: 'case014-tourist-uid',
  email: 'case014.tourist@heritagebot.test',
  password: 'Case014Pass!',
  displayName: 'Case 014 Tourist',
);

late HeritageBotTestBackend backend;

void main() {
  setUpAll(() async {
    backend = await HeritageBotTestBackend.install(accounts: [kRegistered]);
  });

  setUp(() async {
    await backend.reset();
    backend.seedTourist(kRegistered);
  });

  testWidgets('CASE-014 - Forgot password for a registered e-mail: reset '
      'instructions are sent', (WidgetTester tester) async {
    usePhoneSurface(tester);

    await launchAuthGate(tester, until: app.LoginSignupScreen);

    // STEP 1: Enter the registered e-mail in the real login form.
    await tester.enterText(fieldsOf(app.LoginSignupScreen).at(0),
        kRegistered.email);
    await tester.pump();

    // STEP 2: Tap the real "Forgot Password?" button.
    await tapVisible(tester, find.text(en('forgotPassword')));
    await pumpUntilFound(tester, find.byType(SnackBar));

    // ---- Observations ---------------------------------------------------
    final resetRequested =
        backend.auth.passwordResetRequests.contains(kRegistered.email);
    final resetInstructionsSent =
        snackBarWithText(en('resetSent')).evaluate().isNotEmpty;

    // ---- Expected result -------------------------------------------------
    expect(resetRequested, isTrue,
        reason: 'CASE-014: the app must ask Firebase to send the reset e-mail.');
    expect(backend.auth.passwordResetRequests, [kRegistered.email],
        reason: 'Exactly one reset request for the entered e-mail.');
    expect(resetInstructionsSent, isTrue,
        reason: 'CASE-014: "${en('resetSent')}" must be confirmed to the user.');

    // Supporting evidence: no sign-in happened, password unchanged.
    expect(FirebaseAuth.instance.currentUser, isNull);
    expect(backend.auth.signInCalls, isEmpty);
    expect(backend.auth.accountByEmail(kRegistered.email)!.password,
        kRegistered.password);
    expect(find.byType(app.LoginSignupScreen), findsOneWidget);

    await unmountApp(tester);
  });
}
