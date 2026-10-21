import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/heritage_place.dart';

class UsageAnalyticsService {
  UsageAnalyticsService({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  CollectionReference<Map<String, dynamic>> get _events =>
      _firestore.collection('usage_events');

  Future<void> trackSiteView(HeritagePlace site) async {
    await _record(
      eventType: 'site_view',
      data: {
        'siteId': site.id,
        'siteName': site.name,
        'siteLocation': site.location,
        'isTesting': site.isTesting,
      },
    );
  }

  Future<void> trackNavigationStart(HeritagePlace site) async {
    await _record(
      eventType: 'navigation_start',
      data: {
        'siteId': site.id,
        'siteName': site.name,
        'siteLocation': site.location,
        'isTesting': site.isTesting,
      },
    );
  }

  Future<void> trackDynamicHeritageSearch({
    required String query,
    required String resolvedLocation,
    required int resultCount,
  }) async {
    await _record(
      eventType: 'dynamic_search',
      data: {
        'query': query.trim(),
        'resolvedLocation': resolvedLocation.trim(),
        'resultCount': resultCount,
      },
    );
  }

  Future<void> _record({
    required String eventType,
    required Map<String, dynamic> data,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      final now = DateTime.now().millisecondsSinceEpoch;
      await _events.add({
        'eventType': eventType,
        'userId': user.uid,
        'userEmail': user.email?.trim() ?? '',
        'createdAtMillis': now,
        ...data,
      });
    } catch (_) {
      // Usage analytics must never interrupt the main HeritageBot experience.
    }
  }
}
