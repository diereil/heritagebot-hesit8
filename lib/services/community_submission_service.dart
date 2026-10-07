import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/community_submission.dart';

class CommunitySubmissionService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection('community_submissions');

  String createSubmissionId() => _collection.doc().id;

  User get _currentUser {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      throw FirebaseAuthException(
        code: 'not-logged-in',
        message: 'Please log in before using community submissions.',
      );
    }

    return user;
  }

  Future<List<CommunitySubmission>> getMySubmissions() async {
    final user = _currentUser;

    final snapshot = await _collection
        .where('contributorId', isEqualTo: user.uid)
        .get();

    final submissions = snapshot.docs
        .map(
          (doc) => CommunitySubmission.fromMap(doc.data(), documentId: doc.id),
        )
        .toList();

    submissions.sort((a, b) => b.createdAtMillis.compareTo(a.createdAtMillis));

    return submissions;
  }

  Future<CommunitySubmission> submitStory({
    required String submissionId,
    required String contributorName,
    required String heritagePlaceId,
    required String heritagePlaceName,
    required String title,
    required String story,
    required List<String> imageUrls,
    required List<String> videoUrls,
  }) async {
    final user = _currentUser;

    final reference = _collection.doc(submissionId);
    final now = DateTime.now().millisecondsSinceEpoch;

    final submission = CommunitySubmission(
      id: submissionId,
      contributorId: user.uid,
      contributorName: contributorName.trim().isEmpty
          ? (user.displayName?.trim().isNotEmpty == true
                ? user.displayName!.trim()
                : 'Community Contributor')
          : contributorName.trim(),
      contributorEmail: user.email?.trim() ?? '',
      heritagePlaceId: heritagePlaceId,
      heritagePlaceName: heritagePlaceName,
      title: title.trim(),
      story: story.trim(),
      status: CommunitySubmissionStatus.pending,
      adminFeedback: '',
      imageUrls: imageUrls,
      videoUrls: videoUrls,
      createdAtMillis: now,
      updatedAtMillis: now,
    );

    await reference.set(submission.toMap());

    return submission;
  }

  Future<void> updatePendingSubmission({
    required CommunitySubmission submission,
    required String heritagePlaceId,
    required String heritagePlaceName,
    required String title,
    required String story,
    required List<String> imageUrls,
    required List<String> videoUrls,
  }) async {
    final user = _currentUser;

    if (submission.contributorId != user.uid) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
        message: 'You can only edit your own submission.',
      );
    }

    if (submission.status != CommunitySubmissionStatus.pending) {
      throw StateError('Only pending submissions can be edited.');
    }

    final safeTitle = title.trim();
    final safeStory = story.trim();

    if (safeTitle.length < 3) {
      throw ArgumentError('Please enter a story title.');
    }

    if (safeStory.length < 20) {
      throw ArgumentError(
        'Please write a more complete heritage story before saving.',
      );
    }

    await _collection.doc(submission.id).update({
      'heritagePlaceId': heritagePlaceId,
      'heritagePlaceName': heritagePlaceName,
      'title': safeTitle,
      'story': safeStory,
      'imageUrls': imageUrls,
      'videoUrls': videoUrls,
      'status': CommunitySubmissionStatus.pending,
      'updatedAtMillis': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> deletePendingSubmission(CommunitySubmission submission) async {
    final user = _currentUser;

    if (submission.contributorId != user.uid) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
        message: 'You can only delete your own submission.',
      );
    }

    if (submission.status != CommunitySubmissionStatus.pending) {
      throw StateError('Only pending submissions can be deleted.');
    }

    await _collection.doc(submission.id).delete();
  }

  Future<List<CommunitySubmission>> getApprovedSubmissions() async {
    _currentUser;

    final snapshot = await _collection
        .where('status', isEqualTo: CommunitySubmissionStatus.approved)
        .get();

    final submissions = snapshot.docs
        .map(
          (doc) => CommunitySubmission.fromMap(doc.data(), documentId: doc.id),
        )
        .toList();

    submissions.sort((a, b) => b.updatedAtMillis.compareTo(a.updatedAtMillis));

    return submissions;
  }

  Future<List<CommunitySubmission>> getAllSubmissions() async {
    _currentUser;

    final snapshot = await _collection.get();

    final submissions = snapshot.docs
        .map(
          (doc) => CommunitySubmission.fromMap(doc.data(), documentId: doc.id),
        )
        .toList();

    submissions.sort((a, b) => b.createdAtMillis.compareTo(a.createdAtMillis));

    return submissions;
  }

  Future<void> reviewSubmission({
    required String submissionId,
    required String status,
    required String adminFeedback,
  }) async {
    _currentUser;

    if (status != CommunitySubmissionStatus.approved &&
        status != CommunitySubmissionStatus.rejected) {
      throw ArgumentError('Review status must be approved or rejected.');
    }

    await _collection.doc(submissionId).update({
      'status': status,
      'adminFeedback': adminFeedback.trim(),
      'updatedAtMillis': DateTime.now().millisecondsSinceEpoch,
    });
  }
}
