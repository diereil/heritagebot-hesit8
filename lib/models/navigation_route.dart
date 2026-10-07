import 'package:latlong2/latlong.dart';

class NavigationStep {
  final String instruction;
  final double distanceKm;
  final double timeSeconds;
  final int beginShapeIndex;
  final int endShapeIndex;

  const NavigationStep({
    required this.instruction,
    required this.distanceKm,
    required this.timeSeconds,
    required this.beginShapeIndex,
    required this.endShapeIndex,
  });
}

class HeritageNavigationRoute {
  final List<LatLng> points;
  final double distanceKm;
  final double timeSeconds;
  final List<NavigationStep> steps;

  const HeritageNavigationRoute({
    required this.points,
    required this.distanceKm,
    required this.timeSeconds,
    required this.steps,
  });
}
