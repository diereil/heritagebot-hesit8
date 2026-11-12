// HERITAGEBOT - TEST CASE 009
// Proponent: Reil Esdrelon
// Module: Authenticate User
// Unit: Sign Up
// Description: Invalid or weak password ('123').
// Expected: Show password validation error.
//
// TEST TYPE: Flutter widget test (host VM, no device / live Firebase).
//
// REAL CODE UNDER TEST (lib/, unmodified)
//   LoginSignupScreen.submitEmail - local validation
//   `if (password.length < 6) showMessage(t('passwordLength'))`
//   which must stop the sign-up BEFORE anything is sent to Firebase.
//
// MOCKED: Firebase platform layer only (records whether createUser is
// called at all).

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:heritagebot/main.dart' as app;

import '../support/heritagebot_test_harness.dart';

const String kEmail = 'case009.weakpassword@heritagebot.test';
const String kWeakPassword = '123';

late HeritageBotTestBackend backend;

void main() {
  setUpAll(() async {
    backend = await HeritageBotTestBackend.install();
  });

  setUp(() => backend.reset());

  testWidgets('CASE-009 - Weak password "123": password validation error is '
      'shown and no account is created', (WidgetTester tester) async {
    usePhoneSurface(tester);

    expect(FirebaseAuth.instance.currentUser, isNull);

    // STEP 1: Open the real sign-up form.
    await launchAuthGate(tester, until: app.LoginSignupScreen);
    await tapVisible(tester, find.text(en('noAccount')));
    final fields = fieldsOf(app.LoginSignupScreen);
    expect(fields, findsNWidgets(4));

    // STEP 2: Valid name/e-mail, weak password in both password fields.
    await tester.enterText(fields.at(0), 'Case 009 Tourist');
    await tester.enterText(fields.at(1), kEmail);
    await tester.enterText(fields.at(2), kWeakPassword);
    await tester.enterText(fields.at(3), kWeakPassword);
    await tester.pump();

    // STEP 3: Tap the real "Create Account" button.
    await tapVisible(
      tester,
      find.ancestor(
        of: find.byIcon(Icons.mark_email_read_rounded),
        matching: find.byType(ElevatedButton),
      ),
    );
    await pumpUntilFound(tester, find.byType(SnackBar));
    await pumpFor(tester, const Duration(milliseconds: 500));

    // ---- Observations ---------------------------------------------------
    final accountCreated = backend.auth.accountByEmail(kEmail) != null ||
        backend.firestore.documents.isNotEmpty;
    final passwordValidationErrorVisible =
        snackBarWithText(en('passwordLength')).evaluate().isNotEmpty;

    // ---- Expected result -------------------------------------------------
    expect(accountCreated, isFalse,
        reason: 'CASE-009: no account may be created with a weak password.');
    expect(passwordValidationErrorVisible, isTrue,
        reason: 'CASE-009: "${en('passwordLength')}" must be shown.');

    // Supporting evidence: validation happened locally, before Firebase.
    expect(backend.auth.createUserCalls, isEmpty,
        reason: 'The weak password must not be sent to Firebase.');
    expect(FirebaseAuth.instance.currentUser, isNull);
    expect(find.byType(app.LoginSignupScreen), findsOneWidget);
    expect(find.byType(app.EmailVerificationScreen), findsNothing);

    await unmountApp(tester);
  });
}
