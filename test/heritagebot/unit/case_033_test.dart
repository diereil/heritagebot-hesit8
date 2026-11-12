// HERITAGEBOT - TEST CASE 033
// Proponent: Reil Esdrelon
// Module: Tourist Heritage Access
// Unit: AI Historical Narrative
// Description: No relevant source data found.
// Expected: Display safe unavailable response (no narrative; a message that
//           no verified information is available).
//
// TEST TYPE: Flutter widget test (host VM, no device / live Firebase).
//
// REAL CODE UNDER TEST (lib/, unmodified)
//   HeritageSiteService.initializeRuntimeSites -> GeolocationScreen
//   .handleNewPosition -> showPlacePopup ->
//   GeminiStoryService.generateContextAwareStory -> NarrativeAutoPlaybackPanel.
//
// FIXTURE (siteFixture = site_with_no_verified_sources)
// A registered heritage_sites record whose historicalFacts field is empty,
// and an empty `historical_contents` knowledge base - i.e. HeritageBot has
// NO verified source text for this place. (HeritagePlace.fromMap accepts an
// empty historicalFacts field.) The tourist stands at the site.
//
// SCOPE NOTE: no GEMINI_API_KEY in `flutter test`, so the real built-in
// narrative branch (_fallbackStory) runs. With a key, the live branch also
// falls back to place.historicalFacts when RAG returns nothing (main.dart,
// generateContextAwareStory), so the source data is empty on both branches.
//
// MOCKED: Firebase platform layer, GeolocatorPlatform, flutter_tts channel,
// video_player native layer.

import 'package:flutter_test/flutter_test.dart';

import 'package:heritagebot/main.dart' as app;
import 'package:heritagebot/models/heritage_place.dart';
import 'package:heritagebot/services/heritage_site_service.dart';

import '../support/fake_video_player_platform.dart';
import '../support/heritagebot_fixtures.dart';

const FakeAuthAccount kTourist = FakeAuthAccount(
  uid: 'case033-tourist-uid',
  email: 'case033.tourist@heritagebot.test',
  password: 'Case033Pass!',
  displayName: 'Case 033 Tourist',
);

const HeritagePlace kSiteWithoutSources = HeritagePlace(
  id: 'site_with_no_verified_sources',
  name: 'Old Parian Marker',
  location: 'Colon Street, Cebu City',
  lat: 10.31570,
  lng: 123.88540,
  videoTitle: '',
  wikipediaTitle: '',
  detectionRadiusMeters: 20000,
  historicalFacts: '', // no verified source text
);

/// Wording a "no verified information" response would use.
final RegExp kNoEvidencePattern = RegExp(
  r'no (verified|reliable|relevant|historical|available)|'
  r'not (enough|available)|unavailable|insufficient|'
  r'could not find|cannot (provide|find|generate)',
  caseSensitive: false,
);

late HeritageBotTestBackend backend;
late FakeVideoPlayerPlatform video;

void main() {
  setUpAll(() async {
    backend = await HeritageBotTestBackend.install(accounts: [kTourist]);
    video = await FakeVideoPlayerPlatform.install();
  });

  setUp(() async {
    await backend.reset();
    video.clear();
    backend.seedTourist(kTourist);
    seedRegisteredSites(backend, [...defaultHeritagePlaces, kSiteWithoutSources]);
    placeTouristAt(
        backend, lat: kSiteWithoutSources.lat, lng: kSiteWithoutSources.lng);
  });

  testWidgets('CASE-033 - No relevant source data found: safe unavailable '
      'response', (WidgetTester tester) async {
    usePhoneSurface(tester);

    await HeritageSiteService().initializeRuntimeSites();
    final runtimeSite =
        heritagePlaces.singleWhere((s) => s.id == kSiteWithoutSources.id);
    // Fixture check: no verified source text exists for this site.
    expect(runtimeSite.historicalFacts.trim(), isEmpty);
    expect(
        backend.firestore.documents.keys
            .where((k) => k.startsWith('historical_contents/')),
        isEmpty);

    await signInBeforeLaunch(kTourist);
    await launchAuthGate(tester, until: app.MainShell);
    await openGeolocationTab(tester);
    await waitForNarrativePanel(tester);

    // ---- Observations ---------------------------------------------------
    final card = narrativeCard(tester);
    final story = card?.body ?? '';
    final panelTexts =
        textsUnder(tester, find.byType(app.NarrativeAutoPlaybackPanel));

    final observed = <String, Object?>{
      'narrativeAvailable': card != null &&
          card.title == en('contextStoryTitle') &&
          story.trim().isNotEmpty,
      'noEvidenceMessageVisible': panelTexts.any(kNoEvidencePattern.hasMatch),
    };
    printOnFailure('CASE-033 observed: $observed\n'
        'cardTitle="${card?.title}"\nnarrative shown to tourist:\n$story\n'
        'spokenByTts=${backend.channels.spokenTexts.length}');

    // ---- Expected result (unchanged from the original CASE-033) ---------
    expect(observed['narrativeAvailable'], equals(false),
        reason: 'CASE-033: narrativeAvailable does not match the real system result');
    expect(observed['noEvidenceMessageVisible'], equals(true),
        reason: 'CASE-033: noEvidenceMessageVisible does not match the real system result');

    await unmountApp(tester);
  });
}
