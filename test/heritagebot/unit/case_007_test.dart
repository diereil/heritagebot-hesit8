// HERITAGEBOT - TEST CASE 007
// Proponent: Reil Esdrelon
// Module: Authenticate User
// Unit: Sign Up
// Description: Valid new tourist details.
// Expected: Create tourist account.
//
// TEST TYPE: Flutter widget test (host VM, no device / live Firebase).
//
// REAL CODE UNDER TEST (lib/, unmodified)
//   AuthGate -> LoginSignupScreen (sign-up mode, real fields, role selector)
//   -> AuthService.signupWithEmail (createUser, updateDisplayName,
//      sendEmailVerification) -> UserService.savePublicProfile (users/{uid})
//   -> LanguageService.savePreferredLanguageCode -> AuthGate routing to
//      EmailVerificationScreen for the new, unverified password account.
//
// MOCKED: Firebase Auth / Firestore platform layer only
// (support/fake_firebase_platform.dart). The new account exists only in
// memory; no real credentials are used.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:heritagebot/main.dart' as app;
import 'package:heritagebot/models/user_profile.dart';

import '../support/heritagebot_test_harness.dart';

const String kFullName = 'Case 007 New Tourist';
const String kEmail = 'case007.newtourist@heritagebot.test';
const String kPassword = 'Case007Pass!';

late HeritageBotTestBackend backend;

void main() {
  setUpAll(() async {
    backend = await HeritageBotTestBackend.install(); // no accounts exist yet
  });

  setUp(() => backend.reset());

  testWidgets('CASE-007 - Valid new tourist details: tourist account is '
      'created', (WidgetTester tester) async {
    usePhoneSurface(tester);

    // STEP 1: Preconditions - logged out and the e-mail is not registered.
    expect(FirebaseAuth.instance.currentUser, isNull);
    expect(backend.auth.accountByEmail(kEmail), isNull);

    // STEP 2: Open the real app entry (AuthGate -> LoginSignupScreen).
    await tester.pumpWidget(const MaterialApp(home: app.AuthGate()));
    await pumpUntilFound(tester, find.byType(app.LoginSignupScreen));

    // STEP 3: Switch to sign-up mode with the real toggle button.
    await tapVisible(tester, find.text(en('noAccount')));
    final fields = fieldsOf(app.LoginSignupScreen);
    expect(fields, findsNWidgets(4),
        reason: 'Sign-up shows full name, email, password, confirm password.');

    // STEP 4: Enter valid new tourist details. Account Type is left on the
    // real selector's "Tourist" option, which is verified on screen.
    await tester.enterText(fields.at(0), kFullName);
    await tester.enterText(fields.at(1), kEmail);
    await tester.enterText(fields.at(2), kPassword);
    await tester.enterText(fields.at(3), kPassword);
    await tester.pump();
    expect(
      find.descendant(
        of: find.byType(DropdownButtonFormField<String>).first,
        matching: find.text('Tourist'),
      ),
      findsOneWidget,
      reason: 'Account Type selector must show Tourist.',
    );

    // STEP 5: Tap the real "Create Account" button.
    await tapVisible(
      tester,
      find.ancestor(
        of: find.byIcon(Icons.mark_email_read_rounded),
        matching: find.byType(ElevatedButton),
      ),
    );

    // STEP 6: The app routes the new (unverified) account to verification.
    await pumpUntilFound(tester, find.byType(app.EmailVerificationScreen));
    await pumpFor(tester, const Duration(milliseconds: 500));

    // ---- Observations derived from real system state -------------------
    final created = backend.auth.accountByEmail(kEmail);
    final profileDoc = created == null
        ? null
        : backend.firestore.documents['users/${created.uid}'];

    final accountCreated = created != null && profileDoc != null;
    final accountRole = profileDoc?['role'];

    // ---- Expected result: tourist account created ------------------------
    expect(backend.auth.createUserCalls, [kEmail],
        reason: 'CASE-007: the app must call Firebase createUser once.');
    expect(accountCreated, isTrue,
        reason: 'CASE-007: Firebase account and users/{uid} profile must exist.');
    expect(accountRole, UserRoles.tourist,
        reason: 'CASE-007: stored role must be tourist.');

    // Supporting evidence that the account is complete and correct.
    expect(created!.password, kPassword);
    expect(created.displayName, kFullName);
    expect(created.emailVerified, isFalse);
    expect(profileDoc!['fullName'], kFullName);
    expect(profileDoc['email'], kEmail);
    expect(profileDoc['accountStatus'], 'active');
    expect(backend.auth.verificationLinks.map((l) => l.email), [kEmail],
        reason: 'A verification link must be sent to the new tourist.');
    expect(FirebaseAuth.instance.currentUser?.uid, created.uid);
    expect(find.text('A free verification link was sent to\n$kEmail'),
        findsOneWidget);

    await unmountApp(tester);
  });
}
