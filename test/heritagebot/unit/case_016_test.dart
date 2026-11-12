// HERITAGEBOT - TEST CASE 016
// Proponent: Reil Esdrelon
// Module: Authenticate User
// Unit: Change Password
// Description: Enter valid current and new passwords.
// Expected: Update account password.
//
// TEST TYPE: Flutter widget test (host VM, no device / live Firebase).
//
// REAL CODE UNDER TEST (lib/, unmodified)
//   AuthGate -> MainShell -> Profile tab (ProfileScreen) -> "Change Password"
//   -> ChangePasswordScreen.submitChangePassword ->
//   AuthService.changeCurrentUserPassword (reauthenticateWithCredential +
//   updatePassword) -> success SnackBar and return to Profile.
//
// MOCKED: Firebase platform layer only (verified dummy tourist).

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:heritagebot/main.dart' as app;

import '../support/heritagebot_test_harness.dart';

const FakeAuthAccount kTourist = FakeAuthAccount(
  uid: 'case016-tourist-uid',
  email: 'case016.tourist@heritagebot.test',
  password: 'Case016OldPass!',
  displayName: 'Case 016 Tourist',
);
const String kNewPassword = 'Case016NewPass!';

late HeritageBotTestBackend backend;

void main() {
  setUpAll(() async {
    backend = await HeritageBotTestBackend.install(accounts: [kTourist]);
  });

  setUp(() async {
    await backend.reset();
    backend.seedTourist(kTourist);
  });

  testWidgets('CASE-016 - Valid current and new passwords: account password '
      'is updated', (WidgetTester tester) async {
    usePhoneSurface(tester);

    // STEP 1: Precondition - verified tourist signed in, on the home page.
    await signInBeforeLaunch(kTourist);
    await launchAuthGate(tester, until: app.MainShell);

    // STEP 2: Profile tab -> Change Password.
    await tapNavDestination(tester, en('profile'));
    await pumpUntilFound(tester, find.text(en('changePassword')));
    await tapVisible(tester, find.text(en('changePassword')));
    await pumpUntilFound(tester, find.byType(app.ChangePasswordScreen));

    // STEP 3: Enter valid current / new / confirm passwords.
    final fields = fieldsOf(app.ChangePasswordScreen);
    expect(fields, findsNWidgets(3));
    await tester.enterText(fields.at(0), kTourist.password);
    await tester.enterText(fields.at(1), kNewPassword);
    await tester.enterText(fields.at(2), kNewPassword);
    await tester.pump();

    // STEP 4: Tap the real "Save New Password" button.
    await tapVisible(tester, find.text('Save New Password'));
    await pumpUntilFound(
        tester, snackBarWithText('Password changed successfully.'));

    // The real screen closes itself 600 ms after success.
    await pumpUntilGone(tester, find.byType(app.ChangePasswordScreen));

    // ---- Observations ---------------------------------------------------
    final stored = backend.auth.accountByEmail(kTourist.email)!;
    final passwordChanged = stored.password == kNewPassword;
    final user = FirebaseAuth.instance.currentUser;
    final sessionValid = user != null &&
        user.uid == kTourist.uid &&
        find.byType(app.MainShell).evaluate().isNotEmpty;

    // ---- Expected result -------------------------------------------------
    expect(passwordChanged, isTrue,
        reason: 'CASE-016: Firebase must hold the new password.');
    expect(sessionValid, isTrue,
        reason: 'CASE-016: the tourist must stay signed in afterwards.');

    // Supporting evidence: re-authenticated with the current password first,
    // returned to Profile, and only the new password works for login.
    expect(backend.auth.reauthenticationCalls, [kTourist.email]);
    expect(backend.auth.passwordUpdates, [kTourist.uid]);
    expect(find.byType(app.ProfileScreen), findsOneWidget,
        reason: 'The tourist is returned to the Profile page.');

    await unmountApp(tester);

    await FirebaseAuth.instance.signOut();
    await expectLater(
      FirebaseAuth.instance.signInWithEmailAndPassword(
          email: kTourist.email, password: kTourist.password),
      throwsA(isA<FirebaseAuthException>()),
      reason: 'The old password must no longer be accepted.',
    );
    final relogin = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: kTourist.email, password: kNewPassword);
    expect(relogin.user?.uid, kTourist.uid);
  });
}
