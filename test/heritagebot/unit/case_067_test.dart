// HERITAGEBOT - TEST CASE 067
// Proponent: James Stephen O. Ramos
// Module: User Profile Management
// Unit: Manage Profile
// Description: Submit invalid profile details.
// Expected: Show field validation error.
//
// TEST TYPE: Flutter widget test (host VM, no device / live Firebase).
//
// REAL CODE UNDER TEST (lib/, unmodified)
//   AuthGate -> MainShell -> Profile -> ProfileScreen, using whatever
//   profile-editing UI the screen offers (see CASE-066) -> its save action
//   -> its validation (field errorText or message).
//
// FIXTURE (fixtureId = CASE-067): a signed-in Tourist clears the full name
// (blank "   " - invalid) and tries to save.
//
// MOCKED: Firebase platform layer only (in-memory Firestore / Auth).

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:heritagebot/main.dart' as app;

import '../support/contributor_flow.dart';
import '../support/heritagebot_fixtures.dart';

const FakeAuthAccount kTourist = FakeAuthAccount(
  uid: 'case067-tourist-uid',
  email: 'case067.tourist@heritagebot.test',
  password: 'Case067Pass!',
  displayName: 'Andrea Villanueva',
);
const String kInvalidFullName = '   ';
const String kProfilePath = 'users/case067-tourist-uid';

/// A validation message about the name field.
final RegExp kValidationMessage = RegExp(
  r'required|enter (your|a)|invalid|valid name|cannot be empty|must not be empty|at least',
  caseSensitive: false,
);

late HeritageBotTestBackend backend;

void main() {
  setUpAll(() async {
    backend = await HeritageBotTestBackend.install(accounts: [kTourist]);
  });

  setUp(() async {
    await backend.reset();
    backend.seedTourist(kTourist);
  });

  testWidgets('CASE-067 - Submit invalid profile details', (
    WidgetTester tester,
  ) async {
    usePhoneSurface(tester);
    final before = Map<String, dynamic>.of(
      backend.firestore.documents[kProfilePath]!,
    );

    await signInBeforeLaunch(kTourist);
    await launchAuthGate(tester, until: app.MainShell);
    await openProfileTab(tester);

    // STEP: blank the full name through the Profile screen and save.
    final attempt = await attemptProfileEdit(
      tester,
      newFullName: kInvalidFullName,
    );

    // ---- Observations ---------------------------------------------------
    final after = backend.firestore.documents[kProfilePath];
    final authName = FirebaseAuth.instance.currentUser?.displayName;

    final observed = <String, Object?>{
      'profileUpdated':
          after?['fullName'] != before['fullName'] ||
          authName != kTourist.displayName,
      'validationErrorVisible':
          attempt.saveAction != null &&
          (attempt.fieldErrors.isNotEmpty ||
              attempt.messages.any(kValidationMessage.hasMatch)),
    };
    printOnFailure(
      'CASE-067 observed: $observed\n$attempt\n'
      'before=$before\nafter=$after\nauthDisplayName=$authName',
    );

    // ---- Expected result (unchanged from the original CASE-067) ---------
    expect(
      observed['profileUpdated'],
      equals(false),
      reason: 'CASE-067: profileUpdated does not match the real system result',
    );
    expect(
      observed['validationErrorVisible'],
      equals(true),
      reason:
          'CASE-067: validationErrorVisible does not match the real system result',
    );

    await unmountApp(tester);
  });
}
