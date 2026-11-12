// HERITAGEBOT - TEST CASE 010
// Proponent: Reil Esdrelon
// Module: Authenticate User
// Unit: Choose User Role
// Description: Select community contributor role.
// Expected: Store selected contributor role.
//
// TEST TYPE: Flutter widget test (host VM, no device / live Firebase).
//
// REAL CODE UNDER TEST (lib/, unmodified)
//   AuthGate -> (signed-in user with no users/{uid} profile) ->
//   RoleSetupScreen ("Choose Account Type") -> Account Type dropdown ->
//   "Save Account Type" -> UserService.savePublicProfile -> AuthGate ->
//   MainShell(userRole: community_contributor).
//
// NOTE ON ROLE VALUE: the original template used the label 'contributor'.
// HeritageBot stores this role as UserRoles.communityContributor
// ('community_contributor'); the test asserts against the app's constant.
//
// MOCKED: Firebase platform layer only.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:heritagebot/main.dart' as app;
import 'package:heritagebot/models/user_profile.dart';

import '../support/heritagebot_test_harness.dart';

// Verified account that has authenticated but has not chosen a role yet.
const FakeAuthAccount kNewUser = FakeAuthAccount(
  uid: 'case010-new-user-uid',
  email: 'case010.newuser@heritagebot.test',
  password: 'Case010Pass!',
  displayName: 'Case 010 Contributor',
);

late HeritageBotTestBackend backend;

void main() {
  setUpAll(() async {
    backend = await HeritageBotTestBackend.install(accounts: [kNewUser]);
  });

  setUp(() => backend.reset()); // no users/{uid} document

  testWidgets('CASE-010 - Select Community Contributor role: contributor '
      'role is stored', (WidgetTester tester) async {
    usePhoneSurface(tester);

    // STEP 1: Precondition - authenticated, no stored role.
    await signInBeforeLaunch(kNewUser);
    expect(backend.firestore.documents['users/${kNewUser.uid}'], isNull);

    // STEP 2: AuthGate must ask the user to choose an account type.
    await launchAuthGate(tester, until: app.RoleSetupScreen);
    expect(find.text('Choose Account Type'), findsOneWidget);

    // STEP 3: Open the real Account Type dropdown and pick Community
    // Contributor.
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Community Contributor').last);
    await tester.pumpAndSettle();

    // STEP 4: Tap the real "Save Account Type" button.
    await tapVisible(tester, find.text('Save Account Type'));

    // STEP 5: The app re-enters AuthGate with the stored role.
    await pumpUntilFound(tester, find.byType(app.MainShell));
    await pumpFor(tester, const Duration(milliseconds: 500));

    // ---- Observations ---------------------------------------------------
    final doc = backend.firestore.documents['users/${kNewUser.uid}'];
    final roleSaved = doc != null && UserRoles.isValidRole('${doc['role']}');
    final selectedRole = doc?['role'];

    // ---- Expected result -------------------------------------------------
    expect(roleSaved, isTrue,
        reason: 'CASE-010: the chosen role must be stored in users/{uid}.');
    expect(selectedRole, UserRoles.communityContributor,
        reason: 'CASE-010: stored role must be Community Contributor.');

    // Supporting evidence: profile content and contributor interface.
    expect(doc!['uid'], kNewUser.uid);
    expect(doc['email'], kNewUser.email);
    expect(doc['fullName'], kNewUser.displayName);
    expect(doc['accountStatus'], 'active');
    final shell = tester.widget<app.MainShell>(find.byType(app.MainShell));
    expect(shell.userRole, UserRoles.communityContributor);
    expect(
      find.descendant(
          of: find.byType(NavigationBar), matching: find.text('Contribute')),
      findsOneWidget,
      reason: 'Contributor interface must show the Contribute tab.',
    );
    expect(find.byType(app.RoleSetupScreen), findsNothing);
    expect(FirebaseAuth.instance.currentUser?.uid, kNewUser.uid);

    await unmountApp(tester);
  });
}
