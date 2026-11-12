// HERITAGEBOT - TEST CASE 012
// Proponent: Reil Esdrelon
// Module: Authenticate User
// Unit: Email Link Verification
// Description: Open valid verification link.
// Expected: Verify email and update account.
//
// TEST TYPE: Flutter widget test (host VM, no device / live Firebase).
//
// REAL CODE UNDER TEST (lib/, unmodified)
//   Sign-up (LoginSignupScreen -> AuthService.signupWithEmail, which sends
//   the verification link) -> AuthGate -> EmailVerificationScreen ->
//   "I Already Verified" -> AuthService.reloadAndCheckVerified ->
//   AuthGate -> UserService profile -> MainShell (tourist).
//
// HOW THE LINK IS OPENED
// HeritageBot does not handle the link itself: the user taps it in Gmail and
// Firebase's hosted action page applies it (applyActionCode). The test does
// exactly that with the oobCode of the link the app caused Firebase to send.
//
// MOCKED: Firebase platform layer only (in-memory, no real e-mail).

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:heritagebot/main.dart' as app;
import 'package:heritagebot/models/user_profile.dart';

import '../support/heritagebot_test_harness.dart';

const String kFullName = 'Case 012 Tourist';
const String kEmail = 'case012.tourist@heritagebot.test';
const String kPassword = 'Case012Pass!';

late HeritageBotTestBackend backend;

Future<void> signUpThroughApp(WidgetTester tester) async {
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
}

void main() {
  setUpAll(() async {
    backend = await HeritageBotTestBackend.install();
  });

  setUp(() => backend.reset());

  testWidgets('CASE-012 - Open valid verification link: e-mail is verified '
      'and the account is activated', (WidgetTester tester) async {
    usePhoneSurface(tester);

    // STEP 1: Precondition - a new tourist signed up through the app and is
    // held on the verification screen.
    await signUpThroughApp(tester);
    expect(FirebaseAuth.instance.currentUser!.emailVerified, isFalse);
    expect(backend.auth.verificationLinks, hasLength(1));
    final link = backend.auth.verificationLinks.single;
    expect(link.email, kEmail);

    // STEP 2: The tourist opens the (valid) link from the inbox.
    await FirebaseAuth.instance.applyActionCode(link.oobCode);

    // STEP 3: Back in HeritageBot, tap the real "I Already Verified" button.
    await tapVisible(tester, find.text('I Already Verified'));
    await pumpUntilFound(tester, find.byType(app.MainShell));
    await pumpFor(tester, const Duration(milliseconds: 500));

    // ---- Observations ---------------------------------------------------
    final user = FirebaseAuth.instance.currentUser;
    final emailVerified = user?.emailVerified ?? false;
    final profile = backend.firestore.documents['users/${user?.uid}'];
    final shell = tester.widget<app.MainShell>(find.byType(app.MainShell));
    final accountActivated = profile?['accountStatus'] == 'active' &&
        shell.userRole == UserRoles.tourist &&
        find.byType(app.HomeScreen).evaluate().isNotEmpty &&
        find.byType(app.EmailVerificationScreen).evaluate().isEmpty;

    // ---- Expected result -------------------------------------------------
    expect(emailVerified, isTrue,
        reason: 'CASE-012: the e-mail must be verified after the link.');
    expect(accountActivated, isTrue,
        reason: 'CASE-012: the verified account must reach the tourist '
            'home page with an active profile.');

    // Supporting evidence.
    expect(user!.email, kEmail);
    expect(backend.auth.accountByEmail(kEmail)!.emailVerified, isTrue);
    expect(profile!['role'], UserRoles.tourist);
    expect(link.used, isTrue);

    await unmountApp(tester);
  });
}
