// HERITAGEBOT - TEST CASE 039
// Proponent: Reil Esdrelon
// Module: Tourist Heritage Access
// Unit: Translate Narrative
// Description: Translation service fails.
// Expected: Keep original narrative and show error.
//
// TEST TYPE: Flutter widget test (host VM, no device / live Firebase).
//
// REAL CODE UNDER TEST (lib/, unmodified)
//   GeolocationScreen.showPlacePopup -> NarrativeAutoPlaybackPanel (the
//   narrative screen a tourist would translate), and
//   GeminiStoryService.translateNarrative (HeritageBot's translation
//   component).
//
// HOW THE TRANSLATION SERVICE FAILS (translationService = unavailable)
// translateNarrative calls Gemini. In `flutter test` no GEMINI_API_KEY is
// compiled in and all network traffic is blocked, so the real service
// fails (it throws "The translation service is unavailable ...").
//
// PROCEDURE
//  1. Tourist opens a narrative (GPS at Fort San Pedro, English).
//  2. Tourist looks for the translate action on the narrative and uses it.
//     If the narrative screen offers no translate action, the test calls the
//     real GeminiStoryService.translateNarrative with the displayed text (what
//     such an action would call) and checks whether the UI reports anything.
//  3. Observe: original narrative still shown? translation error shown?
//
// MOCKED: Firebase platform layer, GeolocatorPlatform, flutter_tts channel,
// video_player native layer.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:heritagebot/main.dart' as app;
import 'package:heritagebot/models/heritage_place.dart';
import 'package:heritagebot/services/language_service.dart';

import '../support/fake_video_player_platform.dart';
import '../support/heritagebot_fixtures.dart';

const FakeAuthAccount kTourist = FakeAuthAccount(
  uid: 'case039-tourist-uid',
  email: 'case039.tourist@heritagebot.test',
  password: 'Case039Pass!',
  displayName: 'Case 039 Tourist',
);

final RegExp kTranslateAction = RegExp(r'translat', caseSensitive: false);
final RegExp kTranslationError = RegExp(
  r'translat\w*.*(unavailable|could not|failed|error|try again)|'
  r'(unavailable|could not|failed|error).*translat',
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

  testWidgets('CASE-039 - Translation service fails: original narrative is '
      'kept and an error is shown', (WidgetTester tester) async {
    usePhoneSurface(tester);
    expect(app.geminiApiKey, isEmpty,
        reason: 'This case requires the translation service to be unavailable.');

    await signInBeforeLaunch(kTourist);
    await launchAuthGate(tester, until: app.MainShell);
    await openGeolocationTab(tester);
    await waitForNarrativePanel(tester);

    final originalNarrative = narrativeCard(tester)?.body ?? '';
    expect(originalNarrative.trim(), isNotEmpty,
        reason: 'Precondition: a narrative is displayed.');

    // STEP 2: look for a translate action on the narrative screen.
    final sheet = find.byType(BottomSheet);
    final translateControls = find.descendant(
      of: sheet,
      matching: find.byWidgetPredicate((w) =>
          (w is Icon &&
              (w.icon == Icons.translate_rounded ||
                  w.icon == Icons.translate ||
                  w.icon == Icons.g_translate)) ||
          (w is Text && kTranslateAction.hasMatch(w.data ?? ''))),
    );
    final translateActionOffered = translateControls.evaluate().isNotEmpty;

    String? serviceError;
    if (translateActionOffered) {
      await tester.tap(translateControls.first, warnIfMissed: false);
      await pumpFor(tester, const Duration(seconds: 2));
    } else {
      // What a translate action would call - the real translation component.
      try {
        await app.GeminiStoryService().translateNarrative(
          narrative: originalNarrative,
          sourceLanguage: languageByCode('en'),
          targetLanguage: languageByCode('fil'),
        );
      } catch (error) {
        serviceError = error.toString();
      }
      await pumpFor(tester, const Duration(seconds: 1));
    }

    // ---- Observations ---------------------------------------------------
    final narrativeAfter = narrativeCard(tester)?.body ?? '';
    final errorOnScreen = anyTextMatches(tester, sheet, kTranslationError) ||
        anyTextMatches(tester, find.byType(SnackBar), kTranslationError) ||
        anyTextMatches(tester, find.byType(AlertDialog), kTranslationError);

    final observed = <String, Object?>{
      'originalNarrativePreserved': narrativeAfter == originalNarrative,
      'translationErrorVisible': errorOnScreen,
    };
    printOnFailure('CASE-039 observed: $observed\n'
        'translateActionOfferedOnNarrative=$translateActionOffered\n'
        'translationServiceResult=${serviceError ?? '(no exception)'}');

    // ---- Expected result (unchanged from the original CASE-039) ---------
    expect(observed['originalNarrativePreserved'], equals(true),
        reason: 'CASE-039: originalNarrativePreserved does not match the real system result');
    expect(observed['translationErrorVisible'], equals(true),
        reason: 'CASE-039: translationErrorVisible does not match the real system result');

    await unmountApp(tester);
  });
}
