// HERITAGEBOT - TEST CASE 011
// Proponent: Reil Esdrelon
// Module: Authenticate User
// Unit: Choose User Role
// Description: No role selected.
// Expected: Require role selection (no role is saved and the user is told
//           to select a role).
//
// TEST TYPE: Flutter widget test (host VM, no device / live Firebase).
//
// REAL CODE UNDER TEST (lib/, unmodified)
//   (a) Service guard: UserService.savePublicProfile(role: '')
//   (b) UI: AuthGate -> RoleSetupScreen; the user does NOT touch the
//       Account Type selector and taps "Save Account Type".
//
// OBSERVED APP DESIGN (lib/main.dart, _RoleSetupScreenState):
//   `String selectedRole = UserRoles.tourist;`  - the selector is
//   pre-filled with Tourist and offers no empty option, and saveRole() only
//   validates the full name. The test records what the real screen does;
//   it does not assume the outcome.
//
// MOCKED: Firebase platform layer only.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:heritagebot/main.dart' as app;
import 'package:heritagebot/models/user_profile.dart';
import 'package:heritagebot/services/user_service.dart';

import '../support/heritagebot_test_harness.dart';

const FakeAuthAccount kNewUser = FakeAuthAccount(
  uid: 'case011-new-user-uid',
  email: 'case011.newuser@heritagebot.test',
  password: 'Case011Pass!',
  displayName: 'Case 011 New User',
);

late HeritageBotTestBackend backend;

void main() {
  setUpAll(() async {
    backend = await HeritageBotTestBackend.install(accounts: [kNewUser]);
  });

  setUp(() => backend.reset());

  testWidgets('CASE-011 - No role selected: role selection is required',
      (WidgetTester tester) async {
    usePhoneSurface(tester);

    await signInBeforeLaunch(kNewUser);
    final firebaseUser = FirebaseAuth.instance.currentUser!;

    // STEP 1 (service level): an empty role is rejected by UserService.
    Object? serviceError;
    try {
      await UserService().savePublicProfile(
        firebaseUser: firebaseUser,
        fullName: kNewUser.displayName!,
        role: '',
        preferredLanguage: 'en',
      );
    } catch (error) {
      serviceError = error;
    }
    expect(serviceError, isA<ArgumentError>(),
        reason: 'UserService must refuse to store an empty role.');
    expect(backend.firestore.documents['users/${kNewUser.uid}'], isNull);

    // STEP 2 (UI level): the real role screen, no role chosen by the user.
    await launchAuthGate(tester, until: app.RoleSetupScreen);
    await tapVisible(tester, find.text('Save Account Type'));
    await pumpFor(tester, const Duration(seconds: 1));

    // ---- Observations ---------------------------------------------------
    final doc = backend.firestore.documents['users/${kNewUser.uid}'];
    final roleSaved = doc != null && UserRoles.isValidRole('${doc['role']}');
    final roleRequiredVisible = find
        .descendant(
          of: find.byType(SnackBar),
          matching: find.textContaining(
            RegExp(r'role|account type', caseSensitive: false),
          ),
        )
        .evaluate()
        .isNotEmpty;

    printOnFailure(
      'CASE-011 observed: roleSaved=$roleSaved, storedRole=${doc?['role']}, '
      'roleRequiredVisible=$roleRequiredVisible, '
      'mainShellOpened=${find.byType(app.MainShell).evaluate().isNotEmpty}',
    );

    // ---- Expected result -------------------------------------------------
    expect(roleSaved, isFalse,
        reason: 'CASE-011: no role may be stored when the user did not '
            'select one.');
    expect(roleRequiredVisible, isTrue,
        reason: 'CASE-011: the user must be told to select a role.');

    await unmountApp(tester);
  });
}
