// HERITAGEBOT - TEST SUPPORT: device storage for the database backup
// (CASE-118 / CASE-119, System Settings / Backup Database).
//
// SystemSettingsService.createDatabaseBackup (lib/, unmodified) writes its
// JSON file into getApplicationDocumentsDirectory()/HeritageBotBackups
// (path_provider). This fake replaces ONLY the plugin's native platform
// layer (PathProviderPlatform.instance):
//
//   * available   -> the "documents directory" is a fresh temporary folder,
//                    so nothing is written into the real user profile;
//   * unavailable -> the platform reports that storage cannot be reached
//                    (PlatformException), as a phone with unavailable
//                    storage / a failing storage service would.
//
// It never writes or checks a backup itself.
//
// path_provider_platform_interface is a transitive dependency of
// path_provider (already in pubspec.lock); pubspec.yaml is not modified.
// ignore_for_file: depend_on_referenced_packages

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class FakePathProviderPlatform extends PathProviderPlatform {
  FakePathProviderPlatform._(this.documentsDirectory);

  /// Installs the fake with a new temporary documents directory.
  static FakePathProviderPlatform install(String caseId) {
    final fake = FakePathProviderPlatform._(
      Directory.systemTemp.createTempSync('heritagebot_${caseId}_docs_'),
    );
    PathProviderPlatform.instance = fake;
    return fake;
  }

  final Directory documentsDirectory;

  /// false = the storage service is unavailable.
  bool storageAvailable = true;

  int documentsPathRequests = 0;

  void _ensureAvailable() {
    if (!storageAvailable) {
      throw PlatformException(
        code: 'unavailable',
        message: 'Device storage service is unavailable.',
      );
    }
  }

  @override
  Future<String?> getApplicationDocumentsPath() async {
    documentsPathRequests++;
    _ensureAvailable();
    return documentsDirectory.path;
  }

  @override
  Future<String?> getExternalStoragePath() async {
    _ensureAvailable();
    return null;
  }

  @override
  Future<String?> getTemporaryPath() async {
    _ensureAvailable();
    return Directory.systemTemp.path;
  }

  /// Backup files currently in `documents/HeritageBotBackups`.
  List<File> backupFiles() {
    final dir = Directory(
      '${documentsDirectory.path}${Platform.pathSeparator}HeritageBotBackups',
    );
    if (!dir.existsSync()) return const [];
    return dir.listSync().whereType<File>().toList();
  }

  void delete() {
    try {
      if (documentsDirectory.existsSync()) {
        documentsDirectory.deleteSync(recursive: true);
      }
    } on FileSystemException catch (e) {
      // ignore: avoid_print
      print('Note: temporary folder not removed (${e.osError?.message}): '
          '${documentsDirectory.path}');
    }
  }
}
