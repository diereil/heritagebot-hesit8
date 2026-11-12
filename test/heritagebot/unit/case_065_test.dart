// HERITAGEBOT - TEST CASE 065
// Proponent: James Stephen O. Ramos
// Module: User Profile Management
// Unit: View Profile Information
// Description: View stored profile details.
// Expected: Show correct account details.
//
// TEST TYPE: Flutter widget test (host VM, no device / live Firebase).
//
// REAL CODE UNDER TEST (lib/, unmodified)
//   ProfileScreen: name + email (FirebaseAuth.currentUser) and the role
//   badge from UserService.getUserProfile(users/{uid}).
//
// FIXTURE (fixtureId = CASE-065): a Community Contributor whose stored
// profile document users/{uid} holds fullName / email / role exactly as
// UserService.savePublicProfile writes them at registration (the same name
// and email the Firebase Auth account carries). Another user's profile is
// also stored.
//
// OBSERVATION: every detail the Profile screen displays is compared with
// the STORED users/{uid} document of the signed-in account.
//
// MOCKED: Firebase platform layer only (in-memory Firestore / Auth).

import 'package:flutter_test/flutter_test.dart';

import 'package:heritagebot/main.dart' as app;
import 'package:heritagebot/models/user_profile.dart';

import '../support/contributor_flow.dart';
import '../support/heritagebot_fixtures.dart';

const FakeAuthAccount kContributor = FakeAuthAccount(
  uid: 'case065-contributor-uid',
  email: 'case065.contributor@heritagebot.test',
  password: 'Case065Pass!',
  displayName: 'James Stephen O. Ramos',
);
const FakeAuthAccount kOtherUser = FakeAuthAccount(
  uid: 'case065-other-uid',
  email: 'case065.tourist@heritagebot.test',
  password: 'Case065Other!',
  displayName: 'Visiting Tourist',
);

late HeritageBotTestBackend backend;

void main() {
  setUpAll(() async {
    backend = await HeritageBotTestBackend.install(
      accounts: [kContributor, kOtherUser],
    );
  });

  setUp(() async {
    await backend.reset();
    seedContributor(backend, kContributor);
    backend.seedTourist(kOtherUser);
  });

  testWidgets('CASE-065 - View stored profile details', (
    WidgetTester tester,
  ) async {
    usePhoneSurface(tester);
    final stored = Map<String, dynamic>.of(
      backend.firestore.documents['users/${kContributor.uid}']!,
    );
    final storedRoleLabel =
        'Role: ${UserRoles.label(stored['role'] as String)}';

    await signInBeforeLaunch(kContributor);
    await launchAuthGate(tester, until: app.MainShell);
    await openProfileTab(tester);
    await pumpUntilFound(
      tester,
      find.descendant(of: profileScreen, matching: find.text(storedRoleLabel)),
    );

    // ---- Observations ---------------------------------------------------
    final texts = profileTexts(tester);

    final observed = <String, Object?>{
      'profileDetailsVisible':
          texts.contains(stored['fullName']) &&
          texts.contains(stored['email']) &&
          texts.contains(storedRoleLabel),
      'correctAccountLoaded':
          stored['uid'] == kContributor.uid &&
          stored['fullName'] == kContributor.displayName &&
          stored['email'] == kContributor.email &&
          storedRoleLabel == 'Role: Community Contributor' &&
          texts.contains(kContributor.displayName) &&
          texts.contains(kContributor.email) &&
          !texts.contains(kOtherUser.displayName) &&
          !texts.contains(kOtherUser.email) &&
          !texts.contains('Role: Tourist'),
    };
    printOnFailure(
      'CASE-065 observed: $observed\nstored=$stored\n'
      'profileTexts=$texts',
    );

    // ---- Expected result (unchanged from the original CASE-065) ---------
    expect(
      observed['profileDetailsVisible'],
      equals(true),
      reason:
          'CASE-065: profileDetailsVisible does not match the real system result',
    );
    expect(
      observed['correctAccountLoaded'],
      equals(true),
      reason:
          'CASE-065: correctAccountLoaded does not match the real system result',
    );

    await unmountApp(tester);
  });
}
