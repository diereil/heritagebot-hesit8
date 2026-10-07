class HeritagePlace {
  final String id;
  final String name;
  final String location;
  final double lat;
  final double lng;
  final String historicalFacts;
  final String videoTitle;
  final String? videoAsset;
  final String wikipediaTitle;

  /// Geofence radius used to trigger a location-aware narrative.
  final double detectionRadiusMeters;

  /// Administrator-managed site photos stored as Cloudinary URLs.
  final List<String> imageUrls;

  /// true only for development/testing locations such as UCLM.
  final bool isTesting;

  /// Prepared for the later Firestore heritage-site management module.
  final bool isActive;

  const HeritagePlace({
    required this.id,
    required this.name,
    required this.location,
    required this.lat,
    required this.lng,
    required this.historicalFacts,
    required this.videoTitle,
    this.videoAsset,
    required this.wikipediaTitle,
    this.detectionRadiusMeters = 20000,
    this.imageUrls = const [],
    this.isTesting = false,
    this.isActive = true,
  });

  bool get hasVideo => videoAsset != null && videoAsset!.isNotEmpty;

  bool get isOfficial => !isTesting;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'location': location,
      'lat': lat,
      'lng': lng,
      'historicalFacts': historicalFacts,
      'videoTitle': videoTitle,
      'videoAsset': videoAsset,
      'wikipediaTitle': wikipediaTitle,
      'detectionRadiusMeters': detectionRadiusMeters,
      'imageUrls': imageUrls,
      'isTesting': isTesting,
      'isActive': isActive,
    };
  }

  HeritagePlace copyWith({
    String? id,
    String? name,
    String? location,
    double? lat,
    double? lng,
    String? historicalFacts,
    String? videoTitle,
    String? videoAsset,
    bool clearVideoAsset = false,
    String? wikipediaTitle,
    double? detectionRadiusMeters,
    List<String>? imageUrls,
    bool? isTesting,
    bool? isActive,
  }) {
    return HeritagePlace(
      id: id ?? this.id,
      name: name ?? this.name,
      location: location ?? this.location,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      historicalFacts: historicalFacts ?? this.historicalFacts,
      videoTitle: videoTitle ?? this.videoTitle,
      videoAsset: clearVideoAsset ? null : (videoAsset ?? this.videoAsset),
      wikipediaTitle: wikipediaTitle ?? this.wikipediaTitle,
      detectionRadiusMeters:
          detectionRadiusMeters ?? this.detectionRadiusMeters,
      imageUrls: imageUrls ?? List<String>.of(this.imageUrls),
      isTesting: isTesting ?? this.isTesting,
      isActive: isActive ?? this.isActive,
    );
  }

  factory HeritagePlace.fromMap(
    Map<String, dynamic> map, {
    String? documentId,
  }) {
    double asDouble(dynamic value) {
      if (value is num) return value.toDouble();
      return double.tryParse(value?.toString() ?? '') ?? 0;
    }

    return HeritagePlace(
      id: (map['id'] ?? documentId ?? '').toString(),
      name: map['name']?.toString() ?? '',
      location: map['location']?.toString() ?? '',
      lat: asDouble(map['lat']),
      lng: asDouble(map['lng']),
      historicalFacts: map['historicalFacts']?.toString() ?? '',
      videoTitle: map['videoTitle']?.toString() ?? '',
      videoAsset: map['videoAsset']?.toString().trim().isNotEmpty == true
          ? map['videoAsset'].toString()
          : null,
      wikipediaTitle: map['wikipediaTitle']?.toString() ?? '',
      detectionRadiusMeters: asDouble(map['detectionRadiusMeters']) > 0
          ? asDouble(map['detectionRadiusMeters'])
          : 20000,
      imageUrls: (map['imageUrls'] as List<dynamic>? ?? const [])
          .map((item) => item.toString())
          .where((item) => item.trim().isNotEmpty)
          .toList(),
      isTesting: map['isTesting'] == true,
      isActive: map['isActive'] != false,
    );
  }
}

/// CURRENT DEVELOPMENT SCOPE
///
/// Official research sites:
/// 1. Casa Gorordo Museum
/// 2. Heritage of Cebu Monument, Pari-an
/// 3. Fort San Pedro
///
/// UCLM is retained strictly as a development/testing location.
const List<HeritagePlace> defaultHeritagePlaces = [
  HeritagePlace(
    id: 'uclm',
    name: 'University of Cebu Lapu-Lapu and Mandaue',
    location: 'A.C. Cortes Avenue, Mandaue City, Cebu',
    lat: 10.32639,
    lng: 123.95451,
    videoTitle: 'UCLM Testing Video',
    videoAsset: 'assets/videos/uclm.mp4',
    wikipediaTitle: 'University of Cebu',
    detectionRadiusMeters: 20000,
    isTesting: true,
    historicalFacts:
        'UCLM is included in HeritageBot only as a development and geolocation testing location. It is not one of the official heritage sites covered by the study.',
  ),
  HeritagePlace(
    id: 'casa_gorordo',
    name: 'Casa Gorordo Museum',
    location: 'Eduardo Aboitiz Street, Cebu City',
    lat: 10.29991,
    lng: 123.90489,
    videoTitle: 'Casa Gorordo Museum Video',
    videoAsset: 'assets/videos/casa_gorordo.mp4',
    wikipediaTitle: 'Casa Gorordo Museum',
    detectionRadiusMeters: 20000,
    historicalFacts:
        'Casa Gorordo Museum presents the lifestyle of a Cebuano family during the Spanish colonial period. The historic house preserves objects, furnishings, and cultural materials that help visitors understand domestic life in old Cebu.',
  ),
  HeritagePlace(
    id: 'cebu_heritage_monument',
    name: 'Heritage of Cebu Monument',
    location: 'Pari-an, Cebu City',
    lat: 10.29889,
    lng: 123.90362,
    videoTitle: 'Heritage of Cebu Monument Video',
    wikipediaTitle: 'Heritage of Cebu Monument',
    detectionRadiusMeters: 20000,
    historicalFacts:
        'The Heritage of Cebu Monument in Pari-an is a large sculptural tableau depicting important events, people, and symbols in Cebu history. Created by sculptor Eduardo Castrillo, it provides a visual introduction to Cebu’s historical development.',
  ),
  HeritagePlace(
    id: 'fort_san_pedro',
    name: 'Fort San Pedro',
    location: 'Plaza Independencia, Cebu City',
    lat: 10.29261,
    lng: 123.90579,
    videoTitle: 'Fort San Pedro Historical Video',
    videoAsset: 'assets/videos/fort_san_pedro.mp4',
    wikipediaTitle: 'Fort San Pedro',
    detectionRadiusMeters: 20000,
    historicalFacts:
        'Fort San Pedro is a Spanish colonial military defense structure in Cebu City. It served as a fortification during the colonial period and is now preserved as a heritage and tourism site.',
  ),
];

/// Runtime site list used by the existing HeritageBot screens.
///
/// On first installation this starts with the four development defaults.
/// When Firestore contains `heritage_sites`, HeritageSiteService replaces
/// this list with the active Firestore records before the app opens.
final List<HeritagePlace> heritagePlaces = List<HeritagePlace>.of(
  defaultHeritagePlaces,
);

List<HeritagePlace> get officialHeritagePlaces => heritagePlaces
    .where((place) => place.isOfficial && place.isActive)
    .toList();

List<HeritagePlace> get activeHeritagePlaces =>
    heritagePlaces.where((place) => place.isActive).toList();
