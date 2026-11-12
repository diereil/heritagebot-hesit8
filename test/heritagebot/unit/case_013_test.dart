// HERITAGEBOT - TEST CASE 013
// Proponent: Reil Esdrelon
// Module: Authenticate User
// Unit: Email Link Verification
// Description: Open expired verification link.
// Expected: Reject expired link and allow retry.
//
// TEST TYPE: Flutter widget test (host VM, no device / live Firebase).
//
// REAL CODE UNDER TEST (lib/, unmodified)
//   Sign-up -> EmailVerificationScreen -> "I Already Verified"
//   (AuthService.reloadAndCheckVerified) -> "Resend Verification Link"
//   (AuthService.resendEmailVerification) -> retry with the new link.
//
// SCOPE NOTE
// The expired-link message itself ("the action code has expired") is shown
// by Firebase's hosted action page, outside the app - here that is the
// FirebaseAuthException 'expired-action-code' returned by applyActionCode.
// Inside HeritageBot, the observable rejection is that the account stays
// unverified and the app shows "Email is not verified yet. Please check
// your Gmail." The test asserts exactly that app text; it does not claim
// the app shows an expired-specific message.
//
// MOCKED: Firebase platform layer only (link lifetime is expired by the
// test instead of waiting for real time to pass).

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:heritagebot/main.dart' as app;

import '../support/heritagebot_test_harness.dart';

const String kFullName = 'Case 013 Tourist';
const String kEmail = 'case013.tourist@heritagebot.test';
const String kPassword = 'Case013Pass!';

const String kNotVerifiedMessage =
    'Email is not verified yet. Please check your Gmail.';
const String kResentMessage =
    'Verification link sent again. Please check your Gmail.';

late HeritageBotTestBackend backend;

void main() {
  setUpAll(() async {
    backend = await HeritageBotTestBackend.install();
  });

  setUp(() => backend.reset());

  testWidgets('CASE-013 - Open expired verification link: link is rejected '
      'and the user can retry', (WidgetTester tester) async {
    usePhoneSurface(tester);

    // STEP 1: Precondition - sign up through the app.
    await launchAuthGate(tester, until: app.LoginSignupScreen);
    await tapVisible(tester, find.text(en('noAccount')));
    final fields = fieldsOf(app.LoginSignupScreen);
    await tester.enterText(fields.at(0), kFullName);
    await tester.enterText(fields.at(1), kEmail);
    await tester.enterText(fields.at(2), kPassword);
    await tester.enterText(fields.at(3), kPassword);
    await tester.pump();
    await tapVisible(
      tester,
      find.ancestor(
        of: find.byIcon(Icons.mark_email_read_rounded),
        matching: find.byType(ElevatedButton),
      ),
    );
    await pumpUntilFound(tester, find.byType(app.EmailVerificationScreen));
    await pumpFor(tester, const Duration(milliseconds: 500));
    final firstLink = backend.auth.verificationLinks.single;

    // STEP 2: The link expires before the tourist opens it.
    backend.auth.expireAllVerificationLinks();
    FirebaseAuthException? linkError;
    try {
      await FirebaseAuth.instance.applyActionCode(firstLink.oobCode);
    } on FirebaseAuthException catch (e) {
      linkError = e;
    }
    expect(linkError?.code, 'expired-action-code',
        reason: 'Firebase must reject the expired link.');

    // STEP 3: Back in the app, the tourist taps "I Already Verified".
    await tapVisible(tester, find.text('I Already Verified'));
    await pumpUntilFound(tester, snackBarWithText(kNotVerifiedMessage));
    await pumpFor(tester, const Duration(milliseconds: 500));

    // ---- Observations after the expired link -----------------------------
    final emailVerified =
        FirebaseAuth.instance.currentUser?.emailVerified ?? false;
    final notVerifiedErrorVisible =
        snackBarWithText(kNotVerifiedMessage).evaluate().isNotEmpty;

    // ---- Expected result part 1: expired link rejected ---------------------
    expect(emailVerified, isFalse,
        reason: 'CASE-013: the expired link must not verify the account.');
    expect(notVerifiedErrorVisible, isTrue,
        reason: 'CASE-013: the app must tell the user the e-mail is still '
            'not verified.');
    expect(find.byType(app.EmailVerificationScreen), findsOneWidget);
    expect(find.byType(app.MainShell), findsNothing,
        reason: 'An unverified account must not enter the app.');

    // ---- Expected result part 2: retry is allowed -------------------------
    await tester.pump(const Duration(seconds: 5)); // let SnackBar time out
    await tester.pumpAndSettle();
    await tapVisible(tester, find.text('Resend Verification Link'));
    await pumpUntilFound(tester, snackBarWithText(kResentMessage));

    expect(backend.auth.verificationLinks, hasLength(2),
        reason: 'CASE-013: the app must send a new verification link.');
    final newLink = backend.auth.verificationLinks.last;
    expect(newLink.email, kEmail);
    expect(newLink.isExpired, isFalse);

    // The retry succeeds with the new link.
    await FirebaseAuth.instance.applyActionCode(newLink.oobCode);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tapVisible(tester, find.text('I Already Verified'));
    await pumpUntilFound(tester, find.byType(app.MainShell));
    expect(FirebaseAuth.instance.currentUser!.emailVerified, isTrue);

    await unmountApp(tester);
  });
}
