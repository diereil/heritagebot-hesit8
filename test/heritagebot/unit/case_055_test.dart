// HERITAGEBOT - TEST CASE 055
// Proponent: James Stephen O. Ramos
// Module: Community Contributor Management
// Unit: Upload Photos and Videos
// Description: Upload file exceeding size limit.
// Expected: Reject oversized file.
//
// TEST TYPE: Flutter widget test (host VM, no device / live Firebase /
// live Cloudinary).
//
// REAL CODE UNDER TEST (lib/, unmodified)
//   SubmitCommunityStoryScreen: "Photos (0/5)" -> _pickPhotos ->
//   "Submit for Review" -> CommunityMediaService.uploadImages
//   (size > maxImageBytes = 10 MB check) -> error shown by _submit;
//   CommunitySubmissionService.submitStory must NOT be reached.
//
// FIXTURE (fileFixture = over_size_limit): a real photo file
// "cebu_panorama_raw.png" of exactly 10 MB + 1 byte
// (CommunityMediaService.maxImageBytes + 1), chosen from the phone gallery.
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
import 'package:heritagebot/services/community_media_service.dart';

import '../support/contributor_flow.dart';
import '../support/fake_media_platforms.dart';
import '../support/heritagebot_fixtures.dart';
import '../support/story_submission_flow.dart';

const FakeAuthAccount kContributor = FakeAuthAccount(
  uid: 'case055-contributor-uid',
  email: 'case055.contributor@heritagebot.test',
  password: 'Case055Pass!',
  displayName: 'James Contributor',
);

const String kFileName = 'cebu_panorama_raw.png';
const String kTitle = 'Panorama of the Old Cebu Skyline';
const String kStory =
    'I took this panorama from the hill above the city to show how the old '
    'church towers and the fort still stand out among new buildings, and how '
    'the shoreline has moved since my grandparents were young.';

late HeritageBotTestBackend backend;
late FakeImagePickerPlatform gallery;
late FakeGalleryFolder phoneStorage;
final FakeCloudinary cloudinary = FakeCloudinary();

void main() {
  setUpAll(() async {
    backend = await HeritageBotTestBackend.install(accounts: [kContributor]);
    gallery = FakeImagePickerPlatform();
    ImagePickerPlatform.instance = gallery;
    phoneStorage = FakeGalleryFolder.create('case055');
  });

  tearDownAll(() => phoneStorage.delete());

  setUp(() async {
    await backend.reset();
    gallery.clear();
    cloudinary.clear();
    seedContributor(backend, kContributor);
  });

  group('', () {
    testWidgets('CASE-055 - Upload file exceeding size limit', (
      WidgetTester tester,
    ) async {
      await http.runWithClient(() async {
        usePhoneSurface(tester);
        // Valid PNG data padded to exactly 10 MB + 1 byte.
        final size = CommunityMediaService.maxImageBytes + 1;
        final bytes = List<int>.filled(size, 0)
          ..setRange(0, kTinyPngBytes.length, kTinyPngBytes);
        final photo = phoneStorage.write(kFileName, bytes);
        expect(
          photo.lengthSync(),
          greaterThan(CommunityMediaService.maxImageBytes),
          reason: 'Precondition: the fixture exceeds the 10 MB photo limit.',
        );
        gallery.photosToPick = [XFile(photo.path, name: kFileName)];

        await signInBeforeLaunch(kContributor);
        await openSubmitStoryScreen(tester);

        // STEP: tap "Photos (0/5)" and choose the oversized photo.
        await tapVisible(tester, find.text('Photos (0/5)'));
        await pumpFor(tester, const Duration(milliseconds: 300));
        final addedToSelection = find
            .text('Photos (1/5)')
            .evaluate()
            .isNotEmpty;

        // STEP: complete the form and tap "Submit for Review".
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
        final messages = shownSnackBarTexts(tester);
        final previewError = tester.takeException();

        // ---- Observations -----------------------------------------------
        final stored = storedSubmissions(backend);
        final stillOnForm = find
            .byType(app.SubmitCommunityStoryScreen)
            .evaluate()
            .isNotEmpty;

        final observed = <String, Object?>{
          // Accepted = uploaded to Cloudinary or a submission was saved.
          'fileAccepted': cloudinary.uploads.isNotEmpty || stored.isNotEmpty,
          'sizeErrorVisible': messages.contains(
            'Each photo must be 10 MB or smaller.',
          ),
        };
        printOnFailure(
          'CASE-055 observed: $observed\n'
          'fileBytes=${photo.lengthSync()} addedToSelection=$addedToSelection '
          'finished=$finished stillOnForm=$stillOnForm\n'
          'messages=$messages previewError=$previewError\n'
          'uploads=${cloudinary.uploads}\nstoredSubmissions=$stored',
        );

        // ---- Expected result (unchanged from the original CASE-055) -----
        expect(
          observed['fileAccepted'],
          equals(false),
          reason:
              'CASE-055: fileAccepted does not match the real system result',
        );
        expect(
          observed['sizeErrorVisible'],
          equals(true),
          reason:
              'CASE-055: sizeErrorVisible does not match the real system result',
        );
        // Supporting evidence: the contributor stays on the form to fix it.
        expect(stillOnForm, isTrue);

        await unmountApp(tester);
      }, cloudinary.client);
    });
  }, skip: mediaTestSkip);
}
