class UserRoles {
  static const String tourist = 'tourist';
  static const String communityContributor = 'community_contributor';
  static const String admin = 'admin';

  static const List<String> publicRoles = [tourist, communityContributor];

  static bool isPublicRole(String role) => publicRoles.contains(role);

  static bool isValidRole(String role) =>
      role == tourist || role == communityContributor || role == admin;

  static String label(String role) {
    switch (role) {
      case communityContributor:
        return 'Community Contributor';
      case admin:
        return 'Administrator';
      case tourist:
        return 'Tourist';
      default:
        return 'Not Set';
    }
  }
}

class UserProfile {
  final String uid;
  final String fullName;
  final String email;
  final String role;
  final String preferredLanguage;
  final String accountStatus;
  final String photoUrl;
  final int createdAtMillis;

  const UserProfile({
    required this.uid,
    required this.fullName,
    required this.email,
    required this.role,
    required this.preferredLanguage,
    required this.accountStatus,
    required this.photoUrl,
    required this.createdAtMillis,
  });

  bool get isTourist => role == UserRoles.tourist;

  bool get isCommunityContributor => role == UserRoles.communityContributor;

  bool get isAdmin => role == UserRoles.admin;

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'fullName': fullName,
      'email': email,
      'role': role,
      'preferredLanguage': preferredLanguage,
      'accountStatus': accountStatus,
      'photoUrl': photoUrl,
      'createdAtMillis': createdAtMillis,
    };
  }

  factory UserProfile.fromMap(Map<String, dynamic> map, {required String uid}) {
    final createdAtRaw = map['createdAtMillis'];

    int createdAtMillis = 0;

    if (createdAtRaw is int) {
      createdAtMillis = createdAtRaw;
    } else if (createdAtRaw is num) {
      createdAtMillis = createdAtRaw.toInt();
    }

    return UserProfile(
      uid: map['uid']?.toString().trim().isNotEmpty == true
          ? map['uid'].toString()
          : uid,
      fullName: map['fullName']?.toString() ?? '',
      email: map['email']?.toString() ?? '',
      role: map['role']?.toString() ?? '',
      preferredLanguage:
          map['preferredLanguage']?.toString().trim().isNotEmpty == true
          ? map['preferredLanguage'].toString()
          : 'en',
      accountStatus: map['accountStatus']?.toString().trim().isNotEmpty == true
          ? map['accountStatus'].toString()
          : 'active',
      photoUrl: map['photoUrl']?.toString() ?? '',
      createdAtMillis: createdAtMillis,
    );
  }
}
