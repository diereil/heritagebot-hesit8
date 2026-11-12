// HERITAGEBOT - TEST CASE 035
// Proponent: Reil Esdrelon
// Module: Tourist Heritage Access
// Unit: Video and Audio Narrative
// Description: Open available site video.
// Expected: Play or display associated video.
//
// TEST TYPE: Flutter widget test (host VM, no device / live Firebase).
//
// REAL CODE UNDER TEST (lib/, unmodified)
//   Home -> HeritageSiteSearchScreen -> HeritageSiteDetailScreen
//   ("Heritage Video" section) -> HeritageVideoPlayer ->
//   VideoPlayerController.asset(site.videoAsset) -> VideoPlayer -> Play.
//
// FIXTURE (mediaFixture = valid_video): bundled official site Fort San
// Pedro, whose record points to assets/videos/fort_san_pedro.mp4. The test
// confirms that file is really packaged in the app (AssetManifest).
//
// MOCKED: Firebase platform layer and the video_player NATIVE layer
// (FakeVideoPlayerPlatform: opens a source only if it exists in the real
// asset bundle). Actual on-screen decoding/sound needs a device.

import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';

import 'package:heritagebot/main.dart' as app;
import 'package:heritagebot/models/heritage_place.dart';

import '../support/fake_video_player_platform.dart';
import '../support/heritagebot_fixtures.dart';

const FakeAuthAccount kTourist = FakeAuthAccount(
  uid: 'case035-tourist-uid',
  email: 'case035.tourist@heritagebot.test',
  password: 'Case035Pass!',
  displayName: 'Case 035 Tourist',
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
  });

  testWidgets('CASE-035 - Open available site video: the associated video '
      'is displayed and plays', (WidgetTester tester) async {
    usePhoneSurface(tester);

    // Fixture check: the site's video file is packaged with the app.
    expect(site.videoAsset, 'assets/videos/fort_san_pedro.mp4');
    expect(video.bundledAssets, contains(site.videoAsset));

    await signInBeforeLaunch(kTourist);
    await launchAuthGate(tester, until: app.HomeScreen);
    await openSiteDetailFromSearch(tester,
        query: 'Fort San Pedro', siteName: site.name);

    // Scroll to the "Heritage Video" section and wait for the player.
    await scrollUntilBuilt(tester, find.byType(app.HeritageVideoPlayer),
        screen: app.HeritageSiteDetailScreen);
    await pumpUntilFound(tester, find.byType(VideoPlayer));
    final playButton = find.descendant(
        of: find.byType(app.HeritageVideoPlayer),
        matching: find.text('Play Video'));
    await scrollUntilBuilt(tester, playButton,
        screen: app.HeritageSiteDetailScreen);
    await tapVisible(tester, playButton);
    await pumpFor(tester, const Duration(milliseconds: 300));

    // ---- Observations ---------------------------------------------------
    final player = find.byType(app.HeritageVideoPlayer);
    final opened = video.openedSources;
    final controller =
        tester.widget<VideoPlayer>(find.byType(VideoPlayer)).controller;

    final observed = <String, Object?>{
      'videoAvailable': find
              .descendant(of: player, matching: find.byType(VideoPlayer))
              .evaluate()
              .isNotEmpty &&
          controller.value.isInitialized &&
          find.text('Video Error').evaluate().isEmpty,
      'correctVideoOpened': opened.length == 1 &&
          opened.single.sourceType == DataSourceType.asset &&
          opened.single.asset == site.videoAsset &&
          find
              .descendant(of: player, matching: find.text(site.videoTitle))
              .evaluate()
              .isNotEmpty,
    };
    final playing = controller.value.isPlaying &&
        video.playCalls.isNotEmpty &&
        find
            .descendant(of: player, matching: find.text('Pause Video'))
            .evaluate()
            .isNotEmpty;
    printOnFailure('CASE-035 observed: $observed, playing=$playing, '
        'openedSources=${opened.map((s) => s.asset).toList()}');

    // ---- Expected result (unchanged from the original CASE-035) ---------
    expect(observed['videoAvailable'], equals(true),
        reason: 'CASE-035: videoAvailable does not match the real system result');
    expect(observed['correctVideoOpened'], equals(true),
        reason: 'CASE-035: correctVideoOpened does not match the real system result');
    // Supporting evidence: tapping "Play Video" starts playback.
    expect(playing, isTrue, reason: 'Play Video must start the video.');

    await unmountApp(tester);
  });
}
