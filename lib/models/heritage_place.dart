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
  });

  bool get hasVideo => videoAsset != null && videoAsset!.isNotEmpty;
}

const List<HeritagePlace> heritagePlaces = [
  HeritagePlace(
    id: 'uclm',
    name: 'University of Cebu Lapu-Lapu and Mandaue',
    location: 'A.C. Cortes Avenue, Mandaue City, Cebu',
    lat: 10.32639,
    lng: 123.95451,
    videoTitle: 'UCLM School Heritage Video',
    videoAsset: 'assets/videos/uclm.mp4',
    wikipediaTitle: 'University of Cebu',
    historicalFacts:
        'The University of Cebu Lapu-Lapu and Mandaue, also known as UCLM, is an educational institution located along A.C. Cortes Avenue in Mandaue City. It is a meaningful place for students, alumni, families, and visitors because it connects education, personal growth, friendships, and school memories.',
  ),
  HeritagePlace(
    id: 'magellans_cross',
    name: 'Magellan’s Cross',
    location: 'Cebu City',
    lat: 10.2930,
    lng: 123.9020,
    videoTitle: 'Magellan’s Cross Heritage Video',
    videoAsset: 'assets/videos/magellans_cross.mp4',
    wikipediaTitle: "Magellan's Cross",
    historicalFacts:
        'Magellan’s Cross is one of Cebu’s most recognized landmarks. It is traditionally associated with the arrival of Christianity in the Philippines and is an important symbol of Cebuano history, faith, and tourism.',
  ),
  HeritagePlace(
    id: 'fort_san_pedro',
    name: 'Fort San Pedro',
    location: 'Cebu City',
    lat: 10.2923,
    lng: 123.9058,
    videoTitle: 'Fort San Pedro Historical Video',
    videoAsset: 'assets/videos/fort_san_pedro.mp4',
    wikipediaTitle: 'Fort San Pedro',
    historicalFacts:
        'Fort San Pedro is a Spanish colonial military defense structure in Cebu City. It served as a fortification during the colonial period and is now preserved as a heritage and tourism site.',
  ),
  HeritagePlace(
    id: 'basilica_santo_nino',
    name: 'Basilica Minore del Santo Niño',
    location: 'Cebu City',
    lat: 10.2939,
    lng: 123.9013,
    videoTitle: 'Santo Niño Heritage Video',
    videoAsset: 'assets/videos/basilica_santo_nino.mp4',
    wikipediaTitle: 'Basilica Minore del Santo Niño',
    historicalFacts:
        'The Basilica Minore del Santo Niño is one of the oldest Roman Catholic churches in the Philippines. It is closely connected to Cebuano devotion, the Santo Niño, and the Sinulog celebration.',
  ),
  HeritagePlace(
    id: 'casa_gorordo',
    name: 'Casa Gorordo Museum',
    location: 'Cebu City',
    lat: 10.3006,
    lng: 123.8996,
    videoTitle: 'Casa Gorordo Museum Video',
    videoAsset: 'assets/videos/casa_gorordo.mp4',
    wikipediaTitle: 'Casa Gorordo Museum',
    historicalFacts:
        'Casa Gorordo Museum presents the lifestyle of a Cebuano family during the Spanish colonial period. It preserves antique furniture, religious objects, religious images, household materials, and cultural items that show how old Cebuano families lived during the colonial era.',
  ),
];
