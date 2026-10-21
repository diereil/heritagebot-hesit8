import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/community_submission.dart';
import '../models/heritage_place.dart';
import '../models/user_profile.dart';
import 'community_submission_service.dart';
import 'heritage_site_service.dart';
import 'user_service.dart';

class SiteAnalyticsMetric {
  final String siteId;
  final String siteName;
  final int count;

  const SiteAnalyticsMetric({
    required this.siteId,
    required this.siteName,
    required this.count,
  });
}

class AdminAnalyticsSnapshot {
  final List<UserProfile> users;
  final List<HeritagePlace> sites;
  final List<CommunitySubmission> submissions;
  final int generatedNarratives;
  final int siteViews;
  final int dynamicSearches;
  final int navigationStarts;
  final int communityActivityLast30Days;
  final List<SiteAnalyticsMetric> topViewedSites;
  final List<SiteAnalyticsMetric> topBookmarkedSites;

  const AdminAnalyticsSnapshot({
    required this.users,
    required this.sites,
    required this.submissions,
    required this.generatedNarratives,
    required this.siteViews,
    required this.dynamicSearches,
    required this.navigationStarts,
    required this.communityActivityLast30Days,
    required this.topViewedSites,
    required this.topBookmarkedSites,
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
    if (totalSubmissions == 0) return 0;
    return approvedSubmissions / totalSubmissions;
  }
}

class AdminAnalyticsService {
  AdminAnalyticsService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;
  final UserService _userService = UserService();
  final HeritageSiteService _siteService = HeritageSiteService();
  final CommunitySubmissionService _submissionService =
      CommunitySubmissionService();

  Future<AdminAnalyticsSnapshot> loadSnapshot() async {
    final results = await Future.wait<dynamic>([
      _userService.getAllUsers(),
      _siteService.getAllSites(),
      _submissionService.getAllSubmissions(),
      _firestore.collection('ai_narratives').get(),
      _firestore.collection('usage_events').get(),
      _firestore.collectionGroup('bookmarks').get(),
    ]);

    final users = results[0] as List<UserProfile>;
    final sites = results[1] as List<HeritagePlace>;
    final submissions = results[2] as List<CommunitySubmission>;
    final narratives = results[3] as QuerySnapshot<Map<String, dynamic>>;
    final usageEvents = results[4] as QuerySnapshot<Map<String, dynamic>>;
    final bookmarks = results[5] as QuerySnapshot<Map<String, dynamic>>;

    final siteNameById = <String, String>{
      for (final site in sites) site.id: site.name,
    };

    var siteViews = 0;
    var dynamicSearches = 0;
    var navigationStarts = 0;
    final viewedCounts = <String, int>{};
    final viewedNames = <String, String>{};

    for (final doc in usageEvents.docs) {
      final data = doc.data();
      final type = data['eventType']?.toString() ?? '';

      if (type == 'site_view') {
        siteViews++;
        final siteId = data['siteId']?.toString() ?? '';
        if (siteId.isNotEmpty) {
          viewedCounts[siteId] = (viewedCounts[siteId] ?? 0) + 1;
          viewedNames[siteId] =
              data['siteName']?.toString().trim().isNotEmpty == true
              ? data['siteName'].toString().trim()
              : (siteNameById[siteId] ?? siteId);
        }
      } else if (type == 'dynamic_search') {
        dynamicSearches++;
      } else if (type == 'navigation_start') {
        navigationStarts++;
      }
    }

    final bookmarkCounts = <String, int>{};
    final bookmarkNames = <String, String>{};

    for (final doc in bookmarks.docs) {
      final data = doc.data();
      final siteId = (data['siteId'] ?? doc.id).toString();
      if (siteId.isEmpty) continue;

      bookmarkCounts[siteId] = (bookmarkCounts[siteId] ?? 0) + 1;
      bookmarkNames[siteId] =
          data['siteName']?.toString().trim().isNotEmpty == true
          ? data['siteName'].toString().trim()
          : (siteNameById[siteId] ?? siteId);
    }

    final cutoff = DateTime.now()
        .subtract(const Duration(days: 30))
        .millisecondsSinceEpoch;
    final communityActivityLast30Days = submissions.where((submission) {
      final latest = submission.updatedAtMillis > submission.createdAtMillis
          ? submission.updatedAtMillis
          : submission.createdAtMillis;
      return latest >= cutoff;
    }).length;

    return AdminAnalyticsSnapshot(
      users: users,
      sites: sites,
      submissions: submissions,
      generatedNarratives: narratives.docs.length,
      siteViews: siteViews,
      dynamicSearches: dynamicSearches,
      navigationStarts: navigationStarts,
      communityActivityLast30Days: communityActivityLast30Days,
      topViewedSites: _rankSites(viewedCounts, viewedNames),
      topBookmarkedSites: _rankSites(bookmarkCounts, bookmarkNames),
    );
  }

  List<SiteAnalyticsMetric> _rankSites(
    Map<String, int> counts,
    Map<String, String> names,
  ) {
    final items =
        counts.entries
            .map(
              (entry) => SiteAnalyticsMetric(
                siteId: entry.key,
                siteName: names[entry.key] ?? entry.key,
                count: entry.value,
              ),
            )
            .toList()
          ..sort((a, b) {
            final byCount = b.count.compareTo(a.count);
            if (byCount != 0) return byCount;
            return a.siteName.toLowerCase().compareTo(b.siteName.toLowerCase());
          });

    return items.take(5).toList();
  }
}
