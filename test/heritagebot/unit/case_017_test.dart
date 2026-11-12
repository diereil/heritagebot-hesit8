// HERITAGEBOT - TEST CASE 017
// Proponent: Reil Esdrelon
// Module: Authenticate User
// Unit: Change Password
// Description: Enter incorrect current password.
// Expected: Reject password change.
//
// TEST TYPE: Flutter widget test (host VM, no device / live Firebase).
//
// REAL CODE UNDER TEST (lib/, unmodified)
//   Profile -> ChangePasswordScreen -> AuthService.changeCurrentUserPassword
//   -> User.reauthenticateWithCredential (rejected by Firebase with
//   'invalid-credential') -> the screen's error mapping
//   `e.code == 'wrong-password' || e.code == 'invalid-credential'`
//   -> "Current password is incorrect."
//
// MOCKED: Firebase platform layer only.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:heritagebot/main.dart' as app;

import '../support/heritagebot_test_harness.dart';

const FakeAuthAccount kTourist = FakeAuthAccount(
  uid: 'case017-tourist-uid',
  email: 'case017.tourist@heritagebot.test',
  password: 'Case017RealPass!',
  displayName: 'Case 017 Tourist',
);
const String kWrongCurrent = 'NotMyPassword9!';
const String kNewPassword = 'Case017NewPass!';

late HeritageBotTestBackend backend;

void main() {
  setUpAll(() async {
    backend = await HeritageBotTestBackend.install(accounts: [kTourist]);
  });

  setUp(() async {
    await backend.reset();
    backend.seedTourist(kTourist);
  });

  testWidgets('CASE-017 - Incorrect current password: password change is '
      'rejected', (WidgetTester tester) async {
    usePhoneSurface(tester);

    await signInBeforeLaunch(kTourist);
    await launchAuthGate(tester, until: app.MainShell);

    await tapNavDestination(tester, en('profile'));
    await pumpUntilFound(tester, find.text(en('changePassword')));
    await tapVisible(tester, find.text(en('changePassword')));
    await pumpUntilFound(tester, find.byType(app.ChangePasswordScreen));

    // Enter an INCORRECT current password and a valid new password.
    final fields = fieldsOf(app.ChangePasswordScreen);
    await tester.enterText(fields.at(0), kWrongCurrent);
    await tester.enterText(fields.at(1), kNewPassword);
    await tester.enterText(fields.at(2), kNewPassword);
    await tester.pump();

    await tapVisible(tester, find.text('Save New Password'));
    await pumpUntilFound(tester, find.byType(SnackBar));
    await pumpFor(tester, const Duration(seconds: 1));

    // ---- Observations ---------------------------------------------------
    final stored = backend.auth.accountByEmail(kTourist.email)!;
    final passwordChanged = stored.password != kTourist.password;
    final currentPasswordErrorVisible =
        snackBarWithText('Current password is incorrect.')
            .evaluate()
            .isNotEmpty;

    // ---- Expected result -------------------------------------------------
    expect(passwordChanged, isFalse,
        reason: 'CASE-017: the password must not change.');
    expect(currentPasswordErrorVisible, isTrue,
        reason: 'CASE-017: "Current password is incorrect." must be shown.');

    // Supporting evidence: Firebase was asked to verify the current password
    // and refused; no update was sent; the user stays on the form, signed in.
    expect(backend.auth.reauthenticationCalls, [kTourist.email]);
    expect(backend.auth.passwordUpdates, isEmpty);
    expect(find.byType(app.ChangePasswordScreen), findsOneWidget);
    expect(FirebaseAuth.instance.currentUser?.uid, kTourist.uid);
    expect(find.text('Save New Password'), findsOneWidget,
        reason: 'The form must be ready for another attempt.');

    await unmountApp(tester);
  });
}
