import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/discovered_heritage_place.dart';

class HeritageDiscoveryService {
  final String geminiApiKey;
  final String geminiModel;

  const HeritageDiscoveryService({
    required this.geminiApiKey,
    required this.geminiModel,
  });

  static const String _userAgent =
      'HeritageBot-UCLM-Capstone/1.0 (academic heritage discovery prototype)';

  Future<HeritageDiscoveryResult> searchByLocation(String searchText) async {
    final query = searchText.trim();
    if (query.length < 2) {
      throw Exception(
        'Enter a city, barangay, municipality, or location to search.',
      );
    }

    final geocoded = await _geocode(query);
    var places = await _fetchHeritagePlaces(
      latitude: geocoded.latitude,
      longitude: geocoded.longitude,
      fallbackLocation: geocoded.displayName,
      radiusMeters: 15000,
    );

    if (places.isEmpty) {
      places = await _fetchHeritagePlaces(
        latitude: geocoded.latitude,
        longitude: geocoded.longitude,
        fallbackLocation: geocoded.displayName,
        radiusMeters: 30000,
      );
    }

    final enriched = await Future.wait(
      places
          .take(8)
          .map(
            (place) =>
                _enrichFromWikipedia(place, searchedArea: geocoded.displayName),
          ),
    );

    return HeritageDiscoveryResult(
      searchedText: query,
      resolvedLocation: geocoded.displayName,
      latitude: geocoded.latitude,
      longitude: geocoded.longitude,
      places: enriched,
    );
  }

  Future<String> generateAiGuide({
    required DiscoveredHeritagePlace place,
    required String searchedArea,
  }) async {
    final sourceSummary = place.sourceSummary.trim().isEmpty
        ? 'No encyclopedia summary was retrieved for this place.'
        : place.sourceSummary.trim();

    final tagLines = place.sourceTags.entries
        .where((entry) => entry.value.trim().isNotEmpty)
        .take(18)
        .map((entry) => '${entry.key}: ${entry.value}')
        .join('\n');

    if (geminiApiKey.isEmpty) {
      return _fallbackGuide(place, sourceSummary);
    }

    final prompt =
        '''
You are HeritageBot's heritage discovery explanation component.

The user searched this area: $searchedArea
Discovered place: ${place.name}
Category: ${place.category}
Location: ${place.location}
Coordinates: ${place.latitude}, ${place.longitude}

OPENSTREETMAP RETRIEVED METADATA:
$tagLines

RETRIEVED ENCYCLOPEDIA SUMMARY:
$sourceSummary

STRICT GROUNDING RULES:
- Use ONLY the retrieved metadata and encyclopedia summary above.
- Do not use hidden memory or invent dates, people, events, architecture, legends, or cultural claims.
- If the supplied sources do not contain enough historical detail, explicitly say that detailed historical information was not available in the retrieved sources.
- Treat this as an external discovery result, not as a verified HeritageBot knowledge-base record.
- Use clear, simple English suitable for tourists and students.

Return the response using exactly these headings:
WHAT CAN BE FOUND THERE
HISTORICAL BACKGROUND
CULTURAL SIGNIFICANCE
WHAT YOU CAN LEARN

Keep each section concise, around 2 to 4 sentences.
''';

    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/$geminiModel:generateContent',
    );

    try {
      final response = await http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'x-goog-api-key': geminiApiKey,
            },
            body: jsonEncode({
              'contents': [
                {
                  'parts': [
                    {'text': prompt},
                  ],
                },
              ],
              'generationConfig': {'temperature': 0.2, 'maxOutputTokens': 700},
            }),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        return _fallbackGuide(place, sourceSummary);
      }

      final data = jsonDecode(response.body);
      final text = data['candidates']?[0]?['content']?['parts']?[0]?['text'];
      if (text is String && text.trim().isNotEmpty) {
        return text.trim();
      }

      return _fallbackGuide(place, sourceSummary);
    } catch (_) {
      return _fallbackGuide(place, sourceSummary);
    }
  }

  Future<_GeocodedLocation> _geocode(String query) async {
    final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
      'q': query,
      'format': 'jsonv2',
      'addressdetails': '1',
      'limit': '1',
    });

    final response = await http
        .get(uri, headers: {'User-Agent': _userAgent, 'Accept-Language': 'en'})
        .timeout(const Duration(seconds: 20));

    if (response.statusCode != 200) {
      throw Exception(
        'The location search service could not be reached. Please try again.',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! List || decoded.isEmpty) {
      throw Exception(
        'Location not found. Try a more specific city, barangay, or municipality.',
      );
    }

    final first = Map<String, dynamic>.from(decoded.first as Map);
    final latitude = double.tryParse('${first['lat'] ?? ''}');
    final longitude = double.tryParse('${first['lon'] ?? ''}');

    if (latitude == null || longitude == null) {
      throw Exception(
        'The selected location did not provide usable coordinates.',
      );
    }

    return _GeocodedLocation(
      displayName: '${first['display_name'] ?? query}',
      latitude: latitude,
      longitude: longitude,
    );
  }

  Future<List<DiscoveredHeritagePlace>> _fetchHeritagePlaces({
    required double latitude,
    required double longitude,
    required String fallbackLocation,
    required int radiusMeters,
  }) async {
    final overpassQuery =
        '''
[out:json][timeout:25];
(
  nwr(around:$radiusMeters,$latitude,$longitude)["historic"]["name"];
  nwr(around:$radiusMeters,$latitude,$longitude)["heritage"]["name"];
  nwr(around:$radiusMeters,$latitude,$longitude)["tourism"="museum"]["name"];
  nwr(around:$radiusMeters,$latitude,$longitude)["tourism"="attraction"]["historic"]["name"];
);
out body center 60;
''';

    final response = await http
        .post(
          Uri.parse('https://overpass-api.de/api/interpreter'),
          headers: {'User-Agent': _userAgent},
          body: {'data': overpassQuery},
        )
        .timeout(const Duration(seconds: 35));

    if (response.statusCode != 200) {
      throw Exception(
        'Heritage discovery could not be completed right now. Please try again.',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map || decoded['elements'] is! List) {
      return const [];
    }

    final candidates = <_ScoredPlace>[];
    final seen = <String>{};

    for (final rawElement in decoded['elements'] as List) {
      if (rawElement is! Map) continue;
      final element = Map<String, dynamic>.from(rawElement);
      final tagsRaw = element['tags'];
      if (tagsRaw is! Map) continue;

      final tags = <String, String>{};
      for (final entry in tagsRaw.entries) {
        if (entry.value != null) {
          tags['${entry.key}'] = '${entry.value}';
        }
      }

      final name = (tags['name'] ?? '').trim();
      if (name.isEmpty) continue;

      final lat = _elementLatitude(element);
      final lon = _elementLongitude(element);
      if (lat == null || lon == null) continue;

      final normalized = name.toLowerCase().replaceAll(
        RegExp(r'[^a-z0-9]+'),
        '',
      );
      if (!seen.add(normalized)) continue;

      final type = '${element['type'] ?? 'node'}';
      final id = '${element['id'] ?? ''}';
      final osmUrl = id.isEmpty
          ? ''
          : 'https://www.openstreetmap.org/$type/$id';

      final place = DiscoveredHeritagePlace(
        id: '$type/$id',
        name: name,
        category: _categoryFromTags(tags),
        location: _locationFromTags(tags, fallbackLocation),
        latitude: lat,
        longitude: lon,
        osmUrl: osmUrl,
        wikipediaUrl: '',
        sourceSummary: '',
        sourceTags: tags,
      );

      candidates.add(_ScoredPlace(place: place, score: _score(tags)));
    }

    candidates.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      return a.place.name.toLowerCase().compareTo(b.place.name.toLowerCase());
    });

    return candidates.map((entry) => entry.place).take(12).toList();
  }

  Future<DiscoveredHeritagePlace> _enrichFromWikipedia(
    DiscoveredHeritagePlace place, {
    required String searchedArea,
  }) async {
    final wikipediaTag = place.sourceTags['wikipedia']?.trim() ?? '';
    String searchTerm;

    if (wikipediaTag.contains(':')) {
      searchTerm = wikipediaTag.split(':').skip(1).join(':').trim();
    } else if (wikipediaTag.isNotEmpty) {
      searchTerm = wikipediaTag;
    } else {
      searchTerm = '${place.name} $searchedArea';
    }

    final uri = Uri.https('en.wikipedia.org', '/w/api.php', {
      'action': 'query',
      'generator': 'search',
      'gsrsearch': searchTerm,
      'gsrlimit': '1',
      'prop': 'extracts|info',
      'exintro': '1',
      'explaintext': '1',
      'inprop': 'url',
      'format': 'json',
      'origin': '*',
    });

    try {
      final response = await http
          .get(uri, headers: {'User-Agent': _userAgent})
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) return place;
      final decoded = jsonDecode(response.body);
      final query = decoded is Map ? decoded['query'] : null;
      final pages = query is Map ? query['pages'] : null;
      if (pages is! Map || pages.isEmpty) return place;

      final first = Map<String, dynamic>.from(pages.values.first as Map);
      final extract = '${first['extract'] ?? ''}'.trim();
      final fullUrl = '${first['fullurl'] ?? ''}'.trim();

      if (extract.isEmpty) return place;

      return place.copyWith(sourceSummary: extract, wikipediaUrl: fullUrl);
    } catch (_) {
      return place;
    }
  }

  double? _elementLatitude(Map<String, dynamic> element) {
    final direct = element['lat'];
    if (direct is num) return direct.toDouble();
    final center = element['center'];
    if (center is Map && center['lat'] is num) {
      return (center['lat'] as num).toDouble();
    }
    return null;
  }

  double? _elementLongitude(Map<String, dynamic> element) {
    final direct = element['lon'];
    if (direct is num) return direct.toDouble();
    final center = element['center'];
    if (center is Map && center['lon'] is num) {
      return (center['lon'] as num).toDouble();
    }
    return null;
  }

  int _score(Map<String, String> tags) {
    var score = 0;
    if ((tags['heritage'] ?? '').isNotEmpty) score += 6;
    if ((tags['historic'] ?? '').isNotEmpty) score += 5;
    if (tags['tourism'] == 'museum') score += 5;
    if ((tags['wikipedia'] ?? '').isNotEmpty) score += 4;
    if ((tags['wikidata'] ?? '').isNotEmpty) score += 2;
    if ((tags['start_date'] ?? '').isNotEmpty) score += 2;
    if ((tags['description'] ?? '').isNotEmpty) score += 1;
    return score;
  }

  String _categoryFromTags(Map<String, String> tags) {
    if (tags['tourism'] == 'museum') return 'Museum';

    final historic = (tags['historic'] ?? '').trim();
    if (historic.isNotEmpty && historic != 'yes') {
      return _humanize(historic);
    }

    if ((tags['heritage'] ?? '').isNotEmpty) return 'Heritage Site';
    return 'Historical Place';
  }

  String _locationFromTags(Map<String, String> tags, String fallback) {
    final full = (tags['addr:full'] ?? '').trim();
    if (full.isNotEmpty) return full;

    final parts = <String>[
      tags['addr:housenumber'] ?? '',
      tags['addr:street'] ?? '',
      tags['addr:suburb'] ?? '',
      tags['addr:city'] ?? '',
      tags['addr:province'] ?? '',
    ].where((part) => part.trim().isNotEmpty).toList();

    if (parts.isNotEmpty) return parts.join(', ');

    final shortFallback = fallback.split(',').take(3).join(',').trim();
    return shortFallback.isEmpty ? fallback : shortFallback;
  }

  String _humanize(String value) {
    return value
        .replaceAll('_', ' ')
        .split(' ')
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }

  String _fallbackGuide(DiscoveredHeritagePlace place, String summary) {
    final historical =
        summary == 'No encyclopedia summary was retrieved for this place.'
        ? 'Detailed historical information was not available in the retrieved sources for this discovery result.'
        : summary;

    return '''
WHAT CAN BE FOUND THERE
${place.name} was discovered as a ${place.category.toLowerCase()} near ${place.location}. This result comes from external map data and is not automatically a registered HeritageBot geofence site.

HISTORICAL BACKGROUND
$historical

CULTURAL SIGNIFICANCE
The retrieved sources identify this place as heritage- or history-related. More specific cultural claims should be confirmed using official heritage, museum, government, or academic records before they are added to HeritageBot's verified knowledge base.

WHAT YOU CAN LEARN
You can use this discovery result as a starting point for learning about the place, its setting, and why it may be historically important. For verified study or research, compare the result with authoritative historical sources.
''';
  }
}

class _GeocodedLocation {
  final String displayName;
  final double latitude;
  final double longitude;

  const _GeocodedLocation({
    required this.displayName,
    required this.latitude,
    required this.longitude,
  });
}

class _ScoredPlace {
  final DiscoveredHeritagePlace place;
  final int score;

  const _ScoredPlace({required this.place, required this.score});
}
