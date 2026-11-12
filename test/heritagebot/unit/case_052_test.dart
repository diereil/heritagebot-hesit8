// HERITAGEBOT - TEST CASE 052
// Proponent: James Stephen O. Ramos
// Module: Community Contributor Management
// Unit: Upload Photos and Videos
// Description: Upload supported image.
// Expected: Attach image to submission.
//
// TEST TYPE: Flutter widget test (host VM, no device / live Firebase /
// live Cloudinary).
//
// REAL CODE UNDER TEST (lib/, unmodified)
//   SubmitCommunityStoryScreen: "Photos (0/5)" -> _pickPhotos
//   (ImagePicker.pickMultiImage) -> photo preview -> "Submit for Review" ->
//   CommunityMediaService.uploadImages (exists / 10 MB check / multipart
//   POST to Cloudinary) -> CommunitySubmissionService.submitStory
//   (imageUrls) -> Firestore community_submissions/{id}.
//
// FIXTURE (fileFixture = supported_photo): a real PNG photo file
// "magellans_cross_chapel.png" (well under the 10 MB photo limit) chosen
// from the phone gallery.
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
  uid: 'case052-contributor-uid',
  email: 'case052.contributor@heritagebot.test',
  password: 'Case052Pass!',
  displayName: 'James Contributor',
);

const String kTitle = 'Candles at the Chapel of the Cross';
const String kStory =
    'Every Friday my mother lit candles at the chapel that shelters the '
    'cross. This photo shows the painted ceiling she always asked us to look '
    'at, which tells the story of the first baptism in Cebu in 1521.';

late HeritageBotTestBackend backend;
late FakeImagePickerPlatform gallery;
late FakeGalleryFolder phoneStorage;
final FakeCloudinary cloudinary = FakeCloudinary();

void main() {
  setUpAll(() async {
    backend = await HeritageBotTestBackend.install(accounts: [kContributor]);
    gallery = FakeImagePickerPlatform();
    ImagePickerPlatform.instance = gallery;
    phoneStorage = FakeGalleryFolder.create('case052');
  });

  tearDownAll(() => phoneStorage.delete());

  setUp(() async {
    await backend.reset();
    gallery.clear();
    cloudinary.clear();
    seedContributor(backend, kContributor);
  });

  group('', () {
    testWidgets('CASE-052 - Upload supported image', (
      WidgetTester tester,
    ) async {
      await http.runWithClient(() async {
        usePhoneSurface(tester);
        final photo = phoneStorage.write(
          'magellans_cross_chapel.png',
          kTinyPngBytes,
        );
        gallery.photosToPick = [
          XFile(photo.path, name: 'magellans_cross_chapel.png'),
        ];
        final place = officialHeritagePlaces.first;

        await signInBeforeLaunch(kContributor);
        await openSubmitStoryScreen(tester);

        // STEP: tap "Photos (0/5)" and choose the photo in the gallery.
        await tapVisible(tester, find.text('Photos (0/5)'));
        await pumpFor(tester, const Duration(milliseconds: 300));
        final photoSelected = find.text('Photos (1/5)').evaluate().isNotEmpty;

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
        final previewError = tester.takeException();

        // ---- Observations -------------------------------------------------
        final stored = storedSubmissions(backend);
        final doc = stored.length == 1 ? stored.values.single : null;
        final docId = doc?['id'] as String?;
        final imageUrls =
            (doc?['imageUrls'] as List?)?.cast<String>() ?? const [];
        final upload = cloudinary.uploads.length == 1
            ? cloudinary.uploads.single
            : null;
        final cards = doc == null
            ? const <String, DashboardCard>{}
            : await collectDashboardCards(tester);

        final observed = <String, Object?>{
          // The chosen photo was uploaded as an image and its URL is attached
          // to the saved submission.
          'imageAttached':
              photoSelected &&
              upload != null &&
              upload.resourceType == 'image' &&
              upload.fileName == 'magellans_cross_chapel.png' &&
              imageUrls.length == 1 &&
              imageUrls.single == upload.secureUrl &&
              ((doc?['videoUrls'] as List?) ?? const []).isEmpty,
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
                  'heritagebot/community_submissions/${kContributor.uid}/$docId/images' &&
              cards[kTitle]?.texts.contains('1 photo') == true,
        };
        printOnFailure(
          'CASE-052 observed: $observed\nfinished=$finished '
          'snackBars=$snackBars previewError=$previewError\n'
          'uploads=${cloudinary.uploads}\nstoredSubmissions=$stored\n'
          'dashboardCard=${cards[kTitle]}',
        );

        // ---- Expected result (unchanged from the original CASE-052) -------
        expect(
          observed['imageAttached'],
          equals(true),
          reason:
              'CASE-052: imageAttached does not match the real system result',
        );
        expect(
          observed['correctSubmissionLinked'],
          equals(true),
          reason:
              'CASE-052: correctSubmissionLinked does not match the real system result',
        );

        await unmountApp(tester);
      }, cloudinary.client);
    });
  }, skip: mediaTestSkip);
}
