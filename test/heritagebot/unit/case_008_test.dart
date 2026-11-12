// HERITAGEBOT - TEST CASE 008
// Proponent: Reil Esdrelon
// Module: Authenticate User
// Unit: Sign Up
// Description: Duplicate email address.
// Expected: Reject duplicate account.
//
// TEST TYPE: Flutter widget test (host VM, no device / live Firebase).
//
// REAL CODE UNDER TEST (lib/, unmodified)
//   LoginSignupScreen sign-up form -> AuthService.signupWithEmail ->
//   FirebaseAuth.createUserWithEmailAndPassword; the screen's
//   FirebaseAuthException handler shows e.message in a SnackBar.
//
// MOCKED: Firebase platform layer only. The in-memory auth backend already
// holds an account for the e-mail; like Firebase it answers a second
// createUser with code 'email-already-in-use'.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:heritagebot/main.dart' as app;

import '../support/heritagebot_test_harness.dart';

const FakeAuthAccount kRegistered = FakeAuthAccount(
  uid: 'case008-registered-uid',
  email: 'case008.registered@heritagebot.test',
  password: 'Case008Existing!',
  displayName: 'Case 008 Existing Tourist',
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

  testWidgets('CASE-008 - Duplicate email address: duplicate account is '
      'rejected', (WidgetTester tester) async {
    usePhoneSurface(tester);

    // STEP 1: Preconditions - logged out, e-mail already registered.
    expect(FirebaseAuth.instance.currentUser, isNull);
    expect(backend.auth.accountCount, 1);
    final profileBefore =
        Map<String, dynamic>.of(backend.firestore.documents['users/${kRegistered.uid}']!);

    // STEP 2: Open the real sign-up form.
    await launchAuthGate(tester, until: app.LoginSignupScreen);
    await tapVisible(tester, find.text(en('noAccount')));
    final fields = fieldsOf(app.LoginSignupScreen);
    expect(fields, findsNWidgets(4));

    // STEP 3: Enter otherwise-valid details with the REGISTERED e-mail.
    await tester.enterText(fields.at(0), 'Case 008 Duplicate Attempt');
    await tester.enterText(fields.at(1), kRegistered.email);
    await tester.enterText(fields.at(2), 'AnotherPass123!');
    await tester.enterText(fields.at(3), 'AnotherPass123!');
    await tester.pump();

    // STEP 4: Tap the real "Create Account" button.
    final createButton = find.ancestor(
      of: find.byIcon(Icons.mark_email_read_rounded),
      matching: find.byType(ElevatedButton),
    );
    await tapVisible(tester, createButton);

    // STEP 5: Wait for the app's error SnackBar.
    await pumpUntilFound(tester, find.byType(SnackBar));
    await pumpFor(tester, const Duration(milliseconds: 500));

    // ---- Observations derived from real system state -------------------
    final accountCreated = backend.auth.accountCount != 1 ||
        FirebaseAuth.instance.currentUser != null;
    final duplicateEmailErrorVisible = snackBarWithText(
      'The email address is already in use by another account.',
    ).evaluate().isNotEmpty;

    // ---- Expected result: duplicate account rejected ---------------------
    expect(backend.auth.createUserCalls, [kRegistered.email],
        reason: 'CASE-008: the sign-up request must really reach Firebase.');
    expect(accountCreated, isFalse,
        reason: 'CASE-008: no second account may be created.');
    expect(duplicateEmailErrorVisible, isTrue,
        reason: 'CASE-008: the duplicate-email error must be shown.');

    // Supporting evidence: existing data untouched, user stays on sign-up.
    expect(backend.firestore.documents.keys, ['users/${kRegistered.uid}'],
        reason: 'No new profile document may be written.');
    expect(backend.firestore.documents['users/${kRegistered.uid}'],
        profileBefore);
    expect(backend.auth.accountByEmail(kRegistered.email)!.password,
        kRegistered.password,
        reason: 'The existing account must not be overwritten.');
    expect(backend.auth.verificationLinks, isEmpty);
    expect(find.byType(app.LoginSignupScreen), findsOneWidget);
    expect(find.byType(app.EmailVerificationScreen), findsNothing);
    expect(find.byType(app.MainShell), findsNothing);
    expect(tester.widget<ElevatedButton>(createButton).onPressed, isNotNull,
        reason: 'The form must be usable again after the rejection.');

    await unmountApp(tester);
  });
}
