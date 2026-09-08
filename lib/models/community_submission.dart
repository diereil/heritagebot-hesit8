class CommunitySubmissionStatus {
  static const String pending = 'pending';
  static const String approved = 'approved';
  static const String rejected = 'rejected';

  static String label(String status) {
    switch (status) {
      case approved:
        return 'Approved';
      case rejected:
        return 'Rejected';
      case pending:
      default:
        return 'Pending';
    }
  }
}

class CommunitySubmission {
  final String id;
  final String contributorId;
  final String contributorName;
  final String contributorEmail;
  final String heritagePlaceId;
  final String heritagePlaceName;
  final String title;
  final String story;
  final String status;
  final String adminFeedback;
  final List<String> imageUrls;
  final List<String> videoUrls;
  final int createdAtMillis;
  final int updatedAtMillis;

  const CommunitySubmission({
    required this.id,
    required this.contributorId,
    required this.contributorName,
    required this.contributorEmail,
    required this.heritagePlaceId,
    required this.heritagePlaceName,
    required this.title,
    required this.story,
    required this.status,
    required this.adminFeedback,
    required this.imageUrls,
    required this.videoUrls,
    required this.createdAtMillis,
    required this.updatedAtMillis,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'contributorId': contributorId,
      'contributorName': contributorName,
      'contributorEmail': contributorEmail,
      'heritagePlaceId': heritagePlaceId,
      'heritagePlaceName': heritagePlaceName,
      'title': title,
      'story': story,
      'status': status,
      'adminFeedback': adminFeedback,
      'imageUrls': imageUrls,
      'videoUrls': videoUrls,
      'createdAtMillis': createdAtMillis,
      'updatedAtMillis': updatedAtMillis,
    };
  }

  factory CommunitySubmission.fromMap(
    Map<String, dynamic> map, {
    required String documentId,
  }) {
    int intValue(dynamic value) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      return 0;
    }

    List<String> stringList(dynamic value) {
      if (value is List) {
        return value.map((item) => item.toString()).toList();
      }
      return const [];
    }

    return CommunitySubmission(
      id: map['id']?.toString().trim().isNotEmpty == true
          ? map['id'].toString()
          : documentId,
      contributorId: map['contributorId']?.toString() ?? '',
      contributorName: map['contributorName']?.toString() ?? '',
      contributorEmail: map['contributorEmail']?.toString() ?? '',
      heritagePlaceId: map['heritagePlaceId']?.toString() ?? '',
      heritagePlaceName: map['heritagePlaceName']?.toString() ?? '',
      title: map['title']?.toString() ?? '',
      story: map['story']?.toString() ?? '',
      status: map['status']?.toString().trim().isNotEmpty == true
          ? map['status'].toString()
          : CommunitySubmissionStatus.pending,
      adminFeedback: map['adminFeedback']?.toString() ?? '',
      imageUrls: stringList(map['imageUrls']),
      videoUrls: stringList(map['videoUrls']),
      createdAtMillis: intValue(map['createdAtMillis']),
      updatedAtMillis: intValue(map['updatedAtMillis']),
    );
  }
}
