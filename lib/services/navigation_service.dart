import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../models/navigation_route.dart';

class NavigationService {
  static const String _routeEndpoint =
      'https://valhalla1.openstreetmap.de/route';

  const NavigationService();

  Future<HeritageNavigationRoute> buildPedestrianRoute({
    required LatLng start,
    required LatLng destination,
  }) async {
    final payload = <String, dynamic>{
      'locations': [
        {'lat': start.latitude, 'lon': start.longitude, 'type': 'break'},
        {
          'lat': destination.latitude,
          'lon': destination.longitude,
          'type': 'break',
        },
      ],
      'costing': 'pedestrian',
      'units': 'kilometers',
      'directions_options': {'units': 'kilometers', 'language': 'en-US'},
    };

    final response = await http
        .post(
          Uri.parse(_routeEndpoint),
          headers: const {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'X-Client-Id': 'heritagebot-uclm-capstone',
          },
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 25));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Navigation route service returned HTTP ${response.statusCode}.',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw Exception('Navigation service returned an invalid response.');
    }

    if (decoded['error'] != null) {
      throw Exception(decoded['error'].toString());
    }

    final trip = decoded['trip'];
    if (trip is! Map) {
      throw Exception('No pedestrian route was returned for this destination.');
    }

    final legsValue = trip['legs'];
    if (legsValue is! List || legsValue.isEmpty) {
      throw Exception('No pedestrian route was found.');
    }

    final points = <LatLng>[];
    final steps = <NavigationStep>[];

    for (final legValue in legsValue) {
      if (legValue is! Map) continue;

      final shape = legValue['shape']?.toString() ?? '';
      if (shape.isNotEmpty) {
        final decodedPoints = _decodePolyline6(shape);
        if (points.isNotEmpty && decodedPoints.isNotEmpty) {
          decodedPoints.removeAt(0);
        }
        points.addAll(decodedPoints);
      }

      final maneuvers = legValue['maneuvers'];
      if (maneuvers is List) {
        for (final maneuverValue in maneuvers) {
          if (maneuverValue is! Map) continue;

          final instruction = maneuverValue['instruction']?.toString().trim();
          if (instruction == null || instruction.isEmpty) continue;

          steps.add(
            NavigationStep(
              instruction: instruction,
              distanceKm: _asDouble(maneuverValue['length']),
              timeSeconds: _asDouble(maneuverValue['time']),
              beginShapeIndex: _asInt(maneuverValue['begin_shape_index']),
              endShapeIndex: _asInt(maneuverValue['end_shape_index']),
            ),
          );
        }
      }
    }

    if (points.length < 2) {
      throw Exception('The returned route did not contain a usable path.');
    }

    final summary = trip['summary'];
    final distanceKm = summary is Map
        ? _asDouble(summary['length'])
        : _routeDistanceFromLegs(legsValue);
    final timeSeconds = summary is Map
        ? _asDouble(summary['time'])
        : _routeTimeFromLegs(legsValue);

    return HeritageNavigationRoute(
      points: points,
      distanceKm: distanceKm,
      timeSeconds: timeSeconds,
      steps: steps,
    );
  }

  double _routeDistanceFromLegs(List<dynamic> legs) {
    var total = 0.0;
    for (final leg in legs) {
      if (leg is Map && leg['summary'] is Map) {
        total += _asDouble((leg['summary'] as Map)['length']);
      }
    }
    return total;
  }

  double _routeTimeFromLegs(List<dynamic> legs) {
    var total = 0.0;
    for (final leg in legs) {
      if (leg is Map && leg['summary'] is Map) {
        total += _asDouble((leg['summary'] as Map)['time']);
      }
    }
    return total;
  }

  double _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  List<LatLng> _decodePolyline6(String encoded) {
    final points = <LatLng>[];
    var index = 0;
    var latitude = 0;
    var longitude = 0;

    while (index < encoded.length) {
      var result = 0;
      var shift = 0;
      int byte;

      do {
        if (index >= encoded.length) {
          throw Exception('Navigation route shape is incomplete.');
        }
        byte = encoded.codeUnitAt(index++) - 63;
        result |= (byte & 0x1f) << shift;
        shift += 5;
      } while (byte >= 0x20);

      final deltaLatitude = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      latitude += deltaLatitude;

      result = 0;
      shift = 0;

      do {
        if (index >= encoded.length) {
          throw Exception('Navigation route shape is incomplete.');
        }
        byte = encoded.codeUnitAt(index++) - 63;
        result |= (byte & 0x1f) << shift;
        shift += 5;
      } while (byte >= 0x20);

      final deltaLongitude = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      longitude += deltaLongitude;

      points.add(LatLng(latitude / 1000000.0, longitude / 1000000.0));
    }

    return points;
  }
}
