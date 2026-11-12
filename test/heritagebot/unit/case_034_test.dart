// HERITAGEBOT - TEST CASE 034
// Proponent: Reil Esdrelon
// Module: Tourist Heritage Access
// Unit: AI Historical Narrative
// Description: AI service becomes unavailable.
// Expected: Show retry or service error (and no AI narrative).
//
// TEST TYPE: Flutter widget test (host VM, no device / live Firebase).
//
// REAL CODE UNDER TEST (lib/, unmodified)
//   GeolocationScreen.handleNewPosition -> showPlacePopup ->
//   GeminiStoryService.generateContextAwareStory -> NarrativeAutoPlaybackPanel
//   (which has a dedicated "Narrative Unavailable" error card).
//
// HOW THE AI SERVICE IS UNAVAILABLE (aiService = unavailable)
// The Gemini service cannot be reached in this run: no GEMINI_API_KEY is
// compiled in (`flutter test` passes no --dart-define), and the test binding
// blocks all network traffic (every HTTP request returns 400). On a phone,
// an expired key, quota error, timeout or lost connection reaches the SAME
// code: generateContextAwareStory returns _fallbackStory() for a missing key,
// a non-200 response and any exception alike (main.dart lines ~517-676).
//
// FIXTURE: bundled official site Fort San Pedro; GPS fix at the site.
//
// MOCKED: Firebase platform layer, GeolocatorPlatform, flutter_tts channel,
// video_player native layer.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:heritagebot/main.dart' as app;
import 'package:heritagebot/models/heritage_place.dart';

import '../support/fake_video_player_platform.dart';
import '../support/heritagebot_fixtures.dart';

const FakeAuthAccount kTourist = FakeAuthAccount(
  uid: 'case034-tourist-uid',
  email: 'case034.tourist@heritagebot.test',
  password: 'Case034Pass!',
  displayName: 'Case 034 Tourist',
);

final RegExp kServiceErrorPattern = RegExp(
  r'unavailable|service error|could not|cannot|try again|retry|'
  r'offline|failed|error',
  caseSensitive: false,
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
    site = bundledSite('fort_san_pedro');
    placeTouristAt(backend, lat: site.lat, lng: site.lng);
  });

  testWidgets('CASE-034 - AI service becomes unavailable: retry or service '
      'error is shown', (WidgetTester tester) async {
    usePhoneSurface(tester);

    // Precondition: the AI service really is unreachable in this run.
    expect(app.geminiApiKey, isEmpty,
        reason: 'This case requires the Gemini service to be unavailable.');

    await signInBeforeLaunch(kTourist);
    await launchAuthGate(tester, until: app.MainShell);
    await openGeolocationTab(tester);
    await waitForNarrativePanel(tester);

    // ---- Observations ---------------------------------------------------
    final panel = find.byType(app.NarrativeAutoPlaybackPanel);
    final card = narrativeCard(tester);
    final story = card?.body ?? '';
    final retryButtonVisible = find
        .descendant(
            of: find.byType(BottomSheet),
            matching: find.textContaining(
                RegExp('retry|try again', caseSensitive: false)))
        .evaluate()
        .isNotEmpty;
    final errorInPanel =
        anyTextMatches(tester, panel, kServiceErrorPattern);
    final errorSnackBar = anyTextMatches(
        tester, find.byType(SnackBar), kServiceErrorPattern);

    final observed = <String, Object?>{
      'narrativeAvailable': card != null &&
          card.title == en('contextStoryTitle') &&
          story.trim().isNotEmpty,
      'serviceErrorVisible': retryButtonVisible || errorInPanel || errorSnackBar,
    };
    printOnFailure('CASE-034 observed: $observed\n'
        'cardTitle="${card?.title}"\n'
        'retryButton=$retryButtonVisible errorInPanel=$errorInPanel '
        'errorSnackBar=$errorSnackBar\n'
        'narrative shown while Gemini was unreachable:\n$story');

    // ---- Expected result (unchanged from the original CASE-034) ---------
    expect(observed['narrativeAvailable'], equals(false),
        reason: 'CASE-034: narrativeAvailable does not match the real system result');
    expect(observed['serviceErrorVisible'], equals(true),
        reason: 'CASE-034: serviceErrorVisible does not match the real system result');

    await unmountApp(tester);
  });
}
