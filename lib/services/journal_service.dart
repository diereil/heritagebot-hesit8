import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/journal_entry.dart';

class JournalService {
  static const String _legacyLocalBaseKey = 'heritagebot_journal_entries';
  static const String _migrationFlagBaseKey = 'heritagebot_firestore_migrated';

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String get _uid {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid == null || uid.trim().isEmpty) {
      throw FirebaseAuthException(
        code: 'not-logged-in',
        message: 'Please log in before using the journal.',
      );
    }

    return uid;
  }

  CollectionReference<Map<String, dynamic>> _journalCollection() {
    return _firestore
        .collection('users')
        .doc(_uid)
        .collection('journal_entries');
  }

  Future<List<JournalEntry>> getEntries() async {
    await _migrateLocalEntriesIfNeeded();

    final snapshot = await _journalCollection()
        .orderBy('createdAtMillis', descending: true)
        .get();

    return snapshot.docs.map((doc) {
      final data = doc.data();
      data['id'] ??= doc.id;
      return JournalEntry.fromMap(data);
    }).toList();
  }

  Future<List<JournalEntry>> getEntriesByPlace(String placeId) async {
    await _migrateLocalEntriesIfNeeded();

    final snapshot = await _journalCollection()
        .where('placeId', isEqualTo: placeId)
        .get();

    final entries = snapshot.docs.map((doc) {
      final data = doc.data();
      data['id'] ??= doc.id;
      return JournalEntry.fromMap(data);
    }).toList();

    entries.sort((a, b) => b.createdAtMillis.compareTo(a.createdAtMillis));
    return entries;
  }

  Future<void> _migrateLocalEntriesIfNeeded() async {
    final uid = _uid;
    final prefs = await SharedPreferences.getInstance();
    final migrationFlagKey = '${_migrationFlagBaseKey}_$uid';

    if (prefs.getBool(migrationFlagKey) == true) return;

    final legacyKey = '${_legacyLocalBaseKey}_$uid';
    final rawList = prefs.getStringList(legacyKey) ?? [];

    if (rawList.isEmpty) {
      await prefs.setBool(migrationFlagKey, true);
      return;
    }

    for (final raw in rawList) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is! Map) continue;

        final oldEntry = JournalEntry.fromMap(
          Map<String, dynamic>.from(decoded),
        );

        final savedImagePaths = <String>[
          ...oldEntry.imagePaths.where((path) => path.trim().isNotEmpty),
        ];
        final savedVideoPaths = <String>[
          ...oldEntry.videoPaths.where((path) => path.trim().isNotEmpty),
        ];

        final nowMillis = oldEntry.createdAtMillis == 0
            ? DateTime.now().millisecondsSinceEpoch
            : oldEntry.createdAtMillis;

        final migratedEntry = JournalEntry(
          id: oldEntry.id.isEmpty
              ? DateTime.now().microsecondsSinceEpoch.toString()
              : oldEntry.id,
          userId: uid,
          placeId: oldEntry.placeId,
          placeName: oldEntry.placeName,
          letter: oldEntry.letter,
          imagePaths: savedImagePaths,
          videoPaths: savedVideoPaths,
          createdAt: oldEntry.createdAt.isEmpty
              ? DateTime.fromMillisecondsSinceEpoch(nowMillis).toIso8601String()
              : oldEntry.createdAt,
          createdAtMillis: nowMillis,
        );

        await _journalCollection()
            .doc(migratedEntry.id)
            .set(migratedEntry.toMap(), SetOptions(merge: true));
      } catch (_) {
        // Skip broken local entries so the online database can still work.
      }
    }

    await prefs.setBool(migrationFlagKey, true);
  }

  Future<void> addEntry(JournalEntry entry) async {
    await _journalCollection().doc(entry.id).set(entry.toMap());
  }

  Future<void> deleteEntry(String id) async {
    await _journalCollection().doc(id).delete();
  }
}
