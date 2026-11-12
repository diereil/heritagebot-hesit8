// HERITAGEBOT - TEST CASE 090
// Proponent: James Stephen O. Ramos
// Module: Heritage Site Management
// Unit: Upload Heritage Media
// Description: Upload valid site photo or video
// Expected: Associate media with correct site
//
// TEST TYPE: Flutter widget test (host VM, no device / live Firebase /
// live Cloudinary).
//
// REAL CODE UNDER TEST (lib/, unmodified)
//   AuthGate -> AdminShell -> "Sites" -> "Edit" on Casa Gorordo Museum ->
//   HeritageSiteEditorScreen: "Add Heritage Photos" (ImagePicker
//   .pickMultiImage) and "Select / Replace Heritage Video"
//   (ImagePicker.pickVideo) -> "Save Heritage Site" ->
//   HeritageMediaService.uploadImages / uploadVideo (exists / size check /
//   multipart POST to Cloudinary, folder heritagebot/heritage_sites/{id}/..)
//   -> HeritageSiteService.updateSite (imageUrls, videoAsset).
//
// FIXTURES: a real PNG photo "casa_gorordo_courtyard.png" and a real MP4
// "casa_gorordo_tour.mp4" in the phone gallery; a second site (Magellan's
// Cross) whose record must stay unchanged.
//
// MOCKED: Firebase platform layer, the gallery picker
// (FakeImagePickerPlatform) and Cloudinary's upload endpoint
// (FakeCloudinary, via package:http runWithClient - nothing leaves the
// machine). HeritageMediaService reads its Cloudinary settings at compile
// time, so this test needs the dummy --dart-define values described in
// support/fake_media_platforms.dart; without them it is SKIPPED.

// ignore_for_file: depend_on_referenced_packages

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';

import 'package:heritagebot/main.dart' as app;
import 'package:heritagebot/models/heritage_place.dart';

import '../support/admin_flow.dart';
import '../support/fake_media_platforms.dart';

const String kPhotoName = 'casa_gorordo_courtyard.png';
const String kVideoName = 'casa_gorordo_tour.mp4';

late HeritageBotTestBackend backend;
late FakeImagePickerPlatform gallery;
late FakeGalleryFolder phoneStorage;
final FakeCloudinary cloudinary = FakeCloudinary();

void main() {
  setUpAll(() async {
    backend = await HeritageBotTestBackend.install(accounts: [kAdminAccount]);
    gallery = FakeImagePickerPlatform();
    ImagePickerPlatform.instance = gallery;
    phoneStorage = FakeGalleryFolder.create('case090');
  });

  tearDownAll(() => phoneStorage.delete());

  setUp(() async {
    await backend.reset();
    gallery.clear();
    cloudinary.clear();
    seedRegisteredSites(backend, [bundledSite('casa_gorordo'), kMagellansCross]);
  });

  group('', () {
  testWidgets('CASE-090 - Upload valid site photo or video', (
    WidgetTester tester,
  ) async {
    await http.runWithClient(() async {
      usePhoneSurface(tester);
      final site = bundledSite('casa_gorordo');
      final path = 'heritage_sites/${site.id}';
      final otherPath = 'heritage_sites/${kMagellansCross.id}';
      final otherBefore = '${storedSites(backend)[otherPath]}';
      final photo = phoneStorage.write(kPhotoName, kTinyPngBytes);
      final video = phoneStorage.write(kVideoName, mp4Bytes());
      gallery.photosToPick = [XFile(photo.path, name: kPhotoName)];
      gallery.videoToPick = XFile(video.path, name: kVideoName);

      await openAdminShell(tester);
      await openAdminSites(tester);

      // STEP: Edit Casa Gorordo Museum, pick a photo and a video.
      await openSiteEditor(tester, siteName: site.name);
      final addPhotos = find.descendant(
        of: siteEditorScreen,
        matching: find.text('Add Heritage Photos'),
      );
      await scrollUntilBuilt(tester, addPhotos, screen: app.HeritageSiteEditorScreen);
      await tapVisible(tester, addPhotos);
      await pumpFor(tester, const Duration(milliseconds: 300));
      final pickVideo = find.descendant(
        of: siteEditorScreen,
        matching: find.text('Select / Replace Heritage Video'),
      );
      await scrollUntilBuilt(tester, pickVideo, screen: app.HeritageSiteEditorScreen);
      await tapVisible(tester, pickVideo);
      await pumpFor(tester, const Duration(milliseconds: 300));
      final photoSelected = infoCardsTitled(tester, 'New Photos Selected').isNotEmpty;
      final videoSelected = infoCardsTitled(tester, 'New Video Selected').isNotEmpty;

      // STEP: Save (real file I/O + multipart upload).
      await tapSaveSite(tester);
      final finished = await pumpWithRealIoUntil(
        tester,
        () =>
            siteEditorScreen.evaluate().isEmpty ||
            shownSnackBarTexts(tester).isNotEmpty,
      );
      await pumpFor(tester, const Duration(milliseconds: 600));
      final messages = shownSnackBarTexts(tester);
      final closed = siteEditorScreen.evaluate().isEmpty;
      if (closed) {
        await waitForSiteList(tester);
        noteAdminShellHeroDefect(tester);
      }

      // ---- Observations ---------------------------------------------------
      final doc = storedSites(backend)[path];
      final imageUpload = cloudinary.uploads
          .where((u) => u.resourceType == 'image')
          .toList();
      final videoUpload = cloudinary.uploads
          .where((u) => u.resourceType == 'video')
          .toList();
      final imageUrls = (doc?['imageUrls'] as List?)?.cast<String>() ?? const [];

      final observed = <String, Object?>{
        // The picked photo and video were uploaded and stored on the record.
        'heritageMediaSaved':
            photoSelected &&
            videoSelected &&
            closed &&
            messages.contains('Heritage site updated.') &&
            imageUpload.length == 1 &&
            imageUpload.single.fileName == kPhotoName &&
            videoUpload.length == 1 &&
            videoUpload.single.fileName == kVideoName &&
            imageUrls.length == 1 &&
            imageUrls.single == imageUpload.single.secureUrl &&
            doc?['videoAsset'] == videoUpload.single.secureUrl,
        // ...under THIS site's id only; the other site is untouched.
        'correctSiteLinked':
            imageUpload.length == 1 &&
            videoUpload.length == 1 &&
            imageUpload.single.folder ==
                'heritagebot/heritage_sites/${site.id}/images' &&
            videoUpload.single.folder ==
                'heritagebot/heritage_sites/${site.id}/videos' &&
            doc?['id'] == site.id &&
            '${storedSites(backend)[otherPath]}' == otherBefore &&
            heritagePlaces
                .where((p) => p.id == site.id)
                .any((p) => p.imageUrls.contains(imageUpload.single.secureUrl)),
      };
      printOnFailure(
        'CASE-090 observed: $observed\nphotoSelected=$photoSelected '
        'videoSelected=$videoSelected finished=$finished closed=$closed '
        'messages=$messages\nuploads=${cloudinary.uploads}\nsiteDoc=$doc\n'
        'otherBefore=$otherBefore\notherAfter=${storedSites(backend)[otherPath]}',
      );

      // ---- Expected result (unchanged from the original CASE-090) --------
      expect(
        observed['heritageMediaSaved'],
        equals(true),
        reason: 'CASE-090: heritageMediaSaved does not match the real system result',
      );
      expect(
        observed['correctSiteLinked'],
        equals(true),
        reason: 'CASE-090: correctSiteLinked does not match the real system result',
      );

      await unmountApp(tester);
    }, cloudinary.client);
  });
  }, skip: mediaTestSkip);
}
