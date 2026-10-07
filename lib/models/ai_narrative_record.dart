class AiNarrativeReviewStatus {
  static const pendingReview = 'pending_review';
  static const verified = 'verified';
  static const needsReview = 'needs_review';

  static String label(String value) {
    switch (value) {
      case verified:
        return 'Verified';
      case needsReview:
        return 'Needs Review';
      case pendingReview:
      default:
        return 'Pending Review';
    }
  }
}

class AiNarrativeRecord {
  final String id;
  final String userId;
  final String siteId;
  final String siteName;
  final String narrative;
  final String languageCode;
  final String modelName;
  final String retrievalMode;
  final List<String> retrievedContentIds;
  final List<String> retrievedSourceTitles;
  final double distanceMeters;
  final String reviewStatus;
  final String adminReviewNote;
  final int createdAtMillis;
  final int reviewedAtMillis;

  const AiNarrativeRecord({
    required this.id,
    required this.userId,
    required this.siteId,
    required this.siteName,
    required this.narrative,
    required this.languageCode,
    required this.modelName,
    required this.retrievalMode,
    required this.retrievedContentIds,
    required this.retrievedSourceTitles,
    required this.distanceMeters,
    required this.reviewStatus,
    required this.adminReviewNote,
    required this.createdAtMillis,
    required this.reviewedAtMillis,
  });

  factory AiNarrativeRecord.fromMap(
    Map<String, dynamic> map, {
    required String documentId,
  }) {
    List<String> strings(dynamic raw) {
      if (raw is! List) return const [];
      return raw.map((item) => item.toString()).toList();
    }

    return AiNarrativeRecord(
      id: documentId,
      userId: map['userId']?.toString() ?? '',
      siteId: map['siteId']?.toString() ?? '',
      siteName: map['siteName']?.toString() ?? '',
      narrative: map['narrative']?.toString() ?? '',
      languageCode: map['languageCode']?.toString() ?? 'en',
      modelName: map['modelName']?.toString() ?? '',
      retrievalMode: map['retrievalMode']?.toString() ?? '',
      retrievedContentIds: strings(map['retrievedContentIds']),
      retrievedSourceTitles: strings(map['retrievedSourceTitles']),
      distanceMeters: (map['distanceMeters'] as num?)?.toDouble() ?? 0,
      reviewStatus:
          map['reviewStatus']?.toString() ??
          AiNarrativeReviewStatus.pendingReview,
      adminReviewNote: map['adminReviewNote']?.toString() ?? '',
      createdAtMillis: (map['createdAtMillis'] as num?)?.toInt() ?? 0,
      reviewedAtMillis: (map['reviewedAtMillis'] as num?)?.toInt() ?? 0,
    );
  }
}
