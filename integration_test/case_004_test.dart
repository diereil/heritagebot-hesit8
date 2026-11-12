
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import 'package:heritagebot/firebase_options.dart';
import 'package:heritagebot/main.dart' as app;

// HERITAGEBOT - TEST CASE 004
// Proponent: Reil Esdrelon
// Module: Authenticate User
// Unit: Login
// Description: Valid tourist credentials
// Expected: Login succeeds and opens tourist home.

Future<void> waitForWidget(
  WidgetTester tester,
  Finder finder,
) async {
  for (int i = 0; i < 60; i++) {
    await tester.pump();

    if (finder.evaluate().isNotEmpty) {
      return;
    }

    await tester.runAsync(() async {
      await Future<void>.delayed(
        const Duration(milliseconds: 400),
      );
    });
  }

  fail('Expected widget did not appear: $finder');
}

void main() {
  IntegrationTestWidgetsFlutterBinding
      .ensureInitialized();

  const email = String.fromEnvironment(
    'HB_TEST_TOURIST_EMAIL',
  );

  const password = String.fromEnvironment(
    'HB_TEST_TOURIST_PASSWORD',
  );

  testWidgets(
    'CASE-004 - Valid Tourist Credentials',
    (WidgetTester tester) async {

      // STEP 1: Require test credentials.
      expect(email, isNotEmpty);
      expect(password, isNotEmpty);

      // STEP 2: Initialize real Firebase.
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );

      // Start from logged-out state.
      await FirebaseAuth.instance.signOut();

      // STEP 3: Open actual HeritageBot AuthGate.
      await tester.pumpWidget(
        const MaterialApp(
          home: app.AuthGate(),
        ),
      );

      await waitForWidget(
        tester,
        find.byType(app.LoginSignupScreen),
      );

      // STEP 4: Enter valid tourist credentials.
      final textFields = find.byType(TextField);

      expect(textFields, findsAtLeastNWidgets(2));

      await tester.enterText(
        textFields.at(0),
        email,
      );

      await tester.enterText(
        textFields.at(1),
        password,
      );

      // STEP 5: Tap the actual Login button.
      final loginButton = find.ancestor(
        of: find.byIcon(Icons.login_rounded),
        matching: find.byType(ElevatedButton),
      );

      expect(loginButton, findsOneWidget);

      await tester.ensureVisible(loginButton);
      await tester.tap(loginButton);
      await tester.pump();

      // STEP 6: Wait for the tourist home.
      await waitForWidget(
        tester,
        find.byType(app.MainShell),
      );

      // STEP 7: Verify Firebase login.
      final user = FirebaseAuth.instance.currentUser;

      expect(
        user,
        isNotNull,
        reason: 'Firebase login must succeed.',
      );

      expect(
        user?.email?.toLowerCase(),
        email.trim().toLowerCase(),
      );

      // STEP 8: Verify tourist role.
      final shell = tester.widget<app.MainShell>(
        find.byType(app.MainShell),
      );

      expect(
        shell.userRole,
        'tourist',
        reason: 'Must open tourist interface.',
      );

      // STEP 9: Verify the home screen.
      expect(
        find.byType(app.HomeScreen),
        findsOneWidget,
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
