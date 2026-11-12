// HERITAGEBOT - TEST CASE 004
// Proponent: Reil Esdrelon
// Module: Authenticate User
// Unit: Login
// Description: Tourist enters valid login credentials.
// Expected: Login succeeds and the Tourist Home Page opens.
//
// TEST TYPE
// Flutter widget test (package:flutter_test). Runs on the host VM through
// `flutter test` - no Android device, emulator, or live Firebase project.
//
// WHAT IS REAL (unmodified production code from lib/)
//   * AuthGate                  - auth-state routing and role routing
//   * LoginSignupScreen         - real text fields, validation, Login button
//   * AuthService.loginWithEmail - real call into FirebaseAuth
//   * UserService.getUserProfile - real Firestore profile lookup
//   * MainShell / HomeScreen    - real tourist home page
//
// WHAT IS MOCKED (test/heritagebot/support/fake_firebase_platform.dart)
//   * Firebase native platform layer only: an in-memory auth backend seeded
//     with one dummy tourist account and an in-memory Firestore seeded with
//     that tourist's users/{uid} profile document.
//   * No real credentials are used. The account below exists only in memory.

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
const String kTouristUid = 'case004-tourist-uid';
const String kTouristEmail = 'case004.tourist@heritagebot.test';
const String kTouristPassword = 'Case004Pass!';

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
    // Mock the native firebase_core channel, then plug in the fake
    // auth and Firestore platform implementations BEFORE any app code
    // touches FirebaseAuth.instance / FirebaseFirestore.instance.
    setupFirebaseCoreMocks();

    fakeAuth = FakeFirebaseAuthPlatform(
      accounts: const [
        FakeAuthAccount(
          uid: kTouristUid,
          email: kTouristEmail,
          password: kTouristPassword,
          displayName: 'Case 004 Tourist',
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

    // Tourist profile document read by the real UserService in AuthGate.
    fakeFirestore.documents.clear();
    fakeFirestore.seedDocument('users/$kTouristUid', <String, dynamic>{
      'uid': kTouristUid,
      'fullName': 'Case 004 Tourist',
      'email': kTouristEmail,
      'role': UserRoles.tourist,
      'preferredLanguage': 'en',
      'accountStatus': 'active',
      'createdAtMillis': 0,
    });
  });

  testWidgets(
    'CASE-004 - Valid tourist credentials: login succeeds and opens '
    'Tourist Home Page',
    (WidgetTester tester) async {
      // Use a phone-sized surface so the real login layout renders normally.
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);

      // STEP 1: Precondition - no signed-in user.
      expect(
        FirebaseAuth.instance.currentUser,
        isNull,
        reason: 'Test must start from a logged-out state.',
      );

      // STEP 2: Open the REAL HeritageBot AuthGate.
      await tester.pumpWidget(
        const MaterialApp(home: app.AuthGate()),
      );

      await pumpUntilFound(tester, find.byType(app.LoginSignupScreen));
      expect(find.byType(app.MainShell), findsNothing);

      // STEP 3: Enter valid tourist credentials into the real fields.
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
      await tester.enterText(textFields.at(1), kTouristPassword);
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

      // STEP 5: Verify AuthService really sent the entered credentials
      // to Firebase Authentication (exactly once).
      expect(fakeAuth.signInCalls, hasLength(1));
      expect(fakeAuth.signInCalls.single.email, kTouristEmail);
      expect(fakeAuth.signInCalls.single.password, kTouristPassword);

      // STEP 6: Wait for AuthGate to route to the tourist interface.
      await pumpUntilFound(tester, find.byType(app.MainShell));

      // STEP 7: Verify Firebase reports the tourist as signed in.
      final user = FirebaseAuth.instance.currentUser;
      expect(user, isNotNull, reason: 'Firebase login must succeed.');
      expect(user!.uid, kTouristUid);
      expect(user.email, kTouristEmail);

      // STEP 8: Verify the tourist role was applied by AuthGate.
      final shell = tester.widget<app.MainShell>(find.byType(app.MainShell));
      expect(
        shell.userRole,
        UserRoles.tourist,
        reason: 'AuthGate must open the tourist interface.',
      );

      // STEP 9: Verify the Tourist Home Page is shown and login is gone.
      expect(find.byType(app.HomeScreen), findsOneWidget);
      expect(find.text('Explore Heritage by Location'), findsOneWidget);
      expect(find.byType(app.LoginSignupScreen), findsNothing);
      expect(find.byType(app.AdminShell), findsNothing);
      expect(find.byType(app.ContributorDashboardScreen), findsNothing);
      expect(find.byType(app.EmailVerificationScreen), findsNothing);
      expect(find.byType(app.RoleSetupScreen), findsNothing);

      // Unmount so pending widget work completes cleanly.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    },
  );
}
