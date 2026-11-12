// HERITAGEBOT - TEST CASE 051
// Proponent: James Stephen O. Ramos
// Module: Community Contributor Management
// Unit: Submit Heritage Story
// Description: Select heritage site for story.
// Expected: Associate story with selected site.
//
// TEST TYPE: Flutter widget test (host VM, no device / live Firebase).
//
// REAL CODE UNDER TEST (lib/, unmodified)
//   AuthGate (role = community_contributor) -> MainShell "Contribute" ->
//   ContributorDashboardScreen -> "Submit Story" ->
//   SubmitCommunityStoryScreen ("Heritage Place" dropdown built from
//   officialHeritagePlaces) -> _submit -> CommunitySubmissionService
//   .submitStory -> Firestore community_submissions/{id} -> dashboard.
//
// FIXTURE (fixtureId = CASE-051): the contributor changes the Heritage Place
// from the default (first official site, Casa Gorordo Museum) to
// "Fort San Pedro", so the test proves the SELECTED site - not the default -
// is stored. Valid title and story (>= 5 / >= 80 characters); no media.
//
// MOCKED: Firebase platform layer only (in-memory Firestore).

import 'package:flutter_test/flutter_test.dart';

import 'package:heritagebot/main.dart' as app;
import 'package:heritagebot/models/heritage_place.dart';

import '../support/contributor_flow.dart';
import '../support/heritagebot_fixtures.dart';
import '../support/story_submission_flow.dart';

const FakeAuthAccount kContributor = FakeAuthAccount(
  uid: 'case051-contributor-uid',
  email: 'case051.contributor@heritagebot.test',
  password: 'Case051Pass!',
  displayName: 'James Contributor',
);

const String kTitle = 'Cannons Facing the Strait at Fort San Pedro';
const String kStory =
    'My lolo was a guard near Fort San Pedro after the war. He told us how '
    'the old stone walls sheltered families during air raids and how the '
    'triangular bastions once watched every ship entering the port of Cebu.';

late HeritageBotTestBackend backend;

void main() {
  setUpAll(() async {
    backend = await HeritageBotTestBackend.install(accounts: [kContributor]);
  });

  setUp(() async {
    await backend.reset();
    seedContributor(backend, kContributor);
  });

  testWidgets('CASE-051 - Select heritage site for story', (
    WidgetTester tester,
  ) async {
    usePhoneSurface(tester);
    final defaultPlace = officialHeritagePlaces.first;
    final selectedPlace = bundledSite('fort_san_pedro');
    expect(
      officialHeritagePlaces.map((p) => p.id),
      contains(selectedPlace.id),
      reason: 'Precondition: Fort San Pedro is offered in the dropdown.',
    );
    expect(
      selectedPlace.id,
      isNot(defaultPlace.id),
      reason: 'Precondition: the chosen site differs from the default.',
    );

    await signInBeforeLaunch(kContributor);
    await openSubmitStoryScreen(tester);
    expect(storedSubmissions(backend), isEmpty);

    // STEP: choose "Fort San Pedro" in the real Heritage Place dropdown.
    await chooseHeritagePlace(
      tester,
      screen: app.SubmitCommunityStoryScreen,
      placeName: selectedPlace.name,
    );

    // STEP: fill in the story and tap "Submit for Review".
    await fillAndSubmitStory(tester, title: kTitle, story: kStory);
    await pumpUntilFound(
      tester,
      snackBarWithText('Heritage story submitted for administrator review.'),
    );
    await pumpUntilGone(tester, find.byType(app.SubmitCommunityStoryScreen));
    await pumpFor(tester, const Duration(milliseconds: 500));

    // ---- Observations ---------------------------------------------------
    final stored = storedSubmissions(backend);
    final doc = stored.length == 1 ? stored.values.single : null;
    final cards = await collectDashboardCards(tester);
    final card = cards[kTitle];

    final observed = <String, Object?>{
      // A heritage-site reference was saved with the submission.
      'siteAssociationSaved':
          doc != null &&
          doc['title'] == kTitle &&
          doc['contributorId'] == kContributor.uid &&
          (doc['heritagePlaceId'] as String? ?? '').isNotEmpty &&
          (doc['heritagePlaceName'] as String? ?? '').isNotEmpty,
      // ...and it is the site the contributor selected (not the default).
      'correctSiteLinked':
          doc != null &&
          doc['heritagePlaceId'] == selectedPlace.id &&
          doc['heritagePlaceName'] == selectedPlace.name &&
          card?.placeName == selectedPlace.name,
    };
    printOnFailure(
      'CASE-051 observed: $observed\n'
      'storedSubmissions=$stored\ndashboardCard=$card\n'
      'default=${defaultPlace.id} selected=${selectedPlace.id}',
    );

    // ---- Expected result (unchanged from the original CASE-051) ---------
    expect(
      observed['siteAssociationSaved'],
      equals(true),
      reason:
          'CASE-051: siteAssociationSaved does not match the real system result',
    );
    expect(
      observed['correctSiteLinked'],
      equals(true),
      reason:
          'CASE-051: correctSiteLinked does not match the real system result',
    );

    await unmountApp(tester);
  });
}
