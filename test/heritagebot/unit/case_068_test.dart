// HERITAGEBOT - TEST CASE 068
// Proponent: James Stephen O. Ramos
// Module: User Profile Management
// Unit: Update Preferred Language
// Description: Select supported language.
// Expected: Save language preference.
//
// TEST TYPE: Flutter widget test (host VM, no device / live Firebase).
//
// REAL CODE UNDER TEST (lib/, unmodified)
//   ProfileScreen "Language Settings" -> "Preferred Language" dropdown
//   (items = SystemSettingsService.enabledLanguagesForUi) -> onChanged ->
//   LanguageController.setLanguageCode -> LanguageService
//   .savePreferredLanguageCode (SharedPreferences:
//   heritagebot_preferred_language + heritagebot_user_language_{uid}) ->
//   "Language preference saved." message.
//
// FIXTURE (language = Cebuano): the signed-in Tourist opens the dropdown
// and selects "Cebuano". The input is kept exactly as defined for CASE-068.
//
// MOCKED: Firebase platform layer; SharedPreferences uses Flutter's
// in-memory mock store (reset per test).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:heritagebot/main.dart' as app;
import 'package:heritagebot/services/language_service.dart';

import '../support/contributor_flow.dart';
import '../support/heritagebot_fixtures.dart';

const FakeAuthAccount kTourist = FakeAuthAccount(
  uid: 'case068-tourist-uid',
  email: 'case068.tourist@heritagebot.test',
  password: 'Case068Pass!',
  displayName: 'Andrea Villanueva',
);
const String kLanguage = 'Cebuano';

late HeritageBotTestBackend backend;

void main() {
  setUpAll(() async {
    backend = await HeritageBotTestBackend.install(accounts: [kTourist]);
  });

  setUp(() async {
    await backend.reset();
    backend.seedTourist(kTourist);
  });

  testWidgets('CASE-068 - Select supported language', (
    WidgetTester tester,
  ) async {
    usePhoneSurface(tester);

    await signInBeforeLaunch(kTourist);
    await launchAuthGate(tester, until: app.MainShell);
    await openProfileTab(tester);
    final languageBefore = LanguageController.current.value.code;

    // STEP: open the real "Preferred Language" dropdown.
    final dropdown = find.descendant(
      of: profileScreen,
      matching: find.byType(DropdownButtonFormField<String>),
    );
    await scrollUntilBuilt(tester, dropdown, screen: app.ProfileScreen);
    await tapVisible(tester, dropdown);
    await pumpFor(tester, const Duration(milliseconds: 400));

    // Languages listed in the open menu.
    final offered = tester
        .widgetList<DropdownMenuItem<String>>(
          find.byType(DropdownMenuItem<String>),
        )
        .map(
          (item) => item.child is Text ? (item.child as Text).data ?? '' : '',
        )
        .where((name) => name.isNotEmpty)
        .toSet()
        .toList();
    final cebuanoOffered = offered.any(
      (name) => name.toLowerCase().contains(kLanguage.toLowerCase()),
    );

    // STEP: select "Cebuano" (only possible if the app offers it).
    if (cebuanoOffered) {
      await tester.tap(find.textContaining(kLanguage).last);
    } else {
      // Close the menu without choosing anything (like tapping outside it).
      await tester.tapAt(const Offset(4, 4));
    }
    await pumpFor(tester, const Duration(milliseconds: 600));

    // ---- Observations ---------------------------------------------------
    final prefs = await SharedPreferences.getInstance();
    final savedGlobal = prefs.getString('heritagebot_preferred_language');
    final savedForUser = prefs.getString(
      'heritagebot_user_language_${kTourist.uid}',
    );
    final current = LanguageController.current.value;
    final messages = shownSnackBarTexts(tester);
    final supportedNames = supportedLanguages.map((l) => l.name).toList();

    bool isCebuano(String? code) =>
        code != null &&
        languageByCode(
          code,
        ).name.toLowerCase().contains(kLanguage.toLowerCase());

    final observed = <String, Object?>{
      'languagePreferenceSaved':
          cebuanoOffered &&
          savedForUser != null &&
          savedForUser == current.code &&
          messages.isNotEmpty,
      'correctLanguageStored':
          isCebuano(savedForUser) &&
          isCebuano(savedGlobal) &&
          current.name.toLowerCase().contains(kLanguage.toLowerCase()),
    };
    printOnFailure(
      'CASE-068 observed: $observed\n'
      'dropdownOffers=$offered cebuanoOffered=$cebuanoOffered\n'
      'supportedLanguages(lib)=$supportedNames\n'
      'languageBefore=$languageBefore current=${current.code}/${current.name}\n'
      'prefs.global=$savedGlobal prefs.user=$savedForUser messages=$messages',
    );

    // ---- Expected result (unchanged from the original CASE-068) ---------
    expect(
      observed['languagePreferenceSaved'],
      equals(true),
      reason:
          'CASE-068: languagePreferenceSaved does not match the real system result',
    );
    expect(
      observed['correctLanguageStored'],
      equals(true),
      reason:
          'CASE-068: correctLanguageStored does not match the real system result',
    );

    await unmountApp(tester);
  });
}
