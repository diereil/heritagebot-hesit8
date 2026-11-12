// HERITAGEBOT - TEST CASE 028
// Proponent: Reil Esdrelon
// Module: Tourist Heritage Access
// Unit: Geolocation Detection
// Description: Enter configured heritage site radius.
// Expected: Detect nearby site and offer narrative.
//
// TEST TYPE: Flutter widget test (host VM, no device / live Firebase).
//
// REAL CODE UNDER TEST (lib/, unmodified)
//   GeolocationScreen.handleNewPosition -> LocationService.nearestPlace /
//   distanceToPlace -> `distance <= place.detectionRadiusMeters` ->
//   JournalService.getEntriesByPlace -> showPlacePopup ->
//   GeminiStoryService.generateContextAwareStory ->
//   NarrativeAutoPlaybackPanel -> NarrativeAudioService (text-to-speech).
//
// FIXTURE: the GPS fix is exactly at the bundled official site
// "Heritage of Cebu Monument" (good accuracy: 5 m).
//
// SCOPE NOTE: no GEMINI_API_KEY is defined in `flutter test`, so
// GeminiStoryService takes its real built-in offline branch
// (_fallbackStory) instead of calling the Gemini API.
//
// MOCKED: Firebase platform layer, GeolocatorPlatform, and the flutter_tts
// method channel (records what the app asks the phone to speak).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';

import 'package:heritagebot/main.dart' as app;
import 'package:heritagebot/models/heritage_place.dart';

import '../support/heritagebot_test_harness.dart';

const FakeAuthAccount kTourist = FakeAuthAccount(
  uid: 'case028-tourist-uid',
  email: 'case028.tourist@heritagebot.test',
  password: 'Case028Pass!',
  displayName: 'Case 028 Tourist',
);

late HeritageBotTestBackend backend;
late HeritagePlace site;

void main() {
  setUpAll(() async {
    backend = await HeritageBotTestBackend.install(accounts: [kTourist]);
  });

  setUp(() async {
    await backend.reset();
    backend.seedTourist(kTourist);
    site = defaultHeritagePlaces
        .singleWhere((s) => s.id == 'cebu_heritage_monument');
    backend.geolocator
      ..serviceEnabled = true
      ..permission = LocationPermission.whileInUse
      ..currentFix =
          fakeGpsFix(latitude: site.lat, longitude: site.lng, accuracy: 5);
  });

  testWidgets('CASE-028 - Enter heritage site radius: nearby site is detected '
      'and a narrative is offered', (WidgetTester tester) async {
    usePhoneSurface(tester);

    await signInBeforeLaunch(kTourist);
    await launchAuthGate(tester, until: app.MainShell);

    await tapNavDestination(tester, en('geolocation'));
    await pumpUntilFound(tester, find.byType(app.GeolocationScreen));
    await pumpUntilFound(tester, find.byType(app.NarrativeAutoPlaybackPanel));
    await pumpUntilFound(tester, find.text(en('contextStoryTitle')));
    await pumpFor(tester, const Duration(milliseconds: 500));

    // ---- Observations ---------------------------------------------------
    final sheet = find.byType(BottomSheet);
    final siteDetected = sheet.evaluate().isNotEmpty &&
        find
            .descendant(
                of: sheet, matching: find.byType(app.NarrativeAutoPlaybackPanel))
            .evaluate()
            .isNotEmpty;
    final correctSiteDetected = find
        .descendant(of: sheet, matching: find.text(site.name))
        .evaluate()
        .isNotEmpty;

    final storyCards = infoCardsTitled(tester, en('contextStoryTitle'));
    final story = storyCards.isEmpty ? '' : storyCards.single.body;

    // ---- Expected result -------------------------------------------------
    expect(siteDetected, isTrue,
        reason: 'CASE-028: entering the radius must open the site narrative.');
    expect(correctSiteDetected, isTrue,
        reason: 'CASE-028: the narrative must be for ${site.name}.');

    // Supporting evidence: a non-empty narrative is displayed and offered as
    // audio, about this site; the status shows the same nearest site.
    expect(story.trim(), isNotEmpty);
    expect(story, contains(site.name));
    expect(backend.channels.spokenTexts, contains(story),
        reason: 'The narrative must be sent to text-to-speech.');
    expect(find.textContaining('${en('nearest')}: ${site.name}'),
        findsOneWidget);

    await unmountApp(tester);
  });
}
