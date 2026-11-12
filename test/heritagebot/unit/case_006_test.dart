// HERITAGEBOT - TEST CASE 006
// Proponent: Reil Esdrelon
// Module: Authenticate User
// Unit: Login
// Description: Administrator enters valid login credentials.
// Expected: Login succeeds and the authorized Administrator Dashboard opens.
//
// TEST TYPE
// Flutter widget test (package:flutter_test). Runs on the host VM through
// `flutter test` - no Android device, emulator, or live Firebase project.
//
// WHAT IS REAL (unmodified production code from lib/)
//   * AuthGate                    - auth-state routing and role routing
//                                   (switch on UserProfile.role -> AdminShell)
//   * LoginSignupScreen           - real text fields, validation, Login button
//   * AuthService.loginWithEmail  - real call into FirebaseAuth
//   * UserService.getUserProfile  - real users/{uid} profile lookup and
//                                   role parsing (UserProfile.fromMap)
//   * AdminShell                  - real administrator shell / bottom nav
//   * AdminAnalyticsScreen        - real "System Summary" admin dashboard
//                                   (AdminAnalyticsService loads live data
//                                   from the mocked Firestore)
//   * AdminDashboardScreen etc.   - real admin tabs built by AdminShell
//
// WHAT IS MOCKED (test/heritagebot/support/fake_firebase_platform.dart)
//   * Firebase native platform layer only (same fake used by CASE-004/005):
//     an in-memory auth backend seeded with one verified dummy administrator
//     account, and an in-memory Firestore seeded with that administrator's
//     users/{uid} profile document (role: 'admin').
//
// HOW ADMIN AUTHORIZATION IS EXERCISED
// HeritageBot grants the administrator role in two ways:
//   (a) UserService.adminEmails - a hard-coded allowlist of REAL admin email
//       addresses (auto-creates an admin profile on login), and
//   (b) a users/{uid} profile document whose 'role' field is 'admin'.
// This test deliberately uses (b) with a dummy email so that no real
// administrator account or credential is touched. The test asserts that the
// dummy email is NOT on the allowlist, which proves the Administrator
// Dashboard was reached through the real role-based routing in AuthGate.

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
import 'package:heritagebot/services/user_service.dart';

import '../support/fake_firebase_platform.dart';

// Dummy in-memory administrator account (NOT a real Firebase user).
const String kAdminUid = 'case006-admin-uid';
const String kAdminEmail = 'case006.admin@heritagebot.test';
const String kAdminPassword = 'Case006AdminPass!';
const String kAdminName = 'Case 006 Administrator';

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
          uid: kAdminUid,
          email: kAdminEmail,
          password: kAdminPassword,
          displayName: kAdminName,
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

    // Administrator profile document, using the same field structure that
    // UserService writes for administrators (_createOrUpdateAdminProfile).
    fakeFirestore.documents.clear();
    fakeFirestore.seedDocument('users/$kAdminUid', <String, dynamic>{
      'uid': kAdminUid,
      'fullName': kAdminName,
      'email': kAdminEmail,
      'role': UserRoles.admin,
      'preferredLanguage': 'en',
      'accountStatus': 'active',
      'photoUrl': '',
      'createdAtMillis': 0,
      'updatedAtMillis': 0,
    });
  });

  testWidgets(
    'CASE-006 - Valid administrator credentials: login succeeds and opens '
    'the authorized Administrator Dashboard',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);

      // STEP 1: Preconditions - logged out, and the dummy admin is NOT on
      // the real email allowlist (so routing must come from the role field).
      expect(
        FirebaseAuth.instance.currentUser,
        isNull,
        reason: 'Test must start from a logged-out state.',
      );
      expect(
        UserService.adminEmails.contains(kAdminEmail),
        isFalse,
        reason: 'Fixture must not use a real allowlisted admin email.',
      );

      // STEP 2: Open the REAL HeritageBot AuthGate -> LoginSignupScreen.
      await tester.pumpWidget(const MaterialApp(home: app.AuthGate()));
      await pumpUntilFound(tester, find.byType(app.LoginSignupScreen));
      expect(find.byType(app.AdminShell), findsNothing);
      expect(find.byType(app.MainShell), findsNothing);

      // STEP 3: Enter valid administrator credentials into the real fields.
      final textFields = find.descendant(
        of: find.byType(app.LoginSignupScreen),
        matching: find.byType(TextField),
      );
      expect(
        textFields,
        findsNWidgets(2),
        reason: 'Login mode should show the email and password fields only.',
      );

      await tester.enterText(textFields.at(0), kAdminEmail);
      await tester.enterText(textFields.at(1), kAdminPassword);
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

      // STEP 5: AuthService really sent the entered credentials to Firebase
      // Authentication (exactly once).
      expect(fakeAuth.signInCalls, hasLength(1));
      expect(fakeAuth.signInCalls.single.email, kAdminEmail);
      expect(fakeAuth.signInCalls.single.password, kAdminPassword);

      // STEP 6: Wait for AuthGate to route to the administrator interface.
      await pumpUntilFound(tester, find.byType(app.AdminShell));

      // STEP 7: Firebase reports the administrator as signed in.
      final user = FirebaseAuth.instance.currentUser;
      expect(user, isNotNull, reason: 'Firebase login must succeed.');
      expect(user!.uid, kAdminUid);
      expect(user.email, kAdminEmail);
      expect(user.emailVerified, isTrue);

      // STEP 8: The real role-based authorization recognised the account as
      // an Administrator (profile handed to AdminShell by AuthGate).
      final shell = tester.widget<app.AdminShell>(find.byType(app.AdminShell));
      expect(shell.profile.uid, kAdminUid);
      expect(shell.profile.email, kAdminEmail);
      expect(shell.profile.role, UserRoles.admin);
      expect(shell.profile.isAdmin, isTrue);
      expect(shell.profile.accountStatus, 'active');
      expect(UserRoles.label(shell.profile.role), 'Administrator');

      // STEP 9: The Administrator Dashboard is open: admin navigation and
      // the System Summary dashboard (first admin tab) are on screen.
      final navBar = find.descendant(
        of: find.byType(app.AdminShell),
        matching: find.byType(NavigationBar),
      );
      expect(navBar, findsOneWidget);
      for (final label in ['Summary', 'Review', 'Sites', 'AI Base', 'Settings']) {
        expect(
          find.descendant(of: navBar, matching: find.text(label)),
          findsOneWidget,
          reason: 'Admin navigation must include "$label".',
        );
      }
      expect(
        tester.widget<NavigationBar>(navBar).selectedIndex,
        0,
        reason: 'Administrator lands on the Summary dashboard.',
      );
      expect(find.byType(app.AdminAnalyticsScreen), findsOneWidget);
      expect(
        find.byType(app.AdminDashboardScreen, skipOffstage: false),
        findsOneWidget,
      );

      // Wait for the real dashboard to finish loading statistics from the
      // (mocked) Firestore, then verify it rendered real data, not an error.
      await pumpUntilFound(tester, find.text('Total Users'));
      expect(find.text('Could Not Load Analytics'), findsNothing);

      final totalUsersCard = find.ancestor(
        of: find.text('Total Users'),
        matching: find.byType(Card),
      );
      expect(
        find.descendant(of: totalUsersCard, matching: find.text('1')),
        findsOneWidget,
        reason: 'Dashboard must count the single seeded administrator user.',
      );
      expect(
        find.descendant(
          of: totalUsersCard,
          matching: find.text('1 active • 0 suspended'),
        ),
        findsOneWidget,
      );

      // STEP 10: The administrator was NOT routed to the Tourist Home Page
      // (or any other non-admin screen), and the login screen is gone.
      expect(find.byType(app.MainShell), findsNothing);
      expect(find.byType(app.HomeScreen), findsNothing);
      expect(find.text('Explore Heritage by Location'), findsNothing);
      expect(find.byType(app.ContributorDashboardScreen), findsNothing);
      expect(find.byType(app.LoginSignupScreen), findsNothing);
      expect(find.byType(app.EmailVerificationScreen), findsNothing);
      expect(find.byType(app.RoleSetupScreen), findsNothing);

      // The stored role was not altered by the login flow.
      expect(
        fakeFirestore.documents['users/$kAdminUid']?['role'],
        UserRoles.admin,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 5));
    },
  );
}
