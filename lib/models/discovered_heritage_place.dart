class DiscoveredHeritagePlace {
  final String id;
  final String name;
  final String category;
  final String location;
  final double latitude;
  final double longitude;
  final String osmUrl;
  final String wikipediaUrl;
  final String sourceSummary;
  final Map<String, String> sourceTags;

  const DiscoveredHeritagePlace({
    required this.id,
    required this.name,
    required this.category,
    required this.location,
    required this.latitude,
    required this.longitude,
    required this.osmUrl,
    required this.wikipediaUrl,
    required this.sourceSummary,
    required this.sourceTags,
  });

  DiscoveredHeritagePlace copyWith({
    String? wikipediaUrl,
    String? sourceSummary,
  }) {
    return DiscoveredHeritagePlace(
      id: id,
      name: name,
      category: category,
      location: location,
      latitude: latitude,
      longitude: longitude,
      osmUrl: osmUrl,
      wikipediaUrl: wikipediaUrl ?? this.wikipediaUrl,
      sourceSummary: sourceSummary ?? this.sourceSummary,
      sourceTags: sourceTags,
    );
  }
}

class HeritageDiscoveryResult {
  final String searchedText;
  final String resolvedLocation;
  final double latitude;
  final double longitude;
  final List<DiscoveredHeritagePlace> places;

  const HeritageDiscoveryResult({
    required this.searchedText,
    required this.resolvedLocation,
    required this.latitude,
    required this.longitude,
    required this.places,
  });
}
