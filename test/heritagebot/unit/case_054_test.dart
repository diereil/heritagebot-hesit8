// HERITAGEBOT - TEST CASE 054
// Proponent: James Stephen O. Ramos
// Module: Community Contributor Management
// Unit: Upload Photos and Videos
// Description: Upload unsupported file type.
// Expected: Reject file and explain format.
//
// TEST TYPE: Flutter widget test (host VM, no device / live Firebase /
// live Cloudinary).
//
// REAL CODE UNDER TEST (lib/, unmodified)
//   SubmitCommunityStoryScreen: "Photos (0/5)" -> _pickPhotos
//   (ImagePicker.pickMultiImage) -> "Submit for Review" ->
//   CommunityMediaService.uploadImages -> CommunitySubmissionService
//   .submitStory.
//
// FIXTURE (fileFixture = unsupported_exe): a Windows executable
// "heritage_tour_setup.exe" (starts with the "MZ" executable header, 2 KB)
// is handed to HeritageBot as the file the user picked.
//
// WHAT IS OBSERVED: whether HeritageBot itself refuses the file (at selection
// or before upload) and tells the user which formats are supported.
// FakeCloudinary deliberately does NOT reject the file: whether Cloudinary's
// servers would reject it is outside HeritageBot and is not credited to the
// app. (On a real phone the OS gallery picker usually lists only images;
// that platform behaviour is likewise not part of HeritageBot's code.)
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

import '../support/contributor_flow.dart';
import '../support/fake_media_platforms.dart';
import '../support/heritagebot_fixtures.dart';
import '../support/story_submission_flow.dart';

const FakeAuthAccount kContributor = FakeAuthAccount(
  uid: 'case054-contributor-uid',
  email: 'case054.contributor@heritagebot.test',
  password: 'Case054Pass!',
  displayName: 'James Contributor',
);

const String kFileName = 'heritage_tour_setup.exe';
const String kTitle = 'Walking Tour Notes for Colon Street';
const String kStory =
    'These are my notes from the walking tour our barangay organised along '
    'Colon Street, the oldest street in the country, including the stories '
    'the elders shared about the old cinemas and the Parian district.';

/// A message that tells the user the file type/format is not accepted.
final RegExp kFormatMessage = RegExp(
  r'format|file type|unsupported|not supported|jpe?g|png|heic|only images|image files',
  caseSensitive: false,
);

late HeritageBotTestBackend backend;
late FakeImagePickerPlatform gallery;
late FakeGalleryFolder phoneStorage;
final FakeCloudinary cloudinary = FakeCloudinary();

void main() {
  setUpAll(() async {
    backend = await HeritageBotTestBackend.install(accounts: [kContributor]);
    gallery = FakeImagePickerPlatform();
    ImagePickerPlatform.instance = gallery;
    phoneStorage = FakeGalleryFolder.create('case054');
  });

  tearDownAll(() => phoneStorage.delete());

  setUp(() async {
    await backend.reset();
    gallery.clear();
    cloudinary.clear();
    seedContributor(backend, kContributor);
  });

  group('', () {
    testWidgets('CASE-054 - Upload unsupported file type', (
      WidgetTester tester,
    ) async {
      await http.runWithClient(() async {
        usePhoneSurface(tester);
        final exe = phoneStorage.write(kFileName, exeBytes());
        gallery.photosToPick = [XFile(exe.path, name: kFileName)];

        await signInBeforeLaunch(kContributor);
        await openSubmitStoryScreen(tester);

        // STEP: tap "Photos (0/5)" and pick the .exe file.
        await tapVisible(tester, find.text('Photos (0/5)'));
        await pumpFor(tester, const Duration(milliseconds: 300));
        final messagesAfterPick = shownSnackBarTexts(tester);
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
        final messagesAfterSubmit = shownSnackBarTexts(tester);
        // The screen tries to draw a thumbnail of the picked "photo"; with
        // executable bytes Flutter's image decoder reports an error.
        final previewError = tester.takeException();

        // ---- Observations -----------------------------------------------
        final stored = storedSubmissions(backend);
        final uploadedExe = cloudinary.uploads
            .where((u) => u.fileName == kFileName)
            .toList();
        final storedWithExe = stored.values.where(
          (doc) => ((doc['imageUrls'] as List?) ?? const []).any(
            (url) => url.toString().endsWith(kFileName),
          ),
        );
        final allMessages = [...messagesAfterPick, ...messagesAfterSubmit];

        final observed = <String, Object?>{
          // Accepted = HeritageBot sent the file to the media upload or
          // attached it to a saved submission.
          'fileAccepted': uploadedExe.isNotEmpty || storedWithExe.isNotEmpty,
          'formatErrorVisible': allMessages.any(kFormatMessage.hasMatch),
        };
        printOnFailure(
          'CASE-054 observed: $observed\n'
          'addedToSelection("Photos (1/5)")=$addedToSelection '
          'finished=$finished\nmessagesAfterPick=$messagesAfterPick\n'
          'messagesAfterSubmit=$messagesAfterSubmit\n'
          'previewError=$previewError\nuploads=${cloudinary.uploads}\n'
          'storedSubmissions=$stored',
        );

        // ---- Expected result (unchanged from the original CASE-054) -----
        expect(
          observed['fileAccepted'],
          equals(false),
          reason:
              'CASE-054: fileAccepted does not match the real system result',
        );
        expect(
          observed['formatErrorVisible'],
          equals(true),
          reason:
              'CASE-054: formatErrorVisible does not match the real system result',
        );

        await unmountApp(tester);
      }, cloudinary.client);
    });
  }, skip: mediaTestSkip);
}
