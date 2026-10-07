import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/ai_narrative_record.dart';

class AiNarrativeService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection('ai_narratives');

  Future<void> recordGeneratedNarrative({
    required String siteId,
    required String siteName,
    required String narrative,
    required String languageCode,
    required String modelName,
    required String retrievalMode,
    required List<String> retrievedContentIds,
    required List<String> retrievedSourceTitles,
    required double distanceMeters,
  }) async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return;
    }

    final reference = _collection.doc();
    final now = DateTime.now().millisecondsSinceEpoch;

    await reference.set({
      'userId': user.uid,
      'siteId': siteId,
      'siteName': siteName,
      'narrative': narrative,
      'languageCode': languageCode,
      'modelName': modelName,
      'retrievalMode': retrievalMode,
      'retrievedContentIds': retrievedContentIds,
      'retrievedSourceTitles': retrievedSourceTitles,
      'distanceMeters': distanceMeters,
      'reviewStatus': AiNarrativeReviewStatus.pendingReview,
      'adminReviewNote': '',
      'createdAtMillis': now,
      'reviewedAtMillis': 0,
    });
  }

  Future<List<AiNarrativeRecord>> getRecentNarratives({int limit = 100}) async {
    final snapshot = await _collection.get();

    final records =
        snapshot.docs
            .map(
              (doc) =>
                  AiNarrativeRecord.fromMap(doc.data(), documentId: doc.id),
            )
            .toList()
          ..sort((a, b) => b.createdAtMillis.compareTo(a.createdAtMillis));

    return records.take(limit).toList();
  }

  Future<void> reviewNarrative({
    required String narrativeId,
    required String status,
    required String note,
  }) async {
    if (status != AiNarrativeReviewStatus.verified &&
        status != AiNarrativeReviewStatus.needsReview) {
      throw ArgumentError('Narrative review status is invalid.');
    }

    await _collection.doc(narrativeId).update({
      'reviewStatus': status,
      'adminReviewNote': note.trim(),
      'reviewedAtMillis': DateTime.now().millisecondsSinceEpoch,
    });
  }
}
