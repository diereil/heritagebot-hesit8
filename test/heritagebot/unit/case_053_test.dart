// HERITAGEBOT - TEST CASE 053
// Proponent: James Stephen O. Ramos
// Module: Community Contributor Management
// Unit: Upload Photos and Videos
// Description: Upload supported video.
// Expected: Attach video to submission.
//
// TEST TYPE: Flutter widget test (host VM, no device / live Firebase /
// live Cloudinary).
//
// REAL CODE UNDER TEST (lib/, unmodified)
//   SubmitCommunityStoryScreen: "Videos (0/2)" -> _pickVideo
//   (ImagePicker.pickVideo, gallery) -> selected-video card ->
//   "Submit for Review" -> CommunityMediaService.uploadVideos (exists /
//   60 MB check / multipart POST to Cloudinary) ->
//   CommunitySubmissionService.submitStory (videoUrls) ->
//   Firestore community_submissions/{id}.
//
// FIXTURE (fileFixture = supported_video): a real MP4 file
// "sinulog_procession.mp4" (well under the 60 MB video limit) chosen from
// the phone gallery.
//
// MOCKED: Firebase platform layer (in-memory Firestore), the phone's gallery
// picker (FakeImagePickerPlatform) and Cloudinary's upload endpoint
// (FakeCloudinary). Requires the Cloudinary --dart-define values described
// in support/fake_media_platforms.dart.

// image_picker_platform_interface is a transitive dependency of image_picker
// (already in pubspec.lock); pubspec.yaml is not modified.
// ignore_for_file: depend_on_referenced_packages

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';

import 'package:heritagebot/main.dart' as app;
import 'package:heritagebot/models/heritage_place.dart';

import '../support/contributor_flow.dart';
import '../support/fake_media_platforms.dart';
import '../support/heritagebot_fixtures.dart';
import '../support/story_submission_flow.dart';

const FakeAuthAccount kContributor = FakeAuthAccount(
  uid: 'case053-contributor-uid',
  email: 'case053.contributor@heritagebot.test',
  password: 'Case053Pass!',
  displayName: 'James Contributor',
);

const String kVideoName = 'sinulog_procession.mp4';
const String kTitle = 'Sinulog Procession Passing the Museum';
const String kStory =
    'This short video shows the Sinulog procession passing in front of the '
    'old house. My aunt explains how the devotees dance two steps forward and '
    'one step back, a prayer movement older than the festival itself.';

late HeritageBotTestBackend backend;
late FakeImagePickerPlatform gallery;
late FakeGalleryFolder phoneStorage;
final FakeCloudinary cloudinary = FakeCloudinary();

void main() {
  setUpAll(() async {
    backend = await HeritageBotTestBackend.install(accounts: [kContributor]);
    gallery = FakeImagePickerPlatform();
    ImagePickerPlatform.instance = gallery;
    phoneStorage = FakeGalleryFolder.create('case053');
  });

  tearDownAll(() => phoneStorage.delete());

  setUp(() async {
    await backend.reset();
    gallery.clear();
    cloudinary.clear();
    seedContributor(backend, kContributor);
  });

  group('', () {
    testWidgets('CASE-053 - Upload supported video', (
      WidgetTester tester,
    ) async {
      await http.runWithClient(() async {
        usePhoneSurface(tester);
        final video = phoneStorage.write(kVideoName, mp4Bytes());
        gallery.videoToPick = XFile(video.path, name: kVideoName);
        final place = officialHeritagePlaces.first;

        await signInBeforeLaunch(kContributor);
        await openSubmitStoryScreen(tester);

        // STEP: tap "Videos (0/2)" and choose the video in the gallery.
        final videosButton = find.text('Videos (0/2)');
        await tapVisible(tester, videosButton);
        await pumpFor(tester, const Duration(milliseconds: 300));
        final videoSelected =
            find.text('Videos (1/2)').evaluate().isNotEmpty &&
            find.text(kVideoName).evaluate().isNotEmpty;

        // STEP: fill in the story and tap "Submit for Review".
        final fields = fieldsOf(app.SubmitCommunityStoryScreen);
        await tester.enterText(fields.at(0), kTitle);
        await tester.enterText(fields.at(1), kStory);
        await tester.pump();
        final submit = find.text('Submit for Review');
        await scrollUntilBuilt(
          tester,
          submit,
          screen: app.SubmitCommunityStoryScreen,
        );
        await tapVisible(tester, submit);
        final finished = await pumpWithRealIoUntil(
          tester,
          () => shownSnackBarTexts(tester).isNotEmpty,
        );
        await pumpFor(tester, const Duration(milliseconds: 500));
        final snackBars = shownSnackBarTexts(tester);

        // ---- Observations -----------------------------------------------
        final stored = storedSubmissions(backend);
        final doc = stored.length == 1 ? stored.values.single : null;
        final docId = doc?['id'] as String?;
        final videoUrls =
            (doc?['videoUrls'] as List?)?.cast<String>() ?? const [];
        final upload = cloudinary.uploads.length == 1
            ? cloudinary.uploads.single
            : null;
        final cards = doc == null
            ? const <String, DashboardCard>{}
            : await collectDashboardCards(tester);

        final observed = <String, Object?>{
          // The chosen video was uploaded as a video and its URL is attached
          // to the saved submission.
          'videoAttached':
              videoSelected &&
              upload != null &&
              upload.resourceType == 'video' &&
              upload.fileName == kVideoName &&
              videoUrls.length == 1 &&
              videoUrls.single == upload.secureUrl &&
              ((doc?['imageUrls'] as List?) ?? const []).isEmpty,
          // ...and it belongs to THIS submission / contributor.
          'correctSubmissionLinked':
              doc != null &&
              upload != null &&
              doc['title'] == kTitle &&
              doc['contributorId'] == kContributor.uid &&
              doc['heritagePlaceId'] == place.id &&
              docId != null &&
              stored.containsKey('community_submissions/$docId') &&
              upload.folder ==
                  'heritagebot/community_submissions/${kContributor.uid}/$docId/videos' &&
              cards[kTitle]?.texts.contains('1 video') == true,
        };
        printOnFailure(
          'CASE-053 observed: $observed\nfinished=$finished '
          'snackBars=$snackBars\nuploads=${cloudinary.uploads}\n'
          'storedSubmissions=$stored\ndashboardCard=${cards[kTitle]}',
        );

        // ---- Expected result (unchanged from the original CASE-053) -----
        expect(
          observed['videoAttached'],
          equals(true),
          reason:
              'CASE-053: videoAttached does not match the real system result',
        );
        expect(
          observed['correctSubmissionLinked'],
          equals(true),
          reason:
              'CASE-053: correctSubmissionLinked does not match the real system result',
        );

        await unmountApp(tester);
      }, cloudinary.client);
    });
  }, skip: mediaTestSkip);
}
