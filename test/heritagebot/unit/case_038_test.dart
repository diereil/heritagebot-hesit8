// HERITAGEBOT - TEST CASE 038
// Proponent: Reil Esdrelon
// Module: Tourist Heritage Access
// Unit: Translate Narrative
// Description: Choose supported language (targetLanguage = Cebuano).
// Expected: Display narrative in selected language.
//
// TEST TYPE: Flutter widget test (host VM, no device / live Firebase).
//
// REAL CODE UNDER TEST (lib/, unmodified)
//   ProfileScreen.profileLanguageSelector (options from
//   SystemSettingsService.enabledLanguagesForUi / supportedLanguages) ->
//   LanguageController.setLanguageCode -> LanguageService (preferred
//   language) -> GeolocationScreen.showPlacePopup ->
//   GeminiStoryService.generateContextAwareStory(preferredLanguage).
//   In HeritageBot the narrative language is the tourist's preferred
//   language chosen on the Profile screen.
//
// FIXTURE: English UI; bundled official site Fort San Pedro; GPS at site.
// The test tries to choose "Cebuano" exactly as specified by the test case.
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
  uid: 'case038-tourist-uid',
  email: 'case038.tourist@heritagebot.test',
  password: 'Case038Pass!',
  displayName: 'Case 038 Tourist',
);

const String kTargetLanguage = 'Cebuano';
final RegExp kCebuanoOption =
    RegExp(r'cebuano|bisaya|binisaya|sugbuanon', caseSensitive: false);

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

  testWidgets('CASE-038 - Choose supported language ($kTargetLanguage): '
      'narrative is displayed in the selected language',
      (WidgetTester tester) async {
    usePhoneSurface(tester);

    await signInBeforeLaunch(kTourist);
    await launchAuthGate(tester, until: app.MainShell);

    // STEP 1: Profile -> Language Settings -> open the language dropdown.
    await tapNavDestination(tester, en('profile'));
    await pumpUntilFound(tester, find.byType(app.ProfileScreen));
    final dropdown = find.descendant(
        of: find.byType(app.ProfileScreen),
        matching: find.byType(DropdownButtonFormField<String>));
    await scrollUntilBuilt(tester, dropdown, screen: app.ProfileScreen);
    await tapVisible(tester, dropdown);
    await pumpFor(tester, const Duration(milliseconds: 500));

    final offeredLanguages = tester
        .widgetList<DropdownMenuItem<String>>(
            find.byType(DropdownMenuItem<String>))
        .map((item) => (item.child as Text).data ?? '')
        .toSet()
        .toList();
    final cebuanoItem = find.descendant(
        of: find.byType(DropdownMenuItem<String>),
        matching: find.textContaining(kCebuanoOption));

    // STEP 2: choose Cebuano if HeritageBot offers it; otherwise close menu.
    final cebuanoOffered = cebuanoItem.evaluate().isNotEmpty;
    if (cebuanoOffered) {
      await tester.tap(cebuanoItem.last);
    } else {
      await tester.tapAt(const Offset(5, 5)); // dismiss the menu
    }
    await pumpFor(tester, const Duration(milliseconds: 600));
    final appliedLanguage = LanguageController.current.value;
    final savedLanguage = await LanguageService().getPreferredLanguage();

    // STEP 3: open a narrative (tourist at Fort San Pedro).
    await openGeolocationTab(tester);
    await waitForNarrativePanel(tester);
    final card = narrativeCard(tester);
    final story = card?.body ?? '';

    // English narrative = the template HeritageBot generates for 'en'.
    final englishTemplate = story.startsWith('Context-Aware Heritage Story');

    final observed = <String, Object?>{
      'translatedNarrativeVisible': cebuanoOffered &&
          story.trim().isNotEmpty &&
          !englishTemplate &&
          kCebuanoOption.hasMatch(appliedLanguage.name),
      'selectedLanguageApplied': cebuanoOffered &&
          kCebuanoOption.hasMatch(appliedLanguage.name) &&
          kCebuanoOption.hasMatch(savedLanguage.name),
    };
    printOnFailure('CASE-038 observed: $observed\n'
        'languagesOfferedInProfile=$offeredLanguages\n'
        'cebuanoOffered=$cebuanoOffered\n'
        'supportedLanguages=${supportedLanguages.map((l) => '${l.code}:${l.name}').toList()}\n'
        'languageByCode("ceb")=${languageByCode('ceb').name}\n'
        'appliedLanguage=${appliedLanguage.name}, saved=${savedLanguage.name}\n'
        'narrativeShown:\n$story');

    // ---- Expected result (unchanged from the original CASE-038) ---------
    expect(observed['translatedNarrativeVisible'], equals(true),
        reason: 'CASE-038: translatedNarrativeVisible does not match the real system result');
    expect(observed['selectedLanguageApplied'], equals(true),
        reason: 'CASE-038: selectedLanguageApplied does not match the real system result');

    await unmountApp(tester);
  });
}
