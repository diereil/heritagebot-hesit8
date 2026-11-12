// HERITAGEBOT - TEST CASE 005
// Proponent: Reil Esdrelon
// Module: Authenticate User
// Unit: Login
// Description: Tourist enters an incorrect password.
// Expected: The system rejects the login and displays an appropriate
//           authentication error.
//
// TEST TYPE
// Flutter widget test (package:flutter_test). Runs on the host VM through
// `flutter test` - no Android device, emulator, or live Firebase project.
//
// WHAT IS REAL (unmodified production code from lib/)
//   * AuthGate                   - auth-state routing (must stay on login)
//   * LoginSignupScreen          - real text fields, validation, Login button,
//                                  FirebaseAuthException handling, SnackBar
//   * AuthService.loginWithEmail - real call into FirebaseAuth
//
// WHAT IS MOCKED (test/heritagebot/support/fake_firebase_platform.dart)
//   * Firebase native platform layer only (same fake used by CASE-004).
//     It holds one verified dummy tourist account. When the password does
//     not match, it throws FirebaseAuthException(code: 'invalid-credential'),
//     which is what current Firebase Authentication returns for a wrong
//     password when email-enumeration protection is enabled (the default).
//   * No real credentials are used. The account below exists only in memory.
//
// HOW THE APP HANDLES THE ERROR (lib/main.dart, _LoginSignupScreenState):
//   on FirebaseAuthException catch (e) { showMessage(e.message ?? t('authError')); }
// so the message reported by Firebase is shown to the tourist in a SnackBar.

// ignore_for_file: depend_on_referenced_packages

import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:heritagebot/main.dart' as app;
import 'package:heritagebot/models/user_profile.dart';

import '../support/fake_firebase_platform.dart';

// Dummy in-memory test account (NOT a real Firebase user).
const String kTouristUid = 'case005-tourist-uid';
const String kTouristEmail = 'case005.tourist@heritagebot.test';
const String kCorrectPassword = 'Case005Pass!';

// Incorrect password. At least 6 characters so it passes the app's local
// length validation and is genuinely sent to Firebase for verification.
const String kIncorrectPassword = 'WrongPass999!';

late FakeFirebaseAuthPlatform fakeAuth;
late FakeFirebaseFirestorePlatform fakeFirestore;

/// Pumps frames (letting real async work complete) until [finder] matches.
Future<void> pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  int maxPumps = 100,
}) async {
  for (var i = 0; i < maxPumps; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Widget did not appear after $maxPumps pumps: $finder');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    setupFirebaseCoreMocks();

    fakeAuth = FakeFirebaseAuthPlatform(
      accounts: const [
        FakeAuthAccount(
          uid: kTouristUid,
          email: kTouristEmail,
          password: kCorrectPassword,
          displayName: 'Case 005 Tourist',
          emailVerified: true,
        ),
      ],
    );
    FirebaseAuthPlatform.instance = fakeAuth;

    fakeFirestore = FakeFirebaseFirestorePlatform();
    FirebaseFirestorePlatform.instance = fakeFirestore;

    await Firebase.initializeApp();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await FirebaseAuth.instance.signOut();
    fakeAuth.signInCalls.clear();

    // The tourist profile exists, so the ONLY reason login can fail is the
    // incorrect password.
    fakeFirestore.documents.clear();
    fakeFirestore.seedDocument('users/$kTouristUid', <String, dynamic>{
      'uid': kTouristUid,
      'fullName': 'Case 005 Tourist',
      'email': kTouristEmail,
      'role': UserRoles.tourist,
      'preferredLanguage': 'en',
      'accountStatus': 'active',
      'createdAtMillis': 0,
    });
  });

  testWidgets(
    'CASE-005 - Incorrect password: login is rejected, credential error is '
    'shown, Tourist Home Page does not open',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);

      // STEP 1: Precondition - no signed-in user.
      expect(
        FirebaseAuth.instance.currentUser,
        isNull,
        reason: 'Test must start from a logged-out state.',
      );

      // STEP 2: Open the REAL HeritageBot AuthGate -> LoginSignupScreen.
      await tester.pumpWidget(const MaterialApp(home: app.AuthGate()));
      await pumpUntilFound(tester, find.byType(app.LoginSignupScreen));
      expect(find.byType(app.MainShell), findsNothing);

      // STEP 3: Enter the valid email and an INCORRECT password.
      final textFields = find.descendant(
        of: find.byType(app.LoginSignupScreen),
        matching: find.byType(TextField),
      );
      expect(
        textFields,
        findsNWidgets(2),
        reason: 'Login mode should show the email and password fields only.',
      );

      await tester.enterText(textFields.at(0), kTouristEmail);
      await tester.enterText(textFields.at(1), kIncorrectPassword);
      await tester.pump();

      // STEP 4: Tap the real Login button.
      final loginButton = find.ancestor(
        of: find.byIcon(Icons.login_rounded),
        matching: find.byType(ElevatedButton),
      );
      expect(loginButton, findsOneWidget);

      await tester.ensureVisible(loginButton);
      await tester.pump();
      await tester.tap(loginButton);
      await tester.pump();

      // STEP 5: The app really sent the entered credentials to Firebase
      // (so the rejection comes from Firebase, not from local validation).
      expect(fakeAuth.signInCalls, hasLength(1));
      expect(fakeAuth.signInCalls.single.email, kTouristEmail);
      expect(fakeAuth.signInCalls.single.password, kIncorrectPassword);

      // STEP 6: Wait for the real error SnackBar raised by LoginSignupScreen.
      await pumpUntilFound(tester, find.byType(SnackBar));

      // STEP 7: Authentication failed - nobody is signed in.
      expect(
        FirebaseAuth.instance.currentUser,
        isNull,
        reason: 'Firebase must reject the incorrect password.',
      );

      // STEP 8: An appropriate credential error is visible in the UI.
      // The app displays FirebaseAuthException.message; the mocked Firebase
      // rejection for 'invalid-credential' carries this message.
      const expectedError = 'The supplied auth credential is incorrect.';
      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.text(expectedError),
        ),
        findsOneWidget,
        reason: 'The incorrect-password error must be shown to the tourist.',
      );

      // STEP 9: Let any (unexpected) late navigation happen, then verify the
      // Tourist Home Page did NOT open and the tourist is still on Login.
      await tester.pump(const Duration(seconds: 1));
      expect(FirebaseAuth.instance.currentUser, isNull);
      expect(find.byType(app.LoginSignupScreen), findsOneWidget);
      expect(find.byType(app.MainShell), findsNothing);
      expect(find.byType(app.HomeScreen), findsNothing);
      expect(find.text('Explore Heritage by Location'), findsNothing);
      expect(find.byType(app.AdminShell), findsNothing);
      expect(find.byType(app.ContributorDashboardScreen), findsNothing);
      expect(find.byType(app.EmailVerificationScreen), findsNothing);

      // STEP 10: The login form recovered from the failure (button enabled
      // again, entered email kept) so the tourist can retry.
      final button = tester.widget<ElevatedButton>(loginButton);
      expect(
        button.onPressed,
        isNotNull,
        reason: 'Login button must be re-enabled after a failed attempt.',
      );
      expect(find.text(kTouristEmail), findsOneWidget);
      expect(fakeAuth.signInCalls, hasLength(1),
          reason: 'No automatic retry or extra sign-in should occur.');

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 5));
    },
  );
}
