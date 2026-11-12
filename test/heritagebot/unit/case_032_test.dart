// HERITAGEBOT - TEST CASE 032
// Proponent: Reil Esdrelon
// Module: Tourist Heritage Access
// Unit: AI Historical Narrative
// Description: Request narrative for supported site.
// Expected: Show narrative grounded in site records.
//
// TEST TYPE: Flutter widget test (host VM, no device / live Firebase).
//
// REAL CODE UNDER TEST (lib/, unmodified)
//   HeritageSiteService.initializeRuntimeSites -> GeolocationScreen
//   .handleNewPosition (inside trigger radius) -> showPlacePopup ->
//   GeminiStoryService.generateContextAwareStory -> NarrativeAutoPlaybackPanel.
//
// FIXTURE (siteFixture = magellans_cross): the administrator-registered
// Magellan's Cross record (same as CASE-022). The tourist's GPS fix is at
// the site. "Site records" = the site's verified historicalFacts in
// Firestore `heritage_sites/magellans_cross`.
//
// SCOPE NOTE (aiService = available)
// `flutter test` runs without --dart-define=GEMINI_API_KEY and without
// network access, so GeminiStoryService takes its real built-in narrative
// branch (_fallbackStory) - the same code the phone runs when no Gemini key
// is configured. The live Gemini + knowledge-base (RAG) branch can only be
// exercised on a device/emulator build that has the API key and internet.
//
// MOCKED: Firebase platform layer, GeolocatorPlatform, flutter_tts channel,
// video_player native layer.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:heritagebot/main.dart' as app;
import 'package:heritagebot/models/heritage_place.dart';
import 'package:heritagebot/services/heritage_site_service.dart';

import '../support/fake_video_player_platform.dart';
import '../support/heritagebot_fixtures.dart';

const FakeAuthAccount kTourist = FakeAuthAccount(
  uid: 'case032-tourist-uid',
  email: 'case032.tourist@heritagebot.test',
  password: 'Case032Pass!',
  displayName: 'Case 032 Tourist',
);

const HeritagePlace kSite = kMagellansCross;

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
    seedRegisteredSites(backend, [...defaultHeritagePlaces, kSite]);
    placeTouristAt(backend, lat: kSite.lat, lng: kSite.lng);
  });

  testWidgets('CASE-032 - Request narrative for supported site: narrative is '
      'grounded in the site record', (WidgetTester tester) async {
    usePhoneSurface(tester);

    await HeritageSiteService().initializeRuntimeSites();
    expect(heritagePlaces.map((s) => s.id), contains(kSite.id));

    await signInBeforeLaunch(kTourist);
    await launchAuthGate(tester, until: app.MainShell);
    await openGeolocationTab(tester);
    await waitForNarrativePanel(tester);

    // ---- Observations ---------------------------------------------------
    final sheet = find.byType(BottomSheet);
    final card = narrativeCard(tester);
    final story = card?.body ?? '';
    final sheetIsForSite = find
        .descendant(of: sheet, matching: find.text(kSite.name))
        .evaluate()
        .isNotEmpty;

    final observed = <String, Object?>{
      'narrativeAvailable': card != null &&
          card.title == en('contextStoryTitle') &&
          story.trim().isNotEmpty,
      // Every verified fact shown comes from the site's own record.
      'groundedInSiteSources': sheetIsForSite &&
          story.contains(kSite.name) &&
          story.contains(kSite.historicalFacts),
    };
    printOnFailure('CASE-032 observed: $observed\n'
        'cardTitle="${card?.title}"\nnarrative:\n$story');

    // ---- Expected result (unchanged from the original CASE-032) ---------
    expect(observed['narrativeAvailable'], equals(true),
        reason: 'CASE-032: narrativeAvailable does not match the real system result');
    expect(observed['groundedInSiteSources'], equals(true),
        reason: 'CASE-032: groundedInSiteSources does not match the real system result');

    await unmountApp(tester);
  });
}
