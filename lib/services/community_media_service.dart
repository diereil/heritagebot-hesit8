import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

class CommunityMediaService {
  static const int maxImages = 5;
  static const int maxVideos = 2;
  static const int maxImageBytes = 10 * 1024 * 1024;
  static const int maxVideoBytes = 60 * 1024 * 1024;

  static const String _cloudName = String.fromEnvironment(
    'CLOUDINARY_CLOUD_NAME',
  );

  static const String _uploadPreset = String.fromEnvironment(
    'CLOUDINARY_UPLOAD_PRESET',
  );

  User get _currentUser {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      throw FirebaseAuthException(
        code: 'not-logged-in',
        message: 'Please log in before uploading media.',
      );
    }

    return user;
  }

  void _ensureConfigured() {
    if (_cloudName.trim().isEmpty || _uploadPreset.trim().isEmpty) {
      throw Exception(
        'Cloudinary is not configured. Run HeritageBot with '
        '--dart-define=CLOUDINARY_CLOUD_NAME=YOUR_CLOUD_NAME and '
        '--dart-define=CLOUDINARY_UPLOAD_PRESET=YOUR_UNSIGNED_PRESET.',
      );
    }
  }

  Future<List<String>> uploadImages({
    required String submissionId,
    required List<XFile> images,
    void Function(int uploaded, int total)? onProgress,
  }) async {
    _ensureConfigured();

    if (images.length > maxImages) {
      throw ArgumentError('You can upload up to $maxImages photos.');
    }

    final user = _currentUser;
    final urls = <String>[];

    for (var index = 0; index < images.length; index++) {
      final image = images[index];
      final file = File(image.path);

      if (!await file.exists()) {
        throw Exception('A selected photo could not be found.');
      }

      final size = await file.length();

      if (size > maxImageBytes) {
        throw Exception('Each photo must be 10 MB or smaller.');
      }

      final url = await _uploadFile(
        file: file,
        resourceType: 'image',
        folder:
            'heritagebot/community_submissions/${user.uid}/$submissionId/images',
      );

      urls.add(url);
      onProgress?.call(index + 1, images.length);
    }

    return urls;
  }

  Future<List<String>> uploadVideos({
    required String submissionId,
    required List<XFile> videos,
    void Function(int uploaded, int total)? onProgress,
  }) async {
    _ensureConfigured();

    if (videos.length > maxVideos) {
      throw ArgumentError('You can upload up to $maxVideos videos.');
    }

    final user = _currentUser;
    final urls = <String>[];

    for (var index = 0; index < videos.length; index++) {
      final video = videos[index];
      final file = File(video.path);

      if (!await file.exists()) {
        throw Exception('A selected video could not be found.');
      }

      final size = await file.length();

      if (size > maxVideoBytes) {
        throw Exception('Each video must be 60 MB or smaller.');
      }

      final url = await _uploadFile(
        file: file,
        resourceType: 'video',
        folder:
            'heritagebot/community_submissions/${user.uid}/$submissionId/videos',
      );

      urls.add(url);
      onProgress?.call(index + 1, videos.length);
    }

    return urls;
  }

  Future<String> _uploadFile({
    required File file,
    required String resourceType,
    required String folder,
  }) async {
    final endpoint = Uri.parse(
      'https://api.cloudinary.com/v1_1/$_cloudName/$resourceType/upload',
    );

    final request = http.MultipartRequest('POST', endpoint)
      ..fields['upload_preset'] = _uploadPreset
      ..fields['folder'] = folder
      ..files.add(
        await http.MultipartFile.fromPath(
          'file',
          file.path,
        ),
      );

    final streamedResponse = await request.send();
    final responseBody = await streamedResponse.stream.bytesToString();

    Map<String, dynamic> decoded = {};

    try {
      decoded = jsonDecode(responseBody) as Map<String, dynamic>;
    } catch (_) {
      // Keep decoded empty and report the raw HTTP failure below.
    }

    if (streamedResponse.statusCode < 200 ||
        streamedResponse.statusCode >= 300) {
      final cloudinaryMessage =
          (decoded['error'] is Map<String, dynamic>)
              ? (decoded['error'] as Map<String, dynamic>)['message']
                    ?.toString()
              : null;

      throw Exception(
        cloudinaryMessage?.trim().isNotEmpty == true
            ? cloudinaryMessage!
            : 'Cloudinary upload failed with HTTP '
                  '${streamedResponse.statusCode}.',
      );
    }

    final secureUrl = decoded['secure_url']?.toString().trim() ?? '';

    if (secureUrl.isEmpty) {
      throw Exception(
        'Cloudinary uploaded the file but did not return a secure URL.',
      );
    }

    return secureUrl;
  }

  Future<void> deleteMediaUrls(Iterable<String> urls) async {
    // Cloudinary unsigned client uploads do not safely expose destructive
    // account credentials in the Flutter app. The Firestore submission can
    // still be deleted normally. Media cleanup can be performed from the
    // Cloudinary Media Library or moved to a secure backend later.
  }
}
