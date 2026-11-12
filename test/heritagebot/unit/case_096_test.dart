// HERITAGEBOT - TEST CASE 096
// Proponent: Shawn Guillmar C. Morales
// Module: Community Contribution Review
// Unit: View Attached Media
// Description: Open story attachments
// Expected: Display linked media
//
// TEST TYPE: Flutter widget test (host VM, no device / live Firebase /
// live Cloudinary).
//
// REAL CODE UNDER TEST (lib/, unmodified)
//   AuthGate -> AdminShell -> "Review" -> tap the story ->
//   AdminReviewSubmissionScreen: "Attached Photos" (Image.network for each
//   imageUrls entry) and "Attached Videos" (LocalJournalVideoPlayer ->
//   VideoPlayerController.networkUrl for each videoUrls entry).
//
// FIXTURE (fixtureId = CASE-096): a PENDING story with two photos and one
// video (Cloudinary secure_urls, as CommunityMediaService stores them), and
// a second story with its own, different photo.
//
// MOCKED: Firebase platform layer, and Cloudinary's delivery CDN
// (FakeMediaCdn: serves the fixture PNG for the photo URLs and reports the
// video URL as streamable to the fake video_player native layer). The real
// Image / NetworkImage / VideoPlayerController code runs unmodified.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:heritagebot/main.dart' as app;
import 'package:heritagebot/models/community_submission.dart';

import '../support/admin_operations_flow.dart';
import '../support/fake_media_cdn.dart';
import '../support/fake_media_platforms.dart' show kTinyPngBytes, pumpWithRealIoUntil;

const String kCdn = 'https://res.cloudinary.com/heritagebot-test';
const List<String> kPhotos = [
  '$kCdn/image/upload/v1/heritagebot/community_submissions/case096-media/images/0_kiosk.png',
  '$kCdn/image/upload/v1/heritagebot/community_submissions/case096-media/images/1_candles.png',
];
const String kVideo =
    '$kCdn/video/upload/v1/heritagebot/community_submissions/case096-media/videos/0_procession.mp4';
const String kOtherPhoto =
    '$kCdn/image/upload/v1/heritagebot/community_submissions/case096-other/images/0_fort.png';

const String kTitle = 'Procession at the Cross';

late HeritageBotTestBackend backend;
final FakeMediaCdn cdn = FakeMediaCdn();

void main() {
  setUpAll(() async {
    backend = await HeritageBotTestBackend.install(accounts: [kAdminAccount]);
  });

  setUp(() async {
    await backend.reset();
    cdn.requestedPhotoUrls.clear();
    cdn.openedVideoUrls.clear();
    for (final url in [...kPhotos, kOtherPhoto]) {
      cdn.photos[url] = kTinyPngBytes;
    }
    cdn.videos.add(kVideo);
    seedRegisteredSites(backend, [kMagellansCross, bundledSite('fort_san_pedro')]);
    final story = storyFixture(id: 'case096-media', title: kTitle, status: CommunitySubmissionStatus.pending, site: kMagellansCross);
    seedStory(backend, CommunitySubmission(
      id: story.id, contributorId: story.contributorId, contributorName: story.contributorName,
      contributorEmail: story.contributorEmail, heritagePlaceId: story.heritagePlaceId,
      heritagePlaceName: story.heritagePlaceName, title: story.title, story: story.story,
      status: story.status, adminFeedback: story.adminFeedback,
      imageUrls: kPhotos, videoUrls: const [kVideo],
      createdAtMillis: story.createdAtMillis, updatedAtMillis: story.updatedAtMillis,
    ));
    final other = storyFixture(id: 'case096-other', title: 'Fort Walls at Dusk', status: CommunitySubmissionStatus.pending, site: bundledSite('fort_san_pedro'));
    seedStory(backend, CommunitySubmission(
      id: other.id, contributorId: 'fixture-contributor-2', contributorName: 'Jose Ramos',
      contributorEmail: other.contributorEmail, heritagePlaceId: other.heritagePlaceId,
      heritagePlaceName: other.heritagePlaceName, title: other.title, story: other.story,
      status: other.status, adminFeedback: '', imageUrls: const [kOtherPhoto], videoUrls: const [],
      createdAtMillis: other.createdAtMillis, updatedAtMillis: other.updatedAtMillis,
    ));
  });

  testWidgets('CASE-096 - Open story attachments', (WidgetTester tester) async {
    usePhoneSurface(tester);
    cdn.install();
    addTearDown(cdn.uninstall);

    await openAdminShell(tester);
    await openReviewTab(tester);
    await openReviewCard(tester, kTitle);

    // Let NetworkImage download (FakeMediaCdn) and decode, and the video
    // controller initialise.
    final photosHeading = find.descendant(of: reviewDetailScreen, matching: find.text('Attached Photos'));
    final videosHeading = find.descendant(of: reviewDetailScreen, matching: find.text('Attached Videos'));
    await scrollUntilBuilt(tester, photosHeading, screen: app.AdminReviewSubmissionScreen);
    final photosHeadingShown = photosHeading.evaluate().isNotEmpty;
    await scrollUntilBuilt(tester, videosHeading, screen: app.AdminReviewSubmissionScreen);
    final videosHeadingShown = videosHeading.evaluate().isNotEmpty;
    bool photosDecoded() => tester
        .widgetList<RawImage>(find.descendant(of: reviewDetailScreen, matching: find.byType(RawImage)))
        .where((r) => r.image != null)
        .length >= kPhotos.length;
    final mediaReady = await pumpWithRealIoUntil(
      tester,
      () => photosDecoded() && cdn.videoPlayer.initializedPlayers.isNotEmpty,
      maxRounds: 200,
    );

    // ---- Observations -----------------------------------------------------
    final images = tester
        .widgetList<Image>(find.descendant(of: reviewDetailScreen, matching: find.byType(Image)))
        .where((i) => i.image is NetworkImage)
        .map((i) => (i.image as NetworkImage).url)
        .toList();
    final players = tester
        .widgetList<app.LocalJournalVideoPlayer>(
          find.descendant(of: reviewDetailScreen, matching: find.byType(app.LocalJournalVideoPlayer)),
        )
        .map((p) => p.filePath)
        .toList();
    final brokenPhotoIcons = find
        .descendant(of: reviewDetailScreen, matching: find.byIcon(Icons.broken_image_rounded))
        .evaluate()
        .length;
    // LocalJournalVideoPlayer's error state: Icons.error_rounded card.
    final videoErrorShown = find
        .descendant(of: reviewDetailScreen, matching: find.byIcon(Icons.error_rounded))
        .evaluate()
        .isNotEmpty;
    final detail = tester.widget<app.AdminReviewSubmissionScreen>(reviewDetailScreen);

    final observed = <String, Object?>{
      'storyMediaVisible':
          photosHeadingShown &&
          videosHeadingShown &&
          mediaReady &&
          photosDecoded() &&
          brokenPhotoIcons == 0 &&
          cdn.videoPlayer.initializedPlayers.length == 1 &&
          !videoErrorShown,
      'correctStoryLinked':
          detail.submission.id == 'case096-media' &&
          images.toSet().containsAll(kPhotos) &&
          images.length == kPhotos.length &&
          !images.contains(kOtherPhoto) &&
          players.length == 1 &&
          players.single == kVideo &&
          cdn.openedVideoUrls.contains(kVideo) &&
          !cdn.requestedPhotoUrls.contains(kOtherPhoto),
    };
    printOnFailure(
      'CASE-096 observed: $observed\nheadings photos=$photosHeadingShown '
      'videos=$videosHeadingShown decodedNow=${photosDecoded()}\n'
      'mediaReady=$mediaReady images=$images\n'
      'players=$players brokenPhotoIcons=$brokenPhotoIcons videoErrorShown=$videoErrorShown\n'
      'cdnPhotoRequests=${cdn.requestedPhotoUrls}\ncdnVideoOpens=${cdn.openedVideoUrls}',
    );
    // ignore: avoid_print
    print('CASE-096 evidence: observed=$observed images=${images.length} videos=$players');

    // ---- Expected result (unchanged from the original CASE-096) ----------
    expect(
      observed['storyMediaVisible'],
      equals(true),
      reason: 'CASE-096: storyMediaVisible does not match the real system result',
    );
    expect(
      observed['correctStoryLinked'],
      equals(true),
      reason: 'CASE-096: correctStoryLinked does not match the real system result',
    );

    await unmountApp(tester);
    cdn.uninstall();
  });
}
