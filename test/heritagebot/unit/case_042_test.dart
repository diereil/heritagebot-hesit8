// HERITAGEBOT - TEST CASE 042
// Proponent: Reil Esdrelon
// Module: Tourist Heritage Access
// Unit: Saved History
// Description: Open saved history.
// Expected: Display previously saved narrative history.
//
// TEST TYPE: Flutter widget test (host VM, no device / live Firebase).
//
// REAL CODE UNDER TEST (lib/, unmodified)
//   AuthGate -> MainShell (tourist) and every destination a tourist can
//   reach from it: Home, Stories (CommunityStoriesScreen), My Journal
//   (MyJournalScreen / JournalService), Profile (ProfileScreen) and
//   Profile -> View Bookmarked Sites (BookmarkedSitesScreen).
//
// FIXTURE (fixtureId = CASE-042)
// The tourist previously received an AI narrative for Fort San Pedro. It is
// stored in `ai_narratives/{id}` in exactly the shape that
// AiNarrativeService.recordGeneratedNarrative writes after a successful
// Gemini generation (this is the only place HeritageBot saves generated
// narratives).
//
// The test opens the tourist's screens looking for a saved-history entry
// point and for the previously saved narrative.
// (The Geolocation tab is a live map with no saved content and is skipped.)
//
// MOCKED: Firebase platform layer only (in-memory Firestore).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:heritagebot/main.dart' as app;
import 'package:heritagebot/models/ai_narrative_record.dart';
import 'package:heritagebot/models/heritage_place.dart';

import '../support/heritagebot_fixtures.dart';

const FakeAuthAccount kTourist = FakeAuthAccount(
  uid: 'case042-tourist-uid',
  email: 'case042.tourist@heritagebot.test',
  password: 'Case042Pass!',
  displayName: 'Case 042 Tourist',
);

const String kSavedPhrase =
    'the coral-stone walls of Fort San Pedro once guarded Cebu harbour';

/// Short UI labels (tabs, titles, buttons, list entries) naming a history.
final RegExp kHistoryEntryPoint = RegExp(
  r'^(saved |narrative |my |story |view |viewing )*(narrative )?history',
  caseSensitive: false,
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
    site = bundledSite('fort_san_pedro');
    backend.firestore.seedDocument('ai_narratives/case042-narrative-1', {
      'userId': kTourist.uid,
      'siteId': site.id,
      'siteName': site.name,
      'narrative': 'Welcome back to ${site.name}! Long ago, $kSavedPhrase.',
      'languageCode': 'en',
      'modelName': app.geminiModel,
      'retrievalMode': 'site_record',
      'retrievedContentIds': <String>[],
      'retrievedSourceTitles': <String>['HeritageBot site record'],
      'distanceMeters': 12.0,
      'reviewStatus': AiNarrativeReviewStatus.pendingReview,
      'adminReviewNote': '',
      'createdAtMillis': 1767225600000,
      'reviewedAtMillis': 0,
    });
  });

  testWidgets('CASE-042 - Open saved history: previously saved narrative '
      'history is displayed', (WidgetTester tester) async {
    usePhoneSurface(tester);

    await signInBeforeLaunch(kTourist);
    await launchAuthGate(tester, until: app.MainShell);

    final navLabels = textsUnder(tester, find.byType(NavigationBar));
    final screensVisited = <String, List<String>>{};

    Future<void> visit(String name, Type screen) async {
      await pumpUntilFound(tester, find.byType(screen));
      await pumpFor(tester, const Duration(milliseconds: 500));
      screensVisited[name] = textsUnder(tester, find.byType(screen));
    }

    await tapNavDestination(tester, en('home'));
    await visit('Home', app.HomeScreen);
    await tapNavDestination(tester, 'Stories');
    await visit('Stories', app.CommunityStoriesScreen);
    await tapNavDestination(tester, en('myJournal'));
    await visit('My Journal', app.MyJournalScreen);
    await tapNavDestination(tester, en('profile'));
    await visit('Profile', app.ProfileScreen);
    await openBookmarkedSitesFromProfile(tester);
    await visit('Bookmarked Sites', app.BookmarkedSitesScreen);

    // ---- Observations ---------------------------------------------------
    final allTexts = <String>[
      ...navLabels,
      for (final texts in screensVisited.values) ...texts,
    ];
    final historyEntryPoints = allTexts
        .where((t) => t.length <= 40 && kHistoryEntryPoint.hasMatch(t.trim()))
        .toList();
    final narrativeShown = allTexts.any((t) => t.contains(kSavedPhrase));

    final observed = <String, Object?>{
      'historyVisible': historyEntryPoints.isNotEmpty,
      'previousNarrativesLoaded': narrativeShown,
    };
    printOnFailure('CASE-042 observed: $observed\n'
        'touristNavigation=$navLabels\n'
        'historyEntryPointsFound=$historyEntryPoints\n'
        'screensVisited=${screensVisited.keys.toList()}\n'
        'myJournalShows=${screensVisited['My Journal']}');

    // ---- Expected result (unchanged from the original CASE-042) ---------
    expect(observed['historyVisible'], equals(true),
        reason: 'CASE-042: historyVisible does not match the real system result');
    expect(observed['previousNarrativesLoaded'], equals(true),
        reason: 'CASE-042: previousNarrativesLoaded does not match the real system result');

    await unmountApp(tester);
  });
}
