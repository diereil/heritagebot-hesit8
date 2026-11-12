// HERITAGEBOT - TEST CASE 036
// Proponent: Reil Esdrelon
// Module: Tourist Heritage Access
// Unit: Video and Audio Narrative
// Description: Play audio narration.
// Expected: Start audio for selected narrative.
//
// TEST TYPE: Flutter widget test (host VM, no device / live Firebase).
//
// REAL CODE UNDER TEST (lib/, unmodified)
//   GeolocationScreen -> showPlacePopup -> NarrativeAutoPlaybackPanel
//   ._playAutomatically -> NarrativeAudioService.speak -> flutter_tts.
//   (HeritageBot starts narration automatically once the narrative loads;
//   there is no separate "play" button.)
//
// FIXTURE (mediaFixture = narration_ready): bundled official site Casa
// Gorordo Museum; the tourist's GPS fix is at the site; English UI.
//
// MOCKED: Firebase platform layer, GeolocatorPlatform, video_player native
// layer, and the flutter_tts method channel, which records every call the
// app makes to the phone's text-to-speech engine and answers 1 (= success,
// as Android/iOS do). Hearing the actual voice requires a device.

import 'package:flutter_test/flutter_test.dart';

import 'package:heritagebot/main.dart' as app;
import 'package:heritagebot/models/heritage_place.dart';

import '../support/fake_video_player_platform.dart';
import '../support/heritagebot_fixtures.dart';

const FakeAuthAccount kTourist = FakeAuthAccount(
  uid: 'case036-tourist-uid',
  email: 'case036.tourist@heritagebot.test',
  password: 'Case036Pass!',
  displayName: 'Case 036 Tourist',
);

late HeritageBotTestBackend backend;
late FakeVideoPlayerPlatform video;
late HeritagePlace site;

void main() {
  setUpAll(() async {
    backend = await HeritageBotTestBackend.install(accounts: [kTourist]);
    video = await FakeVideoPlayerPlatform.install();
  });

  setUp(() async {
    await backend.reset();
    video.clear();
    backend.seedTourist(kTourist);
    site = bundledSite('casa_gorordo');
    placeTouristAt(backend, lat: site.lat, lng: site.lng);
  });

  testWidgets('CASE-036 - Play audio narration: audio starts for the '
      'selected narrative', (WidgetTester tester) async {
    usePhoneSurface(tester);

    await signInBeforeLaunch(kTourist);
    await launchAuthGate(tester, until: app.MainShell);
    await openGeolocationTab(tester);
    await waitForNarrativePanel(tester);
    await pumpFor(tester, const Duration(milliseconds: 500));

    // ---- Observations ---------------------------------------------------
    final card = narrativeCard(tester);
    final displayedNarrative = card?.body ?? '';
    final ttsCalls = backend.channels.ttsCalls;
    final spoken = backend.channels.spokenTexts;
    final languageCalls = ttsCalls
        .where((c) => c.method == 'setLanguage')
        .map((c) => c.arguments.toString())
        .toList();

    final observed = <String, Object?>{
      // The app asked the phone's TTS engine to speak, and it accepted.
      'audioPlaying': spoken.length == 1 && spoken.single.trim().isNotEmpty,
      // What is spoken is exactly the narrative displayed for this site.
      'correctNarrativeSelected': spoken.length == 1 &&
          card?.title == en('contextStoryTitle') &&
          spoken.single == displayedNarrative.trim() &&
          displayedNarrative.contains(site.name),
    };
    printOnFailure('CASE-036 observed: $observed\n'
        'ttsMethods=${ttsCalls.map((c) => c.method).toList()}\n'
        'setLanguage=$languageCalls\nspoken=$spoken');

    // ---- Expected result (unchanged from the original CASE-036) ---------
    expect(observed['audioPlaying'], equals(true),
        reason: 'CASE-036: audioPlaying does not match the real system result');
    expect(observed['correctNarrativeSelected'], equals(true),
        reason: 'CASE-036: correctNarrativeSelected does not match the real system result');
    // Supporting evidence: narration uses the tourist's language (English).
    expect(languageCalls, contains('en-US'));

    await unmountApp(tester);
  });
}
