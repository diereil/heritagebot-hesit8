// HERITAGEBOT - TEST CASE 066
// Proponent: James Stephen O. Ramos
// Module: User Profile Management
// Unit: Manage Profile
// Description: Update valid profile details.
// Expected: Save updated profile.
//
// TEST TYPE: Flutter widget test (host VM, no device / live Firebase).
//
// REAL CODE UNDER TEST (lib/, unmodified)
//   AuthGate -> MainShell -> Profile -> ProfileScreen, using whatever
//   profile-editing UI the screen offers (editable fields on the screen, or
//   an "Edit / Update Profile"-type entry that opens a form) -> its save
//   action -> users/{uid} (UserService) / FirebaseAuth display name.
//   (attemptProfileEdit in support/contributor_flow.dart only taps and
//   types; it records what the real screen offers.)
//
// FIXTURE (fixtureId = CASE-066): a signed-in Tourist changes the full name
// from "Andrea Villanueva" to the valid name "Andrea M. Villanueva-Cruz".
//
// MOCKED: Firebase platform layer only (in-memory Firestore / Auth).

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:heritagebot/main.dart' as app;

import '../support/contributor_flow.dart';
import '../support/heritagebot_fixtures.dart';

const FakeAuthAccount kTourist = FakeAuthAccount(
  uid: 'case066-tourist-uid',
  email: 'case066.tourist@heritagebot.test',
  password: 'Case066Pass!',
  displayName: 'Andrea Villanueva',
);
const String kNewFullName = 'Andrea M. Villanueva-Cruz';
const String kProfilePath = 'users/case066-tourist-uid';

late HeritageBotTestBackend backend;

void main() {
  setUpAll(() async {
    backend = await HeritageBotTestBackend.install(accounts: [kTourist]);
  });

  setUp(() async {
    await backend.reset();
    backend.seedTourist(kTourist);
  });

  testWidgets('CASE-066 - Update valid profile details', (
    WidgetTester tester,
  ) async {
    usePhoneSurface(tester);
    final before = Map<String, dynamic>.of(
      backend.firestore.documents[kProfilePath]!,
    );

    await signInBeforeLaunch(kTourist);
    await launchAuthGate(tester, until: app.MainShell);
    await openProfileTab(tester);

    // STEP: change the full name through the Profile screen and save.
    final attempt = await attemptProfileEdit(tester, newFullName: kNewFullName);

    // ---- Observations ---------------------------------------------------
    final after = backend.firestore.documents[kProfilePath];
    final authName = FirebaseAuth.instance.currentUser?.displayName;

    final observed = <String, Object?>{
      'profileUpdated':
          attempt.saveAction != null &&
          attempt.fieldErrors.isEmpty &&
          (after?['fullName'] == kNewFullName || authName == kNewFullName),
      'changesPersisted':
          after?['fullName'] == kNewFullName &&
          after?['email'] == before['email'] &&
          after?['role'] == before['role'],
    };
    printOnFailure(
      'CASE-066 observed: $observed\n$attempt\n'
      'before=$before\nafter=$after\nauthDisplayName=$authName',
    );

    // ---- Expected result (unchanged from the original CASE-066) ---------
    expect(
      observed['profileUpdated'],
      equals(true),
      reason: 'CASE-066: profileUpdated does not match the real system result',
    );
    expect(
      observed['changesPersisted'],
      equals(true),
      reason:
          'CASE-066: changesPersisted does not match the real system result',
    );

    await unmountApp(tester);
  });
}
