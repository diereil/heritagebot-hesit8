import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:path_provider/path_provider.dart';

import 'language_service.dart';

class HeritageBotSystemSettings {
  final Set<String> enabledLanguageCodes;
  final bool notificationsEnabled;
  final int? updatedAtMillis;
  final String updatedByEmail;
  final int? lastBackupAtMillis;
  final String lastBackupFileName;
  final int lastBackupRecordCount;
  final String lastBackupByEmail;

  const HeritageBotSystemSettings({
    required this.enabledLanguageCodes,
    required this.notificationsEnabled,
    this.updatedAtMillis,
    this.updatedByEmail = '',
    this.lastBackupAtMillis,
    this.lastBackupFileName = '',
    this.lastBackupRecordCount = 0,
    this.lastBackupByEmail = '',
  });

  factory HeritageBotSystemSettings.defaults() {
    return HeritageBotSystemSettings(
      enabledLanguageCodes: supportedLanguages.map((e) => e.code).toSet(),
      notificationsEnabled: true,
    );
  }

  factory HeritageBotSystemSettings.fromMap(Map<String, dynamic>? data) {
    if (data == null) return HeritageBotSystemSettings.defaults();

    final rawLanguages = data['enabledLanguageCodes'];
    final knownCodes = supportedLanguages.map((e) => e.code).toSet();
    final enabled = <String>{};

    if (rawLanguages is Iterable) {
      for (final item in rawLanguages) {
        final code = item.toString().trim();
        if (knownCodes.contains(code)) enabled.add(code);
      }
    }

    // English is the permanent fallback language of HeritageBot.
    enabled.add('en');

    return HeritageBotSystemSettings(
      enabledLanguageCodes: enabled.isEmpty
          ? supportedLanguages.map((e) => e.code).toSet()
          : enabled,
      notificationsEnabled: data['notificationsEnabled'] is bool
          ? data['notificationsEnabled'] as bool
          : true,
      updatedAtMillis: _asInt(data['updatedAtMillis']),
      updatedByEmail: data['updatedByEmail']?.toString() ?? '',
      lastBackupAtMillis: _asInt(data['lastBackupAtMillis']),
      lastBackupFileName: data['lastBackupFileName']?.toString() ?? '',
      lastBackupRecordCount: _asInt(data['lastBackupRecordCount']) ?? 0,
      lastBackupByEmail: data['lastBackupByEmail']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    final ordered = enabledLanguageCodes.toList()..sort();
    return {
      'enabledLanguageCodes': ordered,
      'notificationsEnabled': notificationsEnabled,
      'updatedAtMillis': updatedAtMillis,
      'updatedByEmail': updatedByEmail,
      'lastBackupAtMillis': lastBackupAtMillis,
      'lastBackupFileName': lastBackupFileName,
      'lastBackupRecordCount': lastBackupRecordCount,
      'lastBackupByEmail': lastBackupByEmail,
    };
  }

  static int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }
}

class DatabaseBackupResult {
  final String fileName;
  final String filePath;
  final DateTime createdAt;
  final int recordCount;

  const DatabaseBackupResult({
    required this.fileName,
    required this.filePath,
    required this.createdAt,
    required this.recordCount,
  });
}

class SystemSettingsService {
  SystemSettingsService({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  static HeritageBotSystemSettings runtimeSettings =
      HeritageBotSystemSettings.defaults();

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  DocumentReference<Map<String, dynamic>> get _settingsDocument =>
      _firestore.collection('system_settings').doc('general');

  static List<AppLanguage> enabledLanguagesForUi({String? includeCode}) {
    final enabled = runtimeSettings.enabledLanguageCodes;
    final result = supportedLanguages
        .where((language) => enabled.contains(language.code))
        .toList();

    if (includeCode != null &&
        includeCode.trim().isNotEmpty &&
        !result.any((language) => language.code == includeCode)) {
      final existing = supportedLanguages.where(
        (language) => language.code == includeCode,
      );
      if (existing.isNotEmpty) result.add(existing.first);
    }

    if (result.isEmpty) return [languageByCode('en')];
    return result;
  }

  static bool get notificationsEnabled => runtimeSettings.notificationsEnabled;

  Future<HeritageBotSystemSettings> loadRuntimeSettings() async {
    try {
      final snapshot = await _settingsDocument.get().timeout(
        const Duration(seconds: 6),
      );

      runtimeSettings = HeritageBotSystemSettings.fromMap(snapshot.data());
      return runtimeSettings;
    } catch (_) {
      runtimeSettings = HeritageBotSystemSettings.defaults();
      return runtimeSettings;
    }
  }

  Future<HeritageBotSystemSettings> getSettings() async {
    final snapshot = await _settingsDocument.get();
    final settings = HeritageBotSystemSettings.fromMap(snapshot.data());
    runtimeSettings = settings;
    return settings;
  }

  Future<HeritageBotSystemSettings> saveSettings({
    required Set<String> enabledLanguageCodes,
    required bool notificationsEnabled,
  }) async {
    final knownCodes = supportedLanguages.map((e) => e.code).toSet();
    final safeCodes =
        enabledLanguageCodes.where((code) => knownCodes.contains(code)).toSet()
          ..add('en');

    final now = DateTime.now().millisecondsSinceEpoch;
    final email = _auth.currentUser?.email?.trim() ?? '';

    await _settingsDocument.set({
      'enabledLanguageCodes': safeCodes.toList()..sort(),
      'notificationsEnabled': notificationsEnabled,
      'updatedAtMillis': now,
      'updatedByEmail': email,
    }, SetOptions(merge: true));

    return getSettings();
  }

  Future<DatabaseBackupResult> createDatabaseBackup() async {
    final now = DateTime.now();
    final root = <String, dynamic>{
      'backupMetadata': {
        'application': 'HeritageBot',
        'createdAtIso': now.toIso8601String(),
        'createdAtMillis': now.millisecondsSinceEpoch,
        'createdByEmail': _auth.currentUser?.email?.trim() ?? '',
        'formatVersion': 1,
      },
    };

    var recordCount = 0;

    final users = await _readCollection('users');
    final enrichedUsers = <Map<String, dynamic>>[];

    for (final user in users) {
      final userId = user['_documentId']?.toString() ?? '';
      final copy = Map<String, dynamic>.from(user);

      if (userId.isNotEmpty) {
        final bookmarks = await _readSubcollection(
          parentCollection: 'users',
          parentId: userId,
          subcollection: 'bookmarks',
        );
        final journalEntries = await _readSubcollection(
          parentCollection: 'users',
          parentId: userId,
          subcollection: 'journal_entries',
        );

        copy['_subcollections'] = {
          'bookmarks': bookmarks,
          'journal_entries': journalEntries,
        };
        recordCount += bookmarks.length + journalEntries.length;
      }

      enrichedUsers.add(copy);
    }

    root['users'] = enrichedUsers;
    recordCount += enrichedUsers.length;

    const topLevelCollections = <String>[
      'heritage_sites',
      'community_submissions',
      'historical_contents',
      'ai_narratives',
      'usage_events',
      'system_settings',
    ];

    for (final collection in topLevelCollections) {
      final records = await _readCollection(collection);
      root[collection] = records;
      recordCount += records.length;
    }

    final directory = await _backupDirectory();
    final fileName = 'heritagebot_backup_${_timestampForFile(now)}.json';
    final file = File('${directory.path}${Platform.pathSeparator}$fileName');

    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString(encoder.convert(_jsonSafe(root)), flush: true);

    await _settingsDocument.set({
      'lastBackupAtMillis': now.millisecondsSinceEpoch,
      'lastBackupFileName': fileName,
      'lastBackupRecordCount': recordCount,
      'lastBackupByEmail': _auth.currentUser?.email?.trim() ?? '',
    }, SetOptions(merge: true));

    await getSettings();

    return DatabaseBackupResult(
      fileName: fileName,
      filePath: file.path,
      createdAt: now,
      recordCount: recordCount,
    );
  }

  Future<List<Map<String, dynamic>>> _readCollection(String name) async {
    final snapshot = await _firestore.collection(name).get();
    return snapshot.docs
        .map((doc) => <String, dynamic>{'_documentId': doc.id, ...doc.data()})
        .toList();
  }

  Future<List<Map<String, dynamic>>> _readSubcollection({
    required String parentCollection,
    required String parentId,
    required String subcollection,
  }) async {
    final snapshot = await _firestore
        .collection(parentCollection)
        .doc(parentId)
        .collection(subcollection)
        .get();

    return snapshot.docs
        .map((doc) => <String, dynamic>{'_documentId': doc.id, ...doc.data()})
        .toList();
  }

  Future<Directory> _backupDirectory() async {
    if (Platform.isAndroid) {
      final external = await getExternalStorageDirectory();
      if (external != null) {
        final dir = Directory(
          '${external.path}${Platform.pathSeparator}HeritageBotBackups',
        );
        if (!await dir.exists()) await dir.create(recursive: true);
        return dir;
      }
    }

    final documents = await getApplicationDocumentsDirectory();
    final dir = Directory(
      '${documents.path}${Platform.pathSeparator}HeritageBotBackups',
    );
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  String _timestampForFile(DateTime value) {
    String two(int number) => number.toString().padLeft(2, '0');
    return '${value.year}${two(value.month)}${two(value.day)}_'
        '${two(value.hour)}${two(value.minute)}${two(value.second)}';
  }

  dynamic _jsonSafe(dynamic value) {
    if (value == null || value is String || value is num || value is bool) {
      return value;
    }
    if (value is Timestamp) return value.toDate().toIso8601String();
    if (value is DateTime) return value.toIso8601String();
    if (value is GeoPoint) {
      return {'latitude': value.latitude, 'longitude': value.longitude};
    }
    if (value is DocumentReference) return value.path;
    if (value is Iterable) return value.map(_jsonSafe).toList();
    if (value is Map) {
      return value.map(
        (key, item) => MapEntry(key.toString(), _jsonSafe(item)),
      );
    }
    return value.toString();
  }
}
