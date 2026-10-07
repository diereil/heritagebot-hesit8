import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/heritage_place.dart';

class HeritageSiteService {
  final CollectionReference<Map<String, dynamic>> _collection =
      FirebaseFirestore.instance.collection('heritage_sites');

  Future<List<HeritagePlace>> getAllSites() async {
    final snapshot = await _collection.get();

    final sites = snapshot.docs
        .map((doc) => HeritagePlace.fromMap(doc.data(), documentId: doc.id))
        .toList();

    sites.sort((a, b) {
      if (a.isTesting != b.isTesting) {
        return a.isTesting ? 1 : -1;
      }

      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    return sites;
  }

  Future<void> initializeRuntimeSites() async {
    try {
      final sites = await getAllSites();

      // If Firestore has not been initialized yet, keep the local
      // development defaults so the app still works.
      if (sites.isEmpty) {
        return;
      }

      _replaceRuntimeSites(sites);
    } catch (_) {
      // Keep the local defaults if Firestore is temporarily unavailable
      // or the latest rules have not been published yet.
    }
  }

  Future<void> refreshRuntimeSites() async {
    final sites = await getAllSites();

    if (sites.isEmpty) {
      heritagePlaces
        ..clear()
        ..addAll(defaultHeritagePlaces);
      return;
    }

    _replaceRuntimeSites(sites);
  }

  void _replaceRuntimeSites(List<HeritagePlace> sites) {
    final activeSites = sites.where((site) => site.isActive).toList();

    // Existing screens assume at least one active site.
    if (activeSites.isEmpty) {
      return;
    }

    heritagePlaces
      ..clear()
      ..addAll(activeSites);
  }

  Future<void> seedDefaultSites() async {
    final existing = await _collection.limit(1).get();

    if (existing.docs.isNotEmpty) {
      throw StateError('Heritage sites are already initialized in Firestore.');
    }

    final batch = FirebaseFirestore.instance.batch();

    for (final site in defaultHeritagePlaces) {
      batch.set(_collection.doc(site.id), {
        ...site.toMap(),
        'createdAtMillis': DateTime.now().millisecondsSinceEpoch,
        'updatedAtMillis': DateTime.now().millisecondsSinceEpoch,
      });
    }

    await batch.commit();
    await refreshRuntimeSites();
  }

  Future<HeritagePlace> createSite({
    required String name,
    required String location,
    required double lat,
    required double lng,
    required String historicalFacts,
    required String videoTitle,
    String? videoAsset,
    required String wikipediaTitle,
    required double detectionRadiusMeters,
    List<String> imageUrls = const [],
    required bool isTesting,
    required bool isActive,
  }) async {
    _validateSite(
      name: name,
      location: location,
      lat: lat,
      lng: lng,
      historicalFacts: historicalFacts,
      detectionRadiusMeters: detectionRadiusMeters,
    );

    final id = await _availableId(name);

    final site = HeritagePlace(
      id: id,
      name: name.trim(),
      location: location.trim(),
      lat: lat,
      lng: lng,
      historicalFacts: historicalFacts.trim(),
      videoTitle: videoTitle.trim(),
      videoAsset: _nullIfBlank(videoAsset),
      wikipediaTitle: wikipediaTitle.trim(),
      detectionRadiusMeters: detectionRadiusMeters,
      imageUrls: imageUrls,
      isTesting: isTesting,
      isActive: isActive,
    );

    await _collection.doc(id).set({
      ...site.toMap(),
      'createdAtMillis': DateTime.now().millisecondsSinceEpoch,
      'updatedAtMillis': DateTime.now().millisecondsSinceEpoch,
    });

    await refreshRuntimeSites();
    return site;
  }

  Future<void> updateSite(HeritagePlace site) async {
    _validateSite(
      name: site.name,
      location: site.location,
      lat: site.lat,
      lng: site.lng,
      historicalFacts: site.historicalFacts,
      detectionRadiusMeters: site.detectionRadiusMeters,
    );

    if (!site.isActive) {
      await _ensureAnotherActiveSite(site.id);
    }

    await _collection.doc(site.id).update({
      ...site.toMap(),
      'updatedAtMillis': DateTime.now().millisecondsSinceEpoch,
    });

    await refreshRuntimeSites();
  }

  Future<void> setActive(HeritagePlace site, bool isActive) async {
    if (!isActive && site.isActive) {
      await _ensureAnotherActiveSite(site.id);
    }

    await _collection.doc(site.id).update({
      'isActive': isActive,
      'updatedAtMillis': DateTime.now().millisecondsSinceEpoch,
    });

    await refreshRuntimeSites();
  }

  Future<void> deleteSite(HeritagePlace site) async {
    if (site.isActive) {
      await _ensureAnotherActiveSite(site.id);
    }

    await _collection.doc(site.id).delete();
    await refreshRuntimeSites();
  }

  Future<void> _ensureAnotherActiveSite(String excludedSiteId) async {
    final sites = await getAllSites();

    final anotherActive = sites.any(
      (site) => site.id != excludedSiteId && site.isActive,
    );

    if (!anotherActive) {
      throw StateError(
        'HeritageBot must keep at least one active heritage site.',
      );
    }
  }

  void _validateSite({
    required String name,
    required String location,
    required double lat,
    required double lng,
    required String historicalFacts,
    required double detectionRadiusMeters,
  }) {
    if (name.trim().length < 3) {
      throw ArgumentError('Please enter a valid heritage site name.');
    }

    if (location.trim().length < 3) {
      throw ArgumentError('Please enter the heritage site location.');
    }

    if (lat < -90 || lat > 90) {
      throw ArgumentError('Latitude must be between -90 and 90.');
    }

    if (lng < -180 || lng > 180) {
      throw ArgumentError('Longitude must be between -180 and 180.');
    }

    if (historicalFacts.trim().length < 20) {
      throw ArgumentError(
        'Please provide a more complete historical description.',
      );
    }

    if (detectionRadiusMeters < 10 || detectionRadiusMeters > 50000) {
      throw ArgumentError(
        'Detection radius must be between 10 and 50000 meters.',
      );
    }
  }

  Future<String> _availableId(String name) async {
    final base = _slugify(name);
    var candidate = base;
    var counter = 2;

    while ((await _collection.doc(candidate).get()).exists) {
      candidate = '${base}_$counter';
      counter++;
    }

    return candidate;
  }

  String _slugify(String value) {
    final lower = value.trim().toLowerCase();
    final cleaned = lower
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');

    if (cleaned.isEmpty) {
      return 'heritage_site_${DateTime.now().millisecondsSinceEpoch}';
    }

    return cleaned;
  }

  String? _nullIfBlank(String? value) {
    final safe = value?.trim() ?? '';
    return safe.isEmpty ? null : safe;
  }
}
