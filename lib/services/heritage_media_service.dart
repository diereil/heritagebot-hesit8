import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

class HeritageMediaService {
  static const int maxImages = 8;
  static const int maxImageBytes = 10 * 1024 * 1024;
  static const int maxVideoBytes = 80 * 1024 * 1024;

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
        message: 'Please log in before uploading heritage media.',
      );
    }

    return user;
  }

  void _ensureConfigured() {
    if (_cloudName.trim().isEmpty || _uploadPreset.trim().isEmpty) {
      throw Exception('Cloudinary is not configured for HeritageBot.');
    }
  }

  Future<List<String>> uploadImages({
    required String siteId,
    required List<XFile> images,
    void Function(int uploaded, int total)? onProgress,
  }) async {
    _ensureConfigured();
    _currentUser;

    if (images.length > maxImages) {
      throw ArgumentError(
        'You can upload up to $maxImages heritage photos at one time.',
      );
    }

    final urls = <String>[];

    for (var index = 0; index < images.length; index++) {
      final file = File(images[index].path);

      if (!await file.exists()) {
        throw Exception('A selected heritage photo could not be found.');
      }

      if (await file.length() > maxImageBytes) {
        throw Exception('Each heritage photo must be 10 MB or smaller.');
      }

      urls.add(
        await _uploadFile(
          file: file,
          resourceType: 'image',
          folder: 'heritagebot/heritage_sites/$siteId/images',
        ),
      );

      onProgress?.call(index + 1, images.length);
    }

    return urls;
  }

  Future<String> uploadVideo({
    required String siteId,
    required XFile video,
  }) async {
    _ensureConfigured();
    _currentUser;

    final file = File(video.path);

    if (!await file.exists()) {
      throw Exception('The selected heritage video could not be found.');
    }

    if (await file.length() > maxVideoBytes) {
      throw Exception('Heritage video must be 80 MB or smaller.');
    }

    return _uploadFile(
      file: file,
      resourceType: 'video',
      folder: 'heritagebot/heritage_sites/$siteId/videos',
    );
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
      ..files.add(await http.MultipartFile.fromPath('file', file.path));

    final streamed = await request.send();
    final body = await streamed.stream.bytesToString();

    Map<String, dynamic> decoded = {};

    try {
      decoded = jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {}

    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      final message = decoded['error'] is Map<String, dynamic>
          ? (decoded['error'] as Map<String, dynamic>)['message']?.toString()
          : null;

      throw Exception(
        message?.trim().isNotEmpty == true
            ? message!
            : 'Heritage media upload failed with HTTP ${streamed.statusCode}.',
      );
    }

    final secureUrl = decoded['secure_url']?.toString().trim() ?? '';

    if (secureUrl.isEmpty) {
      throw Exception(
        'Cloudinary uploaded the heritage media but did not return a URL.',
      );
    }

    return secureUrl;
  }
}
