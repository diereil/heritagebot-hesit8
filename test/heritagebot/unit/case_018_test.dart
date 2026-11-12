// HERITAGEBOT - TEST CASE 018
// Proponent: Reil Esdrelon
// Module: Authenticate User
// Unit: Continue with Gmail
// Description: Complete valid Google sign-in.
// Expected: Authenticate and open correct role page.
//
// TEST TYPE: Flutter widget test (host VM, no device / live Firebase).
//
// REAL CODE UNDER TEST (lib/, unmodified)
//   LoginSignupScreen "Continue with Gmail" -> googleLogin() ->
//   AuthService.signInWithGoogle (GoogleSignIn.instance.signOut/authenticate,
//   GoogleAuthProvider.credential, FirebaseAuth.signInWithCredential) ->
//   AuthGate (no e-mail verification for Google accounts) ->
//   UserService.getUserProfile -> role-based routing.
//
// FIXTURE: a returning Google user whose stored role is Community
// Contributor (a non-default role, so reaching the contributor interface
// proves role routing, not the tourist fallback).
//
// MOCKED: Google account picker (GoogleSignInPlatform) and Firebase platform
// layer only. No real Google account is used.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';

import 'package:heritagebot/main.dart' as app;
import 'package:heritagebot/models/user_profile.dart';

import '../support/heritagebot_test_harness.dart';

const FakeAuthAccount kGoogleUser = FakeAuthAccount(
  uid: 'case018-google-uid',
  email: 'case018.googleuser@heritagebot.test',
  password: '',
  displayName: 'Case 018 Google Contributor',
  providerId: 'google.com',
);
const String kIdToken = 'case018-google-id-token';

late HeritageBotTestBackend backend;

void main() {
  setUpAll(() async {
    backend = await HeritageBotTestBackend.install(accounts: [kGoogleUser]);
    backend.auth.registerOAuthIdToken(kIdToken, kGoogleUser.uid);
  });

  setUp(() async {
    await backend.reset();
    backend.seedProfile(
      uid: kGoogleUser.uid,
      email: kGoogleUser.email,
      fullName: kGoogleUser.displayName!,
      role: UserRoles.communityContributor,
    );
    backend.google
      ..outcome = FakeGooglePickerOutcome.chooseAccount
      ..account = const GoogleSignInUserData(
        email: 'case018.googleuser@heritagebot.test',
        id: 'case018-google-subject',
        displayName: 'Case 018 Google Contributor',
      )
      ..idToken = kIdToken
      ..authenticateCalls = 0;
  });

  testWidgets('CASE-018 - Valid Google sign-in: user is authenticated and '
      'the correct role page opens', (WidgetTester tester) async {
    usePhoneSurface(tester);

    expect(FirebaseAuth.instance.currentUser, isNull);
    await launchAuthGate(tester, until: app.LoginSignupScreen);

    // STEP 1: Tap the real "Continue with Gmail" button; the user picks
    // their Google account in the (fake) picker.
    await tapVisible(tester, find.text(en('continueWithGmail')));

    // STEP 2: Wait for role-based routing.
    await pumpUntilFound(tester, find.byType(app.MainShell));
    await pumpFor(tester, const Duration(milliseconds: 500));

    // ---- Observations ---------------------------------------------------
    final user = FirebaseAuth.instance.currentUser;
    final authenticated = user != null &&
        user.uid == kGoogleUser.uid &&
        user.providerData.any((p) => p.providerId == 'google.com');
    final storedRole =
        backend.firestore.documents['users/${kGoogleUser.uid}']!['role'];
    final shell = tester.widget<app.MainShell>(find.byType(app.MainShell));
    final correctRoleScreenOpened = shell.userRole == storedRole &&
        find
            .descendant(
                of: find.byType(NavigationBar),
                matching: find.text('Contribute'))
            .evaluate()
            .isNotEmpty;

    // ---- Expected result -------------------------------------------------
    expect(authenticated, isTrue,
        reason: 'CASE-018: Firebase must sign in the Google account.');
    expect(correctRoleScreenOpened, isTrue,
        reason: 'CASE-018: the Community Contributor interface must open.');

    // Supporting evidence.
    expect(backend.google.authenticateCalls, 1,
        reason: 'The Google account picker must be opened once.');
    expect(backend.auth.credentialSignInCalls, ['google.com']);
    expect(backend.auth.signInCalls, isEmpty,
        reason: 'No e-mail/password sign-in is involved.');
    expect(find.byType(app.EmailVerificationScreen), findsNothing,
        reason: 'Google accounts do not need e-mail-link verification.');
    expect(find.byType(app.LoginSignupScreen), findsNothing);
    expect(find.byType(app.RoleSetupScreen), findsNothing);
    expect(find.byType(app.AdminShell), findsNothing);

    await unmountApp(tester);
  });
}
