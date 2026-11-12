// HERITAGEBOT - TEST CASE 091
// Proponent: Shawn Guillmar C. Morales
// Module: Heritage Site Management
// Unit: Upload Heritage Media
// Description: Upload invalid media type
// Expected: Reject unsupported media
//
// TEST TYPE: Flutter widget test (host VM, no device / live Firebase /
// live Cloudinary).
//
// REAL CODE UNDER TEST (lib/, unmodified)
//   AuthGate -> AdminShell -> "Sites" -> "Edit" on Casa Gorordo Museum ->
//   HeritageSiteEditorScreen: "Add Heritage Photos" (_pickSitePhotos,
//   ImagePicker.pickMultiImage) -> "Save Heritage Site" -> _save ->
//   HeritageMediaService.uploadImages (exists / size check / multipart POST)
//   -> HeritageSiteService.updateSite.
//
// FIXTURE (mediaFixture = unsupported_exe): a Windows executable
// "fort_tour_installer.exe" (starts with the "MZ" executable header, 2 KB)
// is handed to HeritageBot as the file the administrator picked.
//
// WHAT IS OBSERVED: whether HeritageBot itself refuses the file (at
// selection or before upload) and tells the administrator which formats are
// supported. FakeCloudinary deliberately does NOT reject the file: whether
// Cloudinary's servers would reject it is outside HeritageBot and is not
// credited to the app (same rule as CASE-054).
//
// MOCKED: Firebase platform layer, the gallery picker
// (FakeImagePickerPlatform) and Cloudinary's upload endpoint
// (FakeCloudinary, via package:http runWithClient). Needs the dummy
// Cloudinary --dart-define values (support/unit_091_120_defines.json);
// without them it is SKIPPED.

// ignore_for_file: depend_on_referenced_packages

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';

import 'package:heritagebot/main.dart' as app;

import '../support/admin_flow.dart';
import '../support/fake_media_platforms.dart';

const String kFileName = 'fort_tour_installer.exe';

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
    backend = await HeritageBotTestBackend.install(accounts: [kAdminAccount]);
    gallery = FakeImagePickerPlatform();
    ImagePickerPlatform.instance = gallery;
    phoneStorage = FakeGalleryFolder.create('case091');
  });

  tearDownAll(() => phoneStorage.delete());

  setUp(() async {
    await backend.reset();
    gallery.clear();
    cloudinary.clear();
    seedRegisteredSites(backend, [bundledSite('casa_gorordo'), kMagellansCross]);
  });

  group('', () {
    testWidgets('CASE-091 - Upload invalid media type', (
      WidgetTester tester,
    ) async {
      await http.runWithClient(() async {
        usePhoneSurface(tester);
        final site = bundledSite('casa_gorordo');
        final path = 'heritage_sites/${site.id}';
        final before = '${storedSites(backend)[path]}';
        final exe = phoneStorage.write(kFileName, exeBytes());
        gallery.photosToPick = [XFile(exe.path, name: kFileName)];

        await openAdminShell(tester);
        await openAdminSites(tester);
        await openSiteEditor(tester, siteName: site.name);

        // STEP: "Add Heritage Photos" -> the .exe is picked.
        final addPhotos = find.descendant(
          of: siteEditorScreen,
          matching: find.text('Add Heritage Photos'),
        );
        await scrollUntilBuilt(tester, addPhotos, screen: app.HeritageSiteEditorScreen);
        await tapVisible(tester, addPhotos);
        await pumpFor(tester, const Duration(milliseconds: 300));
        final messagesAfterPick = shownSnackBarTexts(tester);
        final addedToSelection = infoCardsTitled(tester, 'New Photos Selected').isNotEmpty;

        // STEP: "Save Heritage Site" (real file I/O + multipart upload).
        await tapSaveSite(tester);
        final finished = await pumpWithRealIoUntil(
          tester,
          () =>
              siteEditorScreen.evaluate().isEmpty ||
              shownSnackBarTexts(tester).isNotEmpty,
        );
        await pumpFor(tester, const Duration(milliseconds: 600));
        final messagesAfterSave = shownSnackBarTexts(tester);
        final closed = siteEditorScreen.evaluate().isEmpty;
        if (closed) {
          await waitForSiteList(tester);
          noteAdminShellHeroDefect(tester);
        }

        // ---- Observations -------------------------------------------------
        final doc = storedSites(backend)[path];
        final uploadedExe =
            cloudinary.uploads.where((u) => u.fileName == kFileName).toList();
        final imageUrls = (doc?['imageUrls'] as List?)?.cast<String>() ?? const [];
        final storedExe = imageUrls.where((u) => u.endsWith(kFileName)).toList();
        final allMessages = [...messagesAfterPick, ...messagesAfterSave];

        final observed = <String, Object?>{
          // Accepted = HeritageBot sent the file to the media upload or
          // attached it to the saved heritage-site record.
          'mediaAccepted': uploadedExe.isNotEmpty || storedExe.isNotEmpty,
          'formatErrorVisible': allMessages.any(kFormatMessage.hasMatch),
        };
        printOnFailure(
          'CASE-091 observed: $observed\naddedToSelection=$addedToSelection '
          'finished=$finished closed=$closed\nmessagesAfterPick=$messagesAfterPick\n'
          'messagesAfterSave=$messagesAfterSave\nuploads=${cloudinary.uploads}\n'
          'siteBefore=$before\nsiteAfter=$doc',
        );

        // ignore: avoid_print
        print('CASE-091 evidence: observed=$observed');
        // ---- Expected result (unchanged from the original CASE-091) -------
        expect(
          observed['mediaAccepted'],
          equals(false),
          reason: 'CASE-091: mediaAccepted does not match the real system result',
        );
        expect(
          observed['formatErrorVisible'],
          equals(true),
          reason: 'CASE-091: formatErrorVisible does not match the real system result',
        );

        await unmountApp(tester);
      }, cloudinary.client);
    });
  }, skip: mediaTestSkip);
}
