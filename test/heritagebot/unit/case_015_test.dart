// HERITAGEBOT - TEST CASE 015
// Proponent: Reil Esdrelon
// Module: Authenticate User
// Unit: Forgot Password
// Description: Submit malformed email ('invalid-at-symbol').
// Expected: Display email validation error.
//
// TEST TYPE: Flutter widget test (host VM, no device / live Firebase).
//
// REAL CODE UNDER TEST (lib/, unmodified)
//   LoginSignupScreen.forgotPassword():
//   `if (!email.contains('@') || !email.contains('.'))
//        showMessage(t('validEmail'))`
//   which must stop the request before it reaches Firebase.
//
// MOCKED: Firebase platform layer only (records whether a reset request is
// sent at all).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:heritagebot/main.dart' as app;

import '../support/heritagebot_test_harness.dart';

const String kMalformedEmail = 'invalid-at-symbol';

late HeritageBotTestBackend backend;

void main() {
  setUpAll(() async {
    backend = await HeritageBotTestBackend.install();
  });

  setUp(() => backend.reset());

  testWidgets('CASE-015 - Forgot password with malformed e-mail: e-mail '
      'validation error is shown', (WidgetTester tester) async {
    usePhoneSurface(tester);

    await launchAuthGate(tester, until: app.LoginSignupScreen);

    // STEP 1: Enter the malformed e-mail.
    await tester.enterText(
        fieldsOf(app.LoginSignupScreen).at(0), kMalformedEmail);
    await tester.pump();

    // STEP 2: Tap the real "Forgot Password?" button.
    await tapVisible(tester, find.text(en('forgotPassword')));
    await pumpUntilFound(tester, find.byType(SnackBar));
    await pumpFor(tester, const Duration(milliseconds: 500));

    // ---- Observations ---------------------------------------------------
    final resetRequested = backend.auth.passwordResetRequests.isNotEmpty;
    final emailErrorVisible =
        snackBarWithText(en('validEmail')).evaluate().isNotEmpty;

    // ---- Expected result -------------------------------------------------
    expect(resetRequested, isFalse,
        reason: 'CASE-015: no reset request may be sent for a malformed '
            'e-mail.');
    expect(emailErrorVisible, isTrue,
        reason: 'CASE-015: "${en('validEmail')}" must be shown.');

    // Supporting evidence.
    expect(snackBarWithText(en('resetSent')), findsNothing);
    expect(find.byType(app.LoginSignupScreen), findsOneWidget);

    await unmountApp(tester);
  });
}
