// HERITAGEBOT - TEST SUPPORT: device gallery + Cloudinary fakes for
// CASE-052..CASE-055 (Community Contributor Management / Upload Photos and
// Videos).
//
// Like the other fakes in this folder, these replace ONLY what sits outside
// HeritageBot:
//
//   * FakeImagePickerPlatform -> ImagePickerPlatform.instance
//       The phone's gallery picker. It returns the file the "user" chooses.
//       It never filters, resizes, or validates anything; that is up to
//       HeritageBot.
//   * FakeCloudinary          -> the HTTP client used by package:http
//       (installed with http's own runWithClient). It stands in for
//       https://api.cloudinary.com: it records every upload request
//       HeritageBot sends and answers like Cloudinary's upload API
//       (HTTP 200 + secure_url). It does not accept or reject files on the
//       app's behalf.
//
// The real SubmitCommunityStoryScreen and CommunityMediaService (lib/,
// unmodified) run on top of these fakes.
//
// CommunityMediaService reads its Cloudinary settings at compile time
// (String.fromEnvironment), so these tests must be started with
//   --dart-define=CLOUDINARY_CLOUD_NAME=heritagebot-test
//   --dart-define=CLOUDINARY_UPLOAD_PRESET=heritagebot-test-preset
// (dummy values; no request leaves the machine). Without them the tests are
// SKIPPED, and the skip reason says why.

// Transitive dependencies of image_picker (already in pubspec.lock);
// pubspec.yaml is not modified.
// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';

// ---------------------------------------------------------------------------
// BUILD CONFIGURATION (same compile-time keys CommunityMediaService reads)
// ---------------------------------------------------------------------------

const String kTestCloudName = String.fromEnvironment('CLOUDINARY_CLOUD_NAME');
const String kTestUploadPreset = String.fromEnvironment(
  'CLOUDINARY_UPLOAD_PRESET',
);

bool get cloudinaryConfiguredForTest =>
    kTestCloudName.trim().isNotEmpty && kTestUploadPreset.trim().isNotEmpty;

/// Skip reason for media tests when the build has no Cloudinary settings.
Object get mediaTestSkip => cloudinaryConfiguredForTest
    ? false
    : 'CommunityMediaService needs its compile-time Cloudinary settings. Run '
          'with --dart-define=CLOUDINARY_CLOUD_NAME=heritagebot-test '
          '--dart-define=CLOUDINARY_UPLOAD_PRESET=heritagebot-test-preset '
          '(dummy values; uploads go to FakeCloudinary, not the internet).';

// ---------------------------------------------------------------------------
// DEVICE GALLERY
// ---------------------------------------------------------------------------

class FakeImagePickerPlatform extends ImagePickerPlatform {
  /// Files the user selects the next time HeritageBot opens the photo picker.
  List<XFile> photosToPick = <XFile>[];

  /// File the user selects the next time HeritageBot opens the video picker.
  XFile? videoToPick;

  int multiImagePickerOpened = 0;
  int videoPickerOpened = 0;

  void clear() {
    photosToPick = <XFile>[];
    videoToPick = null;
    multiImagePickerOpened = 0;
    videoPickerOpened = 0;
  }

  @override
  Future<List<XFile>> getMultiImageWithOptions({
    MultiImagePickerOptions options = const MultiImagePickerOptions(),
  }) async {
    multiImagePickerOpened++;
    return List<XFile>.of(photosToPick);
  }

  @override
  Future<XFile?> getVideo({
    required ImageSource source,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    Duration? maxDuration,
  }) async {
    videoPickerOpened++;
    return videoToPick;
  }

  @override
  Future<LostDataResponse> getLostData() async => LostDataResponse.empty();
}

// ---------------------------------------------------------------------------
// CLOUDINARY UPLOAD API
// ---------------------------------------------------------------------------

class FakeCloudinaryUpload {
  FakeCloudinaryUpload({
    required this.url,
    required this.resourceType,
    required this.folder,
    required this.uploadPreset,
    required this.fileName,
    required this.bodyBytes,
    required this.secureUrl,
  });

  final Uri url;
  final String resourceType; // "image" or "video" (from the endpoint path)
  final String folder;
  final String uploadPreset;
  final String fileName;
  final int bodyBytes;
  final String secureUrl;

  @override
  String toString() =>
      'FakeCloudinaryUpload($resourceType, folder=$folder, '
      'file=$fileName, bytes=$bodyBytes, secureUrl=$secureUrl)';
}

class FakeCloudinary {
  final List<FakeCloudinaryUpload> uploads = <FakeCloudinaryUpload>[];

  void clear() => uploads.clear();

  /// Client handed to package:http via runWithClient.
  http.Client client() => MockClient((http.Request request) async {
    // Multipart field values are plain ASCII here; latin1 keeps binary
    // file bytes from breaking the decode.
    final body = latin1.decode(request.bodyBytes);
    String field(String name) =>
        RegExp('name="$name"\r\n\r\n([^\r]*)\r\n').firstMatch(body)?.group(1) ??
        '';
    final fileName =
        RegExp('name="file"; filename="([^"]*)"').firstMatch(body)?.group(1) ??
        '';
    final segments = request.url.pathSegments; // v1_1/{cloud}/{type}/upload
    final resourceType = segments.length >= 3 ? segments[2] : '';
    final folder = field('folder');
    final secureUrl =
        'https://res.cloudinary.com/${segments.length > 1 ? segments[1] : ''}'
        '/$resourceType/upload/v1/$folder/${uploads.length}_$fileName';

    uploads.add(
      FakeCloudinaryUpload(
        url: request.url,
        resourceType: resourceType,
        folder: folder,
        uploadPreset: field('upload_preset'),
        fileName: fileName,
        bodyBytes: request.bodyBytes.length,
        secureUrl: secureUrl,
      ),
    );

    return http.Response(
      jsonEncode(<String, Object?>{
        'secure_url': secureUrl,
        'resource_type': resourceType,
      }),
      200,
      headers: const {'content-type': 'application/json'},
    );
  });
}

// ---------------------------------------------------------------------------
// MEDIA FILES ON THE "PHONE"
// ---------------------------------------------------------------------------

/// A valid 1x1 PNG (what a real photo file starts with).
final Uint8List kTinyPngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
);

/// Minimal MP4 header ("ftyp" box) followed by sample data.
Uint8List mp4Bytes() {
  final header = <int>[
    0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70, // size, "ftyp"
    0x6D, 0x70, 0x34, 0x32, 0x00, 0x00, 0x00, 0x00, // "mp42"
    0x6D, 0x70, 0x34, 0x32, 0x69, 0x73, 0x6F, 0x6D, // "mp42isom"
  ];
  return Uint8List.fromList([...header, ...List<int>.filled(4096, 0x11)]);
}

/// Windows executable header ("MZ") followed by sample data.
Uint8List exeBytes() => Uint8List.fromList([
  0x4D,
  0x5A,
  0x90,
  0x00,
  0x03,
  0x00,
  ...List<int>.filled(2048, 0x00),
]);

/// Temporary folder that plays the phone's gallery storage for one file.
class FakeGalleryFolder {
  FakeGalleryFolder._(this.directory);

  final Directory directory;

  static FakeGalleryFolder create(String caseId) => FakeGalleryFolder._(
    Directory.systemTemp.createTempSync('heritagebot_${caseId}_'),
  );

  File write(String name, List<int> bytes) {
    final file = File('${directory.path}${Platform.pathSeparator}$name');
    file.writeAsBytesSync(bytes, flush: true);
    return file;
  }

  /// Best-effort clean-up of the temporary folder. On Windows a file that
  /// the image preview has just read can still be locked by the OS for a
  /// moment; a leftover temp folder must not turn into a test failure.
  void delete() {
    try {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    } on FileSystemException catch (e) {
      // ignore: avoid_print
      print(
        'Note: temporary gallery folder not removed (${e.osError?.message}): '
        '${directory.path}',
      );
    }
  }
}

// ---------------------------------------------------------------------------
// PUMPING WITH REAL FILE I/O
// ---------------------------------------------------------------------------

/// CommunityMediaService does real file I/O (File.exists / length / read).
/// Inside testWidgets that I/O only progresses when real time is allowed
/// to pass, so alternate real-time slices with frame pumps until [done].
Future<bool> pumpWithRealIoUntil(
  WidgetTester tester,
  bool Function() done, {
  int maxRounds = 300,
}) async {
  for (var i = 0; i < maxRounds; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 50));
    if (done()) return true;
  }
  return false;
}
