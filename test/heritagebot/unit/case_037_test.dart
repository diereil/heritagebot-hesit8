// HERITAGEBOT - TEST CASE 037
// Proponent: Reil Esdrelon
// Module: Tourist Heritage Access
// Unit: Video and Audio Narrative
// Description: Media resource is missing.
// Expected: Show media unavailable message.
//
// TEST TYPE: Flutter widget test (host VM, no device / live Firebase).
//
// REAL CODE UNDER TEST (lib/, unmodified)
//   HeritageSiteService.initializeRuntimeSites -> HeritageSiteService search
//   -> HeritageSiteDetailScreen -> HeritageVideoPlayer
//   (VideoPlayerController.asset(...).initialize().catchError -> hasError).
//
// FIXTURE (mediaFixture = missing_media)
// The administrator-registered Magellan's Cross record (CASE-022 fixture)
// whose videoAsset points to a file that is NOT packaged in the app
// (assets/videos/magellans_cross_tour.mp4 - the bundle only contains
// magellans_cross.mp4). The test confirms the file is absent from the real
// AssetManifest, so opening it fails exactly as it would on a phone.
//
// MOCKED: Firebase platform layer and the video_player NATIVE layer
// (reports a load error for a source that is not in the asset bundle).

import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';

import 'package:heritagebot/main.dart' as app;
import 'package:heritagebot/models/heritage_place.dart';
import 'package:heritagebot/services/heritage_site_service.dart';

import '../support/fake_video_player_platform.dart';
import '../support/heritagebot_fixtures.dart';

const FakeAuthAccount kTourist = FakeAuthAccount(
  uid: 'case037-tourist-uid',
  email: 'case037.tourist@heritagebot.test',
  password: 'Case037Pass!',
  displayName: 'Case 037 Tourist',
);

const String kMissingVideo = 'assets/videos/magellans_cross_tour.mp4';
final HeritagePlace kSite = kMagellansCross.copyWith(videoAsset: kMissingVideo);

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
  });

  testWidgets('CASE-037 - Media resource is missing: media unavailable '
      'message is shown', (WidgetTester tester) async {
    usePhoneSurface(tester);

    // Fixture check: the referenced video is missing from the app bundle.
    expect(video.bundledAssets, isNot(contains(kMissingVideo)));

    await HeritageSiteService().initializeRuntimeSites();
    expect(heritagePlaces.singleWhere((s) => s.id == kSite.id).videoAsset,
        kMissingVideo);

    await signInBeforeLaunch(kTourist);
    await launchAuthGate(tester, until: app.HomeScreen);
    await openSiteDetailFromSearch(tester,
        query: 'Magellan', siteName: kSite.name);

    final player = find.byType(app.HeritageVideoPlayer);
    await scrollUntilBuilt(tester, player, screen: app.HeritageSiteDetailScreen);
    await pumpFor(tester, const Duration(seconds: 1));

    // ---- Observations ---------------------------------------------------
    final errorCards = tester
        .widgetList<app.InfoCard>(
            find.descendant(of: player, matching: find.byType(app.InfoCard)))
        .toList();

    final observed = <String, Object?>{
      'mediaAvailable':
          find.descendant(of: player, matching: find.byType(VideoPlayer))
              .evaluate()
              .isNotEmpty,
      'mediaUnavailableVisible': errorCards.any((c) =>
          RegExp('video', caseSensitive: false).hasMatch(c.title) &&
          RegExp(r'cannot be loaded|unavailable|not (found|available)',
                  caseSensitive: false)
              .hasMatch(c.body)),
    };
    printOnFailure('CASE-037 observed: $observed\n'
        'openedSources=${video.openedSources.map((s) => s.asset).toList()}\n'
        'messageShown=${errorCards.map((c) => '${c.title}: ${c.body}').toList()}');

    // ---- Expected result (unchanged from the original CASE-037) ---------
    expect(observed['mediaAvailable'], equals(false),
        reason: 'CASE-037: mediaAvailable does not match the real system result');
    expect(observed['mediaUnavailableVisible'], equals(true),
        reason: 'CASE-037: mediaUnavailableVisible does not match the real system result');
    // Supporting evidence: the app really tried to open the missing file.
    expect(video.openedSources.map((s) => s.asset), contains(kMissingVideo));

    await unmountApp(tester);
  });
}
