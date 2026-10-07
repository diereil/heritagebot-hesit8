import '../models/community_submission.dart';
import '../models/heritage_place.dart';
import '../models/user_profile.dart';
import 'community_submission_service.dart';
import 'heritage_site_service.dart';
import 'user_service.dart';

class AdminAnalyticsSnapshot {
  final List<UserProfile> users;
  final List<HeritagePlace> sites;
  final List<CommunitySubmission> submissions;

  const AdminAnalyticsSnapshot({
    required this.users,
    required this.sites,
    required this.submissions,
  });

  int get totalUsers => users.length;
  int get tourists =>
      users.where((user) => user.role == UserRoles.tourist).length;
  int get contributors =>
      users.where((user) => user.role == UserRoles.communityContributor).length;
  int get admins => users.where((user) => user.role == UserRoles.admin).length;

  int get activeUsers => users
      .where((user) => user.accountStatus.toLowerCase() == 'active')
      .length;
  int get suspendedUsers => users
      .where((user) => user.accountStatus.toLowerCase() == 'suspended')
      .length;

  int get totalSites => sites.length;
  int get officialSites => sites.where((site) => site.isOfficial).length;
  int get testingSites => sites.where((site) => site.isTesting).length;
  int get activeSites => sites.where((site) => site.isActive).length;
  int get inactiveSites => sites.where((site) => !site.isActive).length;

  int get totalSubmissions => submissions.length;
  int get pendingSubmissions => submissions
      .where(
        (submission) => submission.status == CommunitySubmissionStatus.pending,
      )
      .length;
  int get approvedSubmissions => submissions
      .where(
        (submission) => submission.status == CommunitySubmissionStatus.approved,
      )
      .length;
  int get rejectedSubmissions => submissions
      .where(
        (submission) => submission.status == CommunitySubmissionStatus.rejected,
      )
      .length;

  double get approvalRate {
    if (totalSubmissions == 0) {
      return 0;
    }

    return approvedSubmissions / totalSubmissions;
  }
}

class AdminAnalyticsService {
  final UserService _userService = UserService();
  final HeritageSiteService _siteService = HeritageSiteService();
  final CommunitySubmissionService _submissionService =
      CommunitySubmissionService();

  Future<AdminAnalyticsSnapshot> loadSnapshot() async {
    final results = await Future.wait<dynamic>([
      _userService.getAllUsers(),
      _siteService.getAllSites(),
      _submissionService.getAllSubmissions(),
    ]);

    return AdminAnalyticsSnapshot(
      users: results[0] as List<UserProfile>,
      sites: results[1] as List<HeritagePlace>,
      submissions: results[2] as List<CommunitySubmission>,
    );
  }
}
