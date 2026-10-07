import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/heritage_place.dart';

class BookmarkService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String get _uid {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid == null || uid.trim().isEmpty) {
      throw FirebaseAuthException(
        code: 'not-logged-in',
        message: 'Please log in before using bookmarks.',
      );
    }

    return uid;
  }

  CollectionReference<Map<String, dynamic>> _collection() {
    return _firestore.collection('users').doc(_uid).collection('bookmarks');
  }

  Future<Set<String>> getBookmarkedSiteIds() async {
    final snapshot = await _collection().get();

    return snapshot.docs.map((doc) {
      final data = doc.data();
      return (data['siteId'] ?? doc.id).toString();
    }).toSet();
  }

  Future<bool> isBookmarked(String siteId) async {
    final doc = await _collection().doc(siteId).get();
    return doc.exists;
  }

  Future<void> addBookmark(HeritagePlace place) async {
    await _collection().doc(place.id).set({
      'siteId': place.id,
      'siteName': place.name,
      'location': place.location,
      'isTesting': place.isTesting,
      'createdAtMillis': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> removeBookmark(String siteId) async {
    await _collection().doc(siteId).delete();
  }

  Future<bool> toggleBookmark(HeritagePlace place) async {
    final bookmarked = await isBookmarked(place.id);

    if (bookmarked) {
      await removeBookmark(place.id);
      return false;
    }

    await addBookmark(place);
    return true;
  }
}
